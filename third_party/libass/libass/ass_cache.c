/*
 * Copyright (C) 2006 Evgeniy Stepanov <eugeni.stepanov@gmail.com>
 * Copyright (C) 2011 Grigori Goronzy <greg@chown.ath.cx>
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

#include <inttypes.h>
#include <ft2build.h>
#include FT_OUTLINE_H
#include <assert.h>

#include "ass_utils.h"
#include "ass_font.h"
#include "ass_outline.h"
#include "ass_cache.h"
#include "ass_threading.h"

// Always enable native-endian mode, since we don't care about cross-platform consistency of the hash
#define WYHASH_LITTLE_ENDIAN 1
#include "wyhash.h"

// With wyhash any arbitrary 64 bit value will suffice
#define ASS_HASH_INIT 0xb3e46a540bd36cd4ULL

static inline ass_hashcode ass_hash_buf(const void *buf, size_t len, ass_hashcode hval)
{
    return wyhash(buf, len, hval, _wyp);
}

// type-specific functions
// create hash/compare functions for bitmap, outline and composite cache
#define CREATE_HASH_FUNCTIONS
#include "ass_cache_template.h"
#define CREATE_COMPARISON_FUNCTIONS
#include "ass_cache_template.h"

// font cache
static bool font_key_move(void *dst, void *src)
{
    ASS_FontDesc *d = dst, *s = src;
    if (!d)
        return true;

    *d = *s;
    d->family.str = ass_copy_string(s->family);
    return d->family.str;
}

static void font_destruct(void *key, void *value)
{
    ass_font_clear(value);
}

size_t ass_font_construct(void *key, void *value, void *priv);

const CacheDesc font_cache_desc = {
    .hash_func = font_hash,
    .compare_func = font_compare,
    .key_move_func = font_key_move,
    .construct_func = ass_font_construct,
    .destruct_func = font_destruct,
    .key_size = sizeof(ASS_FontDesc),
    .value_size = sizeof(ASS_Font)
};


// bitmap cache
static bool bitmap_key_move(void *dst, void *src)
{
    BitmapHashKey *d = dst, *s = src;
    if (d) {
        *d = *s;
        ass_cache_inc_ref(d->outline);
    }
    return true;
}

static void bitmap_destruct(void *key, void *value)
{
    BitmapHashKey *k = key;
    ass_free_bitmap(value);
    ass_cache_dec_ref(k->outline);
}

size_t ass_bitmap_construct(void *key, void *value, void *priv);

const CacheDesc bitmap_cache_desc = {
    .hash_func = bitmap_hash,
    .compare_func = bitmap_compare,
    .key_move_func = bitmap_key_move,
    .construct_func = ass_bitmap_construct,
    .destruct_func = bitmap_destruct,
    .key_size = sizeof(BitmapHashKey),
    .value_size = sizeof(Bitmap)
};


// composite cache
static ass_hashcode composite_hash(void *key, ass_hashcode hval)
{
    CompositeHashKey *k = key;
    hval = filter_hash(&k->filter, hval);
    for (size_t i = 0; i < k->bitmap_count; i++)
        hval = bitmap_ref_hash(&k->bitmaps[i], hval);
    return hval;
}

static bool composite_compare(void *a, void *b)
{
    CompositeHashKey *ak = a;
    CompositeHashKey *bk = b;
    if (!filter_compare(&ak->filter, &bk->filter))
        return false;
    if (ak->bitmap_count != bk->bitmap_count)
        return false;
    for (size_t i = 0; i < ak->bitmap_count; i++)
        if (!bitmap_ref_compare(&ak->bitmaps[i], &bk->bitmaps[i]))
            return false;
    return true;
}

static bool composite_key_move(void *dst, void *src)
{
    CompositeHashKey *d = dst, *s = src;
    if (d) {
        *d = *s;
        for (size_t i = 0; i < d->bitmap_count; i++) {
            ass_cache_inc_ref(d->bitmaps[i].bm);
            ass_cache_inc_ref(d->bitmaps[i].bm_o);
        }
        return true;
    }

    free(s->bitmaps);
    return true;
}

static void composite_destruct(void *key, void *value)
{
    CompositeHashValue *v = value;
    CompositeHashKey *k = key;
    ass_free_bitmap(&v->bm);
    ass_free_bitmap(&v->bm_o);
    ass_free_bitmap(&v->bm_s);
    for (size_t i = 0; i < k->bitmap_count; i++) {
        ass_cache_dec_ref(k->bitmaps[i].bm);
        ass_cache_dec_ref(k->bitmaps[i].bm_o);
    }
    free(k->bitmaps);
}

size_t ass_composite_construct(void *key, void *value, void *priv);

const CacheDesc composite_cache_desc = {
    .hash_func = composite_hash,
    .compare_func = composite_compare,
    .key_move_func = composite_key_move,
    .construct_func = ass_composite_construct,
    .destruct_func = composite_destruct,
    .key_size = sizeof(CompositeHashKey),
    .value_size = sizeof(CompositeHashValue)
};


// outline cache
static ass_hashcode outline_hash(void *key, ass_hashcode hval)
{
    OutlineHashKey *k = key;
    switch (k->type) {
    case OUTLINE_GLYPH:
        return glyph_hash(&k->u, hval);
    case OUTLINE_DRAWING:
        return drawing_hash(&k->u, hval);
    case OUTLINE_BORDER:
        return border_hash(&k->u, hval);
    default:  // OUTLINE_BOX
        return hval;
    }
}

static bool outline_compare(void *a, void *b)
{
    OutlineHashKey *ak = a;
    OutlineHashKey *bk = b;
    if (ak->type != bk->type)
        return false;
    switch (ak->type) {
    case OUTLINE_GLYPH:
        return glyph_compare(&ak->u, &bk->u);
    case OUTLINE_DRAWING:
        return drawing_compare(&ak->u, &bk->u);
    case OUTLINE_BORDER:
        return border_compare(&ak->u, &bk->u);
    default:  // OUTLINE_BOX
        return true;
    }
}

static bool outline_key_move(void *dst, void *src)
{
    OutlineHashKey *d = dst, *s = src;
    if (!d)
        return true;

    *d = *s;
    if (s->type == OUTLINE_DRAWING) {
        d->u.drawing.text.str = ass_copy_string(s->u.drawing.text);
        return d->u.drawing.text.str;
    }
    if (s->type == OUTLINE_BORDER)
        ass_cache_inc_ref(s->u.border.outline);
    else if (s->type == OUTLINE_GLYPH)
        ass_cache_inc_ref(s->u.glyph.font);
    return true;
}

static void outline_destruct(void *key, void *value)
{
    OutlineHashValue *v = value;
    OutlineHashKey *k = key;
    ass_outline_free(&v->outline[0]);
    ass_outline_free(&v->outline[1]);
    switch (k->type) {
    case OUTLINE_GLYPH:
        ass_cache_dec_ref(k->u.glyph.font);
        break;
    case OUTLINE_DRAWING:
        free((char *) k->u.drawing.text.str);
        break;
    case OUTLINE_BORDER:
        ass_cache_dec_ref(k->u.border.outline);
        break;
    default:  // OUTLINE_BOX
        break;
    }
}

size_t ass_outline_construct(void *key, void *value, void *priv);

const CacheDesc outline_cache_desc = {
    .hash_func = outline_hash,
    .compare_func = outline_compare,
    .key_move_func = outline_key_move,
    .construct_func = ass_outline_construct,
    .destruct_func = outline_destruct,
    .key_size = sizeof(OutlineHashKey),
    .value_size = sizeof(OutlineHashValue)
};


// font-face size metric cache
static bool face_size_metrics_key_move(void *dst, void *src)
{
    FaceSizeMetricsHashKey *d = dst, *s = src;
    if (!d)
        return true;

    *d = *s;
    ass_cache_inc_ref(s->font);
    return true;
}

static void face_size_metrics_destruct(void *key, void *value)
{
    FaceSizeMetricsHashKey *k = key;
    ass_cache_dec_ref(k->font);
}

size_t ass_face_size_metrics_construct(void *key, void *value, void *priv);

const CacheDesc face_size_metrics_cache_desc = {
    .hash_func = face_size_metrics_hash,
    .compare_func = face_size_metrics_compare,
    .key_move_func = face_size_metrics_key_move,
    .construct_func = ass_face_size_metrics_construct,
    .destruct_func = face_size_metrics_destruct,
    .key_size = sizeof(FaceSizeMetricsHashKey),
    .value_size = sizeof(FT_Size_Metrics)
};


// glyph metric cache
static bool glyph_metrics_key_move(void *dst, void *src)
{
    GlyphMetricsHashKey *d = dst, *s = src;
    if (!d)
        return true;

    *d = *s;
    ass_cache_inc_ref(s->font);
    return true;
}

static void glyph_metrics_destruct(void *key, void *value)
{
    GlyphMetricsHashKey *k = key;
    ass_cache_dec_ref(k->font);
}

size_t ass_glyph_metrics_construct(void *key, void *value, void *priv);

const CacheDesc glyph_metrics_cache_desc = {
    .hash_func = glyph_metrics_hash,
    .compare_func = glyph_metrics_compare,
    .key_move_func = glyph_metrics_key_move,
    .construct_func = ass_glyph_metrics_construct,
    .destruct_func = glyph_metrics_destruct,
    .key_size = sizeof(GlyphMetricsHashKey),
    .value_size = sizeof(FT_Glyph_Metrics)
};



// Cache data
//
// The cache is split into N_CACHE_SHARDS independently locked shards, each with
// its own hash map, LRU queue and size counter. A key's shard and bucket are
// both derived from its hash, using disjoint bit ranges so the two are
// independent. Sharding bounds lock contention when worker threads render
// events in parallel; the total bucket count is kept close to the original
// single-map size so per-shard chains stay short.
//
// Reference counting: an item's ref_count counts external holders plus one
// while the item sits in its shard's LRU queue ("the queue reference").
// Increments/decrements are lock-free atomics; only the final drop to zero
// (which may free the item) and the LRU surgery take the shard lock.
//
// ass_cache_cut()/ass_cache_empty()/ass_cache_done() must only run while no
// worker threads touch the cache (between frames); they manipulate shard state
// without taking the locks, relying on that external serialization.

#define N_CACHE_SHARDS      64     // must be a power of two
#define CACHE_SHARD_BUCKETS 1024   // per shard, power of two (total ~= 65536)

typedef struct cache_item {
    struct cache_shard *shard;  // owning shard, or NULL once detached
    const CacheDesc *desc;
    struct cache_item *next, **prev;
    struct cache_item *queue_next, **queue_prev;
    size_t size;
    ass_atomic_size_t ref_count;
} CacheItem;

typedef struct cache_shard {
    ass_mutex_t mutex;
    CacheItem **map;
    CacheItem *queue_first, **queue_last;
    size_t cache_size;
} CacheShard;

struct cache {
    const CacheDesc *desc;
    CacheShard shards[N_CACHE_SHARDS];
};

#define CACHE_ALIGN 8
#define CACHE_ITEM_SIZE ((sizeof(CacheItem) + (CACHE_ALIGN - 1)) & ~(CACHE_ALIGN - 1))

static inline size_t align_cache(size_t size)
{
    return (size + (CACHE_ALIGN - 1)) & ~(CACHE_ALIGN - 1);
}

static inline CacheItem *value_to_item(void *value)
{
    return (CacheItem *) ((char *) value - CACHE_ITEM_SIZE);
}

// Map a hash to a shard and an in-shard bucket using disjoint bit ranges.
static inline CacheShard *hash_to_shard(Cache *cache, ass_hashcode hash,
                                        unsigned *bucket)
{
    *bucket = (unsigned) (hash & (CACHE_SHARD_BUCKETS - 1));
    size_t idx = (size_t) (hash >> 40) & (N_CACHE_SHARDS - 1);
    return &cache->shards[idx];
}


// Create a cache with type-specific hash/compare/destruct/size functions
Cache *ass_cache_create(const CacheDesc *desc)
{
    Cache *cache = calloc(1, sizeof(*cache));
    if (!cache)
        return NULL;
    cache->desc = desc;

    size_t i;
    for (i = 0; i < N_CACHE_SHARDS; i++) {
        CacheShard *shard = &cache->shards[i];
        shard->queue_last = &shard->queue_first;
        if (ass_mutex_init(&shard->mutex) != 0)
            break;
        shard->map = calloc(CACHE_SHARD_BUCKETS, sizeof(CacheItem *));
        if (!shard->map) {
            ass_mutex_destroy(&shard->mutex);
            break;
        }
    }
    if (i < N_CACHE_SHARDS) {
        for (size_t j = 0; j < i; j++) {
            ass_mutex_destroy(&cache->shards[j].mutex);
            free(cache->shards[j].map);
        }
        free(cache);
        return NULL;
    }

    return cache;
}

// Find an item for key in the given bucket. Shard lock must be held.
static inline CacheItem *find_item(CacheShard *shard, const CacheDesc *desc,
                                   unsigned bucket, void *key, size_t key_offs)
{
    CacheItem *item = shard->map[bucket];
    while (item) {
        if (desc->compare_func(key, (char *) item + key_offs)) {
            assert(item->size);
            return item;
        }
        item = item->next;
    }
    return NULL;
}

// Append an item at the MRU tail of its shard queue. Shard lock must be held.
static inline void queue_append(CacheShard *shard, CacheItem *item)
{
    *shard->queue_last = item;
    item->queue_prev = shard->queue_last;
    shard->queue_last = &item->queue_next;
    item->queue_next = NULL;
}

// Move an item to the MRU tail on access, re-acquiring the queue reference if
// it had been evicted from the queue (orphaned). Shard lock must be held.
static inline void promote_item(CacheShard *shard, CacheItem *item)
{
    if (!item->queue_prev || item->queue_next) {
        if (item->queue_prev) {
            item->queue_next->queue_prev = item->queue_prev;
            *item->queue_prev = item->queue_next;
        } else
            ass_atomic_inc_size(&item->ref_count);
        queue_append(shard, item);
    }
}

static inline void destroy_item(const CacheDesc *desc, CacheItem *item)
{
    assert(item->desc == desc);
    char *value = (char *) item + CACHE_ITEM_SIZE;
    desc->destruct_func(value + align_cache(desc->value_size), value);
    free(item);
}

// Retrieve a value corresponding to a particular cache key,
// creating one if it does not already exist.
// The returned item is guaranteed to be valid until the next ass_cache_cut call;
// to extend its lifetime further, call ass_cache_inc_ref().
void *ass_cache_get(Cache *cache, void *key, void *priv)
{
    const CacheDesc *desc = cache->desc;
    size_t key_offs = CACHE_ITEM_SIZE + align_cache(desc->value_size);
    unsigned bucket;
    CacheShard *shard = hash_to_shard(cache, desc->hash_func(key, ASS_HASH_INIT),
                                      &bucket);

    ass_mutex_lock(&shard->mutex);
    CacheItem *item = find_item(shard, desc, bucket, key, key_offs);
    if (item) {
        promote_item(shard, item);
        ass_mutex_unlock(&shard->mutex);
        desc->key_move_func(NULL, key);
        return (char *) item + CACHE_ITEM_SIZE;
    }
    ass_mutex_unlock(&shard->mutex);

    // Miss: build the item with the (potentially expensive, recursive)
    // construct_func OUTSIDE the lock, then publish it.
    item = malloc(key_offs + desc->key_size);
    if (!item) {
        desc->key_move_func(NULL, key);
        return NULL;
    }
    item->shard = shard;
    item->desc = desc;
    void *new_key = (char *) item + key_offs;
    if (!desc->key_move_func(new_key, key)) {
        free(item);
        return NULL;
    }
    void *value = (char *) item + CACHE_ITEM_SIZE;
    item->size = desc->construct_func(new_key, value, priv);
    assert(item->size);

    ass_mutex_lock(&shard->mutex);
    // Another thread may have inserted the same key while we built ours.
    CacheItem *existing = find_item(shard, desc, bucket, new_key, key_offs);
    if (existing) {
        promote_item(shard, existing);
        ass_mutex_unlock(&shard->mutex);
        destroy_item(desc, item);
        return (char *) existing + CACHE_ITEM_SIZE;
    }

    CacheItem **bucketptr = &shard->map[bucket];
    if (*bucketptr)
        (*bucketptr)->prev = &item->next;
    item->prev = bucketptr;
    item->next = *bucketptr;
    *bucketptr = item;

    queue_append(shard, item);
    ass_atomic_store_size(&item->ref_count, 1);
    shard->cache_size += item->size + (item->size == 1 ? 0 : CACHE_ITEM_SIZE);
    ass_mutex_unlock(&shard->mutex);
    return value;
}

void *ass_cache_key(void *value)
{
    CacheItem *item = value_to_item(value);
    return (char *) value + align_cache(item->desc->value_size);
}

void ass_cache_inc_ref(void *value)
{
    if (!value)
        return;
    CacheItem *item = value_to_item(value);
    assert(item->size && ass_atomic_load_size(&item->ref_count));
    ass_atomic_inc_size(&item->ref_count);
}

void ass_cache_dec_ref(void *value)
{
    if (!value)
        return;
    CacheItem *item = value_to_item(value);
    assert(item->size);
    if (ass_atomic_dec_size(&item->ref_count))
        return;

    // The count reached zero. A concurrent ass_cache_get() hit may still
    // resurrect the item (orphan re-reference), so re-check under the shard
    // lock before unlinking and destroying it.
    CacheShard *shard = item->shard;
    if (shard) {
        ass_mutex_lock(&shard->mutex);
        if (ass_atomic_load_size(&item->ref_count)) {
            ass_mutex_unlock(&shard->mutex);
            return;
        }
        if (item->next)
            item->next->prev = item->prev;
        *item->prev = item->next;
        shard->cache_size -= item->size + (item->size == 1 ? 0 : CACHE_ITEM_SIZE);
        ass_mutex_unlock(&shard->mutex);
    }
    destroy_item(item->desc, item);
}

// Evict least-recently-used items from one shard. Caller-serialized (no lock).
static void cut_shard(CacheShard *shard, size_t max_size)
{
    if (shard->cache_size <= max_size)
        return;

    do {
        CacheItem *item = shard->queue_first;
        if (!item)
            break;
        assert(item->size);

        shard->queue_first = item->queue_next;
        if (ass_atomic_dec_size(&item->ref_count)) {
            item->queue_prev = NULL;
            continue;
        }

        if (item->next)
            item->next->prev = item->prev;
        *item->prev = item->next;

        shard->cache_size -= item->size + (item->size == 1 ? 0 : CACHE_ITEM_SIZE);
        destroy_item(item->desc, item);
    } while (shard->cache_size > max_size);
    if (shard->queue_first)
        shard->queue_first->queue_prev = &shard->queue_first;
    else
        shard->queue_last = &shard->queue_first;
}

void ass_cache_cut(Cache *cache, size_t max_size)
{
    size_t shard_max = max_size / N_CACHE_SHARDS;
    for (size_t i = 0; i < N_CACHE_SHARDS; i++)
        cut_shard(&cache->shards[i], shard_max);
}

void ass_cache_empty(Cache *cache)
{
    for (size_t s = 0; s < N_CACHE_SHARDS; s++) {
        CacheShard *shard = &cache->shards[s];
        for (unsigned i = 0; i < CACHE_SHARD_BUCKETS; i++) {
            CacheItem *item = shard->map[i];
            while (item) {
                assert(item->size);
                CacheItem *next = item->next;
                if (item->queue_prev)
                    ass_atomic_dec_size(&item->ref_count);
                if (ass_atomic_load_size(&item->ref_count))
                    item->shard = NULL;
                else
                    destroy_item(item->desc, item);
                item = next;
            }
            shard->map[i] = NULL;
        }
        shard->queue_first = NULL;
        shard->queue_last = &shard->queue_first;
        shard->cache_size = 0;
    }
}

void ass_cache_done(Cache *cache)
{
    ass_cache_empty(cache);
    for (size_t s = 0; s < N_CACHE_SHARDS; s++) {
        ass_mutex_destroy(&cache->shards[s].mutex);
        free(cache->shards[s].map);
    }
    free(cache);
}

// Type-specific creation function
Cache *ass_font_cache_create(void)
{
    return ass_cache_create(&font_cache_desc);
}

Cache *ass_outline_cache_create(void)
{
    return ass_cache_create(&outline_cache_desc);
}

Cache *ass_glyph_metrics_cache_create(void)
{
    return ass_cache_create(&glyph_metrics_cache_desc);
}

Cache *ass_face_size_metrics_cache_create(void)
{
    return ass_cache_create(&face_size_metrics_cache_desc);
}

Cache *ass_bitmap_cache_create(void)
{
    return ass_cache_create(&bitmap_cache_desc);
}

Cache *ass_composite_cache_create(void)
{
    return ass_cache_create(&composite_cache_desc);
}
