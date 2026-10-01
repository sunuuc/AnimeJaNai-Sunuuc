/*
 * Copyright (C) 2026 libass contributors
 *
 * This file is part of libass.
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 */

#include "config.h"
#include "ass_compat.h"

#if CONFIG_THREADS

#include <stdlib.h>
#include <stdbool.h>

#include "ass_threading.h"

#ifdef _WIN32
#include <process.h>  // _beginthreadex
typedef HANDLE ass_native_thread_t;
#else
#include <unistd.h>
typedef pthread_t ass_native_thread_t;
#endif

#include <stdint.h>

#if defined(_MSC_VER)
#define ASS_TLS __declspec(thread)
#else
#define ASS_TLS __thread
#endif

// One outstanding parallel_for. Regions live on their owner's stack and are
// linked into the pool's active list while running. Several can be active at
// once (e.g. blur regions from different events rendering in parallel).
typedef struct task_region {
    void (*fn)(void *arg, size_t index, size_t thread_id);
    void *arg;
    size_t count;
    size_t next;                  // next unclaimed index (guarded by pool->lock)
    ass_atomic_size_t done;       // completed count (atomic; read lock-free)
    bool exclusive;               // task owns the thread's per-thread scratch,
                                  // so a thread may run only one at a time
    struct task_region *prev, *nxt;
} TaskRegion;

struct ass_thread_pool {
    ass_mutex_t lock;
    ass_cond_t  cond;             // new work, region progress, or shutdown
    size_t n_threads;             // total parallelism incl. the caller's slot
    size_t n_workers;             // spawned worker threads (== n_threads - 1)
    ass_native_thread_t *threads;
    TaskRegion *head;             // most-recently pushed active region
    size_t ready_workers;
    bool   shutdown;
};

// Stable per-thread id, used to index per-thread scratch (RenderContext).
// SIZE_MAX marks a thread that is not a pool worker (an outside caller).
static ASS_TLS size_t tls_thread_id = SIZE_MAX;

// How many exclusive tasks the current thread is nested in. While > 0 it may
// not start another exclusive task (that would reuse its per-thread scratch),
// but it may still help with non-exclusive work (e.g. blur stripes).
static ASS_TLS int tls_excl_depth;

struct worker_arg {
    ASS_ThreadPool *pool;
    size_t worker_id;
};

// Find the first active region with an unclaimed index and claim it.
// Caller must hold pool->lock. Returns NULL if no work is currently claimable.
static TaskRegion *claim_index(ASS_ThreadPool *pool, size_t *out_idx)
{
    for (TaskRegion *r = pool->head; r; r = r->nxt) {
        if (r->exclusive && tls_excl_depth)
            continue;   // can't nest a second exclusive task on this thread
        if (r->next < r->count) {
            *out_idx = r->next++;
            return r;
        }
    }
    return NULL;
}

// Run one claimed task. Enters and leaves with pool->lock held, but drops it
// while executing the task body.
static void run_claimed(ASS_ThreadPool *pool, TaskRegion *r, size_t idx,
                        size_t my_id)
{
    ass_mutex_unlock(&pool->lock);
    size_t saved = tls_thread_id;
    tls_thread_id = my_id;
    if (r->exclusive)
        tls_excl_depth++;
    r->fn(r->arg, idx, my_id);
    if (r->exclusive)
        tls_excl_depth--;
    tls_thread_id = saved;
    // Read count BEFORE the final increment: the moment done reaches count,
    // the region's owner may unlink the region and return, and *r (which
    // lives in the owner's stack frame) dies with it. Only pool-owned state
    // may be touched from here on.
    size_t count = r->count;
    // Release: publish this task body's writes (rendered bitmaps, cache
    // items, ...) to the region owner, whose load-acquire of done pairs with
    // every incrementer via the RMW release sequence. Without this edge the
    // owner's post-run reads of worker-produced data are a C11 data race.
    size_t d = ass_atomic_inc_size_release(&r->done);
    ass_mutex_lock(&pool->lock);
    if (d == count)
        ass_cond_broadcast(&pool->cond);   // the region's owner may be waiting
}

static void worker_loop(ASS_ThreadPool *pool, size_t worker_id)
{
    tls_thread_id = worker_id;
    ass_mutex_lock(&pool->lock);

    // Announce readiness so pool creation can't return (and thus no job can be
    // posted) before every worker is parked here. The creator re-checks the
    // count, so we never read n_workers (which it may still be finalizing).
    pool->ready_workers++;
    ass_cond_broadcast(&pool->cond);

    for (;;) {
        size_t idx;
        TaskRegion *r = claim_index(pool, &idx);
        if (r) {
            run_claimed(pool, r, idx, worker_id);
            continue;
        }
        if (pool->shutdown)
            break;
        ass_cond_wait(&pool->cond, &pool->lock);
    }
    ass_mutex_unlock(&pool->lock);
}

#ifdef _WIN32
static unsigned __stdcall worker_entry(void *data)
#else
static void *worker_entry(void *data)
#endif
{
    struct worker_arg *wa = data;
    ASS_ThreadPool *pool = wa->pool;
    size_t worker_id = wa->worker_id;
    free(wa);
    worker_loop(pool, worker_id);
#ifdef _WIN32
    return 0;
#else
    return NULL;
#endif
}

static bool thread_start(ass_native_thread_t *t, struct worker_arg *wa)
{
#ifdef _WIN32
    HANDLE h = (HANDLE) _beginthreadex(NULL, 0, worker_entry, wa, 0, NULL);
    if (!h)
        return false;
    *t = h;
    return true;
#else
    return pthread_create(t, NULL, worker_entry, wa) == 0;
#endif
}

