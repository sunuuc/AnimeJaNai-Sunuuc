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

#ifndef LIBASS_THREADING_H
#define LIBASS_THREADING_H

#include "config.h"

#include <stddef.h>
#include <stdbool.h>

/*
 * This header provides two layers:
 *
 *  1. Lock and atomic-refcount wrappers (ass_mutex_*, ass_atomic_*) that are
 *     defined in BOTH threaded and non-threaded builds. With CONFIG_THREADS
 *     off they collapse to no-op locks and plain integer arithmetic, so code
 *     such as ass_cache.c can use them unconditionally without #ifdef.
 *
 *  2. A persistent worker ThreadPool, declared only when CONFIG_THREADS is on.
 */

#if CONFIG_THREADS

#ifdef _WIN32

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

typedef SRWLOCK            ass_mutex_t;
typedef CONDITION_VARIABLE ass_cond_t;

static inline int  ass_mutex_init(ass_mutex_t *m)    { InitializeSRWLock(m); return 0; }
static inline void ass_mutex_destroy(ass_mutex_t *m) { (void) m; }
static inline void ass_mutex_lock(ass_mutex_t *m)    { AcquireSRWLockExclusive(m); }
static inline void ass_mutex_unlock(ass_mutex_t *m)  { ReleaseSRWLockExclusive(m); }

static inline int  ass_cond_init(ass_cond_t *c)      { InitializeConditionVariable(c); return 0; }
static inline void ass_cond_destroy(ass_cond_t *c)   { (void) c; }
static inline void ass_cond_wait(ass_cond_t *c, ass_mutex_t *m)
                                                     { SleepConditionVariableSRW(c, m, INFINITE, 0); }
static inline void ass_cond_signal(ass_cond_t *c)    { WakeConditionVariable(c); }
static inline void ass_cond_broadcast(ass_cond_t *c) { WakeAllConditionVariable(c); }

// Recursive mutex (CRITICAL_SECTION is recursive).
typedef CRITICAL_SECTION ass_rmutex_t;
static inline int  ass_rmutex_init(ass_rmutex_t *m)    { InitializeCriticalSection(m); return 0; }
static inline void ass_rmutex_destroy(ass_rmutex_t *m) { DeleteCriticalSection(m); }
static inline void ass_rmutex_lock(ass_rmutex_t *m)    { EnterCriticalSection(m); }
static inline void ass_rmutex_unlock(ass_rmutex_t *m)  { LeaveCriticalSection(m); }

#else // POSIX

#include <pthread.h>

typedef pthread_mutex_t ass_mutex_t;
typedef pthread_cond_t  ass_cond_t;

static inline int  ass_mutex_init(ass_mutex_t *m)    { return pthread_mutex_init(m, NULL); }
static inline void ass_mutex_destroy(ass_mutex_t *m) { pthread_mutex_destroy(m); }
static inline void ass_mutex_lock(ass_mutex_t *m)    { pthread_mutex_lock(m); }
static inline void ass_mutex_unlock(ass_mutex_t *m)  { pthread_mutex_unlock(m); }

static inline int  ass_cond_init(ass_cond_t *c)      { return pthread_cond_init(c, NULL); }
static inline void ass_cond_destroy(ass_cond_t *c)   { pthread_cond_destroy(c); }
static inline void ass_cond_wait(ass_cond_t *c, ass_mutex_t *m)
                                                     { pthread_cond_wait(c, m); }
static inline void ass_cond_signal(ass_cond_t *c)    { pthread_cond_signal(c); }
static inline void ass_cond_broadcast(ass_cond_t *c) { pthread_cond_broadcast(c); }

// Recursive mutex, for locks that may be re-entered on the same thread
// (e.g. HarfBuzz shaping callbacks that re-enter the metrics cache).
typedef pthread_mutex_t ass_rmutex_t;
static inline int ass_rmutex_init(ass_rmutex_t *m)
{
    pthread_mutexattr_t attr;
    if (pthread_mutexattr_init(&attr) != 0)
        return -1;
    pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
    int ret = pthread_mutex_init(m, &attr);
    pthread_mutexattr_destroy(&attr);
    return ret;
}
static inline void ass_rmutex_destroy(ass_rmutex_t *m) { pthread_mutex_destroy(m); }
static inline void ass_rmutex_lock(ass_rmutex_t *m)    { pthread_mutex_lock(m); }
static inline void ass_rmutex_unlock(ass_rmutex_t *m)  { pthread_mutex_unlock(m); }

#endif // _WIN32

// --- Atomics ---------------------------------------------------------------
// Refcounts and the LRU frame stamp. Increment/decrement return the new value.

#if defined(__STDC_NO_ATOMICS__) && defined(_MSC_VER)

// Old MSVC without <stdatomic.h>: fall back to Interlocked intrinsics.
// size_t-wide ops map onto the pointer-sized Interlocked variants.
#include <intrin.h>

typedef volatile size_t   ass_atomic_size_t;
typedef volatile unsigned ass_atomic_uint_t;

#if defined(_WIN64)
#define ASS_ILACTYPE __int64
#define ASS_ILADD    _InterlockedExchangeAdd64
#define ASS_ILEXCH   _InterlockedExchange64
#else
#define ASS_ILACTYPE long
#define ASS_ILADD    _InterlockedExchangeAdd
#define ASS_ILEXCH   _InterlockedExchange
#endif

static inline size_t ass_atomic_inc_size(ass_atomic_size_t *p)
{ return (size_t) ASS_ILADD((volatile ASS_ILACTYPE *) p, 1) + 1; }
static inline size_t ass_atomic_dec_size(ass_atomic_size_t *p)
{ return (size_t) ASS_ILADD((volatile ASS_ILACTYPE *) p, -1) - 1; }
static inline size_t ass_atomic_load_size(const ass_atomic_size_t *p)
{ return *p; }
static inline void   ass_atomic_store_size(ass_atomic_size_t *p, size_t v)
{ ASS_ILEXCH((volatile ASS_ILACTYPE *) p, (ASS_ILACTYPE) v); }

// Publication/consumption pair: Interlocked intrinsics are full barriers,
// which subsumes the release/acquire these require. The acquire load is an
// interlocked add of 0 so it carries the barrier on all MSVC targets
// (a plain volatile read is only acquire under /volatile:ms).
static inline size_t ass_atomic_inc_size_release(ass_atomic_size_t *p)
{ return (size_t) ASS_ILADD((volatile ASS_ILACTYPE *) p, 1) + 1; }
static inline size_t ass_atomic_load_size_acquire(const ass_atomic_size_t *p)
{ return (size_t) ASS_ILADD((volatile ASS_ILACTYPE *) (ass_atomic_size_t *) p, 0); }

static inline unsigned ass_atomic_load_uint(const ass_atomic_uint_t *p)
{ return *p; }
static inline void     ass_atomic_store_uint(ass_atomic_uint_t *p, unsigned v)
{ _InterlockedExchange((volatile long *) p, (long) v); }
static inline unsigned ass_atomic_add_uint(ass_atomic_uint_t *p, unsigned n)
{ return (unsigned) _InterlockedExchangeAdd((volatile long *) p, (long) n); }

#else

#include <stdatomic.h>

typedef atomic_size_t     ass_atomic_size_t;
typedef atomic_uint       ass_atomic_uint_t;

static inline size_t ass_atomic_inc_size(ass_atomic_size_t *p)
{ return atomic_fetch_add_explicit(p, 1, memory_order_relaxed) + 1; }
static inline size_t ass_atomic_dec_size(ass_atomic_size_t *p)
{ return atomic_fetch_sub_explicit(p, 1, memory_order_acq_rel) - 1; }
static inline size_t ass_atomic_load_size(const ass_atomic_size_t *p)
{ return atomic_load_explicit(p, memory_order_relaxed); }
static inline void   ass_atomic_store_size(ass_atomic_size_t *p, size_t v)
{ atomic_store_explicit(p, v, memory_order_relaxed); }

// Publication/consumption pair for counters that hand data between threads
// (the thread pool's per-region completion count): every incrementer releases
// its preceding writes, and a load-acquire that observes the final value
// synchronizes with all of them (the increments are RMWs, so each release's
// release sequence extends through the later increments).
static inline size_t ass_atomic_inc_size_release(ass_atomic_size_t *p)
{ return atomic_fetch_add_explicit(p, 1, memory_order_release) + 1; }
static inline size_t ass_atomic_load_size_acquire(const ass_atomic_size_t *p)
{ return atomic_load_explicit(p, memory_order_acquire); }