static void thread_join(ass_native_thread_t t)
{
#ifdef _WIN32
    WaitForSingleObject(t, INFINITE);
    CloseHandle(t);
#else
    pthread_join(t, NULL);
#endif
}

ASS_ThreadPool *ass_thread_pool_create(size_t n_threads)
{
    if (n_threads < 1)
        n_threads = 1;

    ASS_ThreadPool *pool = calloc(1, sizeof(*pool));
    if (!pool)
        return NULL;

    pool->n_threads = n_threads;
    pool->n_workers = n_threads - 1;

    bool lock_ok = ass_mutex_init(&pool->lock) == 0;
    bool cond_ok = lock_ok && ass_cond_init(&pool->cond) == 0;
    if (!cond_ok) {
        if (lock_ok)
            ass_mutex_destroy(&pool->lock);
        free(pool);
        return NULL;
    }

    if (pool->n_workers) {
        pool->threads = calloc(pool->n_workers, sizeof(*pool->threads));
        if (!pool->threads) {
            ass_thread_pool_destroy(pool);
            return NULL;
        }

        size_t started = 0;
        for (size_t i = 0; i < pool->n_workers; i++) {
            struct worker_arg *wa = malloc(sizeof(*wa));
            if (!wa)
                break;
            wa->pool = pool;
            wa->worker_id = i;
            if (!thread_start(&pool->threads[i], wa)) {
                free(wa);
                break;
            }
            started++;
        }

        // If not all workers started, run with however many we got rather
        // than fail outright; correctness does not depend on the count.
        // Finalize n_workers and wait for every started worker to park in its
        // wait loop, all under the lock (workers never read n_workers).
        ass_mutex_lock(&pool->lock);
        pool->n_workers = started;
        while (pool->ready_workers < started)
            ass_cond_wait(&pool->cond, &pool->lock);
        ass_mutex_unlock(&pool->lock);

        pool->n_threads = started + 1;
    }

    return pool;
}

void ass_thread_pool_destroy(ASS_ThreadPool *pool)
{
    if (!pool)
        return;

    if (pool->n_workers) {
        ass_mutex_lock(&pool->lock);
        pool->shutdown = true;
        ass_cond_broadcast(&pool->cond);
        ass_mutex_unlock(&pool->lock);

        for (size_t i = 0; i < pool->n_workers; i++)
            thread_join(pool->threads[i]);
    }
    free(pool->threads);

    ass_cond_destroy(&pool->cond);
    ass_mutex_destroy(&pool->lock);
    free(pool);
}

size_t ass_thread_pool_nthreads(ASS_ThreadPool *pool)
{
    return pool->n_threads;
}

// Nestable parallel-for: runs task(arg, index, thread_id) for index in
// [0, count). Safe to call from an outside thread OR from within a running
// task (a worker), because a thread waiting for its own region to finish
// helps execute any other claimable work meanwhile, so nesting cannot
// deadlock. thread_id is the executing thread's stable slot, usable to index
// per-thread scratch.
void ass_thread_pool_run(ASS_ThreadPool *pool, size_t count,
                         void (*task)(void *arg, size_t index, size_t worker_id),
                         void *arg, bool exclusive)
{
    if (!count)
        return;

    size_t my_id = tls_thread_id;
    bool external = my_id == SIZE_MAX;
    if (external)
        my_id = pool->n_workers;   // the outside caller's stable slot

    // No helper threads: run inline.
    if (!pool->n_workers) {
        size_t saved = tls_thread_id;
        tls_thread_id = my_id;
        for (size_t i = 0; i < count; i++)
            task(arg, i, my_id);
        tls_thread_id = saved;
        return;
    }

    TaskRegion r = { .fn = task, .arg = arg, .count = count, .next = 0,
                     .exclusive = exclusive };
    ass_atomic_store_size(&r.done, 0);

    ass_mutex_lock(&pool->lock);
    // Publish at the list head and wake idle workers to help.
    r.prev = NULL;
    r.nxt = pool->head;
    if (pool->head)
        pool->head->prev = &r;
    pool->head = &r;
    ass_cond_broadcast(&pool->cond);

    // Help until this region is fully done; drain other regions while waiting.
    for (;;) {
        size_t idx;
        TaskRegion *pr = claim_index(pool, &idx);
        if (pr) {
            run_claimed(pool, pr, idx, my_id);
            continue;
        }
        // Acquire pairs with the workers' release increments: observing
        // done == count makes every task body's writes visible before we
        // unlink the region and let the caller consume the results (and
        // before this stack frame -- holding the region -- is reused).
        if (ass_atomic_load_size_acquire(&r.done) == count)
            break;
        ass_cond_wait(&pool->cond, &pool->lock);
    }

    // Unlink our region.
    if (r.prev)
        r.prev->nxt = r.nxt;
    else
        pool->head = r.nxt;
    if (r.nxt)
        r.nxt->prev = r.prev;
    ass_mutex_unlock(&pool->lock);
}

size_t ass_get_cpu_count(void)
{
#ifdef _WIN32
    SYSTEM_INFO si;
    GetSystemInfo(&si);
    size_t n = si.dwNumberOfProcessors;
#else
    long n = sysconf(_SC_NPROCESSORS_ONLN);
#endif
    return n >= 1 ? (size_t) n : 1;
}

#endif // CONFIG_THREADS