static inline unsigned ass_atomic_load_uint(const ass_atomic_uint_t *p)
{ return atomic_load_explicit(p, memory_order_relaxed); }
static inline void     ass_atomic_store_uint(ass_atomic_uint_t *p, unsigned v)
{ atomic_store_explicit(p, v, memory_order_relaxed); }
static inline unsigned ass_atomic_add_uint(ass_atomic_uint_t *p, unsigned n)
{ return atomic_fetch_add_explicit(p, n, memory_order_relaxed); }

#endif // atomics backend

// --- Thread pool -----------------------------------------------------------

typedef struct ass_thread_pool ASS_ThreadPool;

// Create a pool with n_threads persistent workers (n_threads >= 1).
// Returns NULL on failure.
ASS_ThreadPool *ass_thread_pool_create(size_t n_threads);

// Join all workers and free the pool.
void ass_thread_pool_destroy(ASS_ThreadPool *pool);

// Number of worker threads in the pool.
size_t ass_thread_pool_nthreads(ASS_ThreadPool *pool);

// Run task(arg, index, worker_id) for every index in [0, count) across the
// pool's workers, then block until all have finished. The calling thread also
// participates as a worker. Output slots are caller-partitioned by index, so
// completion order does not affect results. Nestable: a task may itself call
// this (a thread waiting for its tasks helps run others meanwhile).
//
// exclusive marks tasks that own the executing thread's per-thread scratch
// (worker_id-indexed): a thread already running one will not start another, so
// such tasks never run nested on the same thread. Non-exclusive tasks (e.g.
// blur stripes) may be helped from anywhere.
void ass_thread_pool_run(ASS_ThreadPool *pool, size_t count,
                         void (*task)(void *arg, size_t index, size_t worker_id),
                         void *arg, bool exclusive);

// Number of online logical CPUs, clamped to >= 1.
size_t ass_get_cpu_count(void);

#else // !CONFIG_THREADS

// No-op lock so lock-using code compiles unchanged in single-threaded builds.
typedef char ass_mutex_t;
static inline int  ass_mutex_init(ass_mutex_t *m)    { (void) m; return 0; }
static inline void ass_mutex_destroy(ass_mutex_t *m) { (void) m; }
static inline void ass_mutex_lock(ass_mutex_t *m)    { (void) m; }
static inline void ass_mutex_unlock(ass_mutex_t *m)  { (void) m; }

typedef char ass_rmutex_t;
static inline int  ass_rmutex_init(ass_rmutex_t *m)    { (void) m; return 0; }
static inline void ass_rmutex_destroy(ass_rmutex_t *m) { (void) m; }
static inline void ass_rmutex_lock(ass_rmutex_t *m)    { (void) m; }
static inline void ass_rmutex_unlock(ass_rmutex_t *m)  { (void) m; }

typedef size_t   ass_atomic_size_t;
typedef unsigned ass_atomic_uint_t;

static inline size_t ass_atomic_inc_size(ass_atomic_size_t *p)        { return ++(*p); }
static inline size_t ass_atomic_dec_size(ass_atomic_size_t *p)        { return --(*p); }
static inline size_t ass_atomic_load_size(const ass_atomic_size_t *p) { return *p; }
static inline void   ass_atomic_store_size(ass_atomic_size_t *p, size_t v) { *p = v; }

static inline size_t ass_atomic_inc_size_release(ass_atomic_size_t *p)        { return ++(*p); }
static inline size_t ass_atomic_load_size_acquire(const ass_atomic_size_t *p) { return *p; }

static inline unsigned ass_atomic_load_uint(const ass_atomic_uint_t *p) { return *p; }
static inline void     ass_atomic_store_uint(ass_atomic_uint_t *p, unsigned v) { *p = v; }
static inline unsigned ass_atomic_add_uint(ass_atomic_uint_t *p, unsigned n) { unsigned o = *p; *p += n; return o; }

#endif // CONFIG_THREADS

#endif // LIBASS_THREADING_H
