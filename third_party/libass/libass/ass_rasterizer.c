/*
 * Copyright (C) 2014 Vabishchevich Nikolay <vabnick@gmail.com>
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

#include <assert.h>
#ifdef _MSC_VER
#include <intrin.h>
#pragma intrinsic(_BitScanReverse)
#endif

#include "ass_utils.h"
#include "ass_outline.h"
#include "ass_rasterizer.h"



static inline int ilog2(uint32_t n)
{
#if defined(__GNUC__) || defined(__clang__)
    return __builtin_clz(n) ^ 31;
#elif defined(_MSC_VER)
    unsigned long res;
    _BitScanReverse(&res, n);
    return res;
#else
    int res = 0;
    for (int ord = 16; ord; ord /= 2)
        if (n >= ((uint32_t) 1 << ord)) {
            res += ord;
            n >>= ord;
        }
    return res;
#endif
}


bool ass_rasterizer_init(const BitmapEngine *engine, RasterizerData *rst, int outline_error)
{
    rst->outline_error = outline_error;
    rst->linebuf[0] = rst->linebuf[1] = NULL;
    rst->size[0] = rst->capacity[0] = 0;
    rst->size[1] = rst->capacity[1] = 0;
    rst->n_first = 0;

    unsigned align = 1 << engine->align_order;
    unsigned size = 1 << (2 * engine->tile_order);
    rst->tile = ass_aligned_alloc(align, size, false);
    return rst->tile;
}

/**
 * \brief Ensure sufficient buffer size (allocate if necessary)
 * \param index index (0 or 1) of the input segment buffer (rst->linebuf)
 * \param delta requested size increase
 * \return false on error
 */
static inline bool check_capacity(RasterizerData *rst, int index, size_t delta)
{
    delta += rst->size[index];
    if (rst->capacity[index] >= delta)
        return true;

    size_t capacity = FFMAX(2 * rst->capacity[index], 64);
    while (capacity < delta)
        capacity *= 2;
    void *ptr = realloc(rst->linebuf[index], sizeof(struct segment) * capacity);
    if (!ptr)
        return false;

    rst->linebuf[index] = (struct segment *) ptr;
    rst->capacity[index] = capacity;
    return true;
}

void ass_rasterizer_done(RasterizerData *rst)
{
    free(rst->linebuf[0]);
    free(rst->linebuf[1]);

    ass_aligned_free(rst->tile);
}


/*
 * Tiled Rasterization Algorithm
 *
 * 1) Convert splines into polylines using recursive subdivision.
 *
 * 2) Determine which segments of resulting polylines fall into each tile.
 * That's done through recursive splitting of segment array with horizontal or vertical lines.
 * Each individual segment can lie fully left(top) or right(bottom) from the splitting line or cross it.
 * In the latter case copies of such segment go to both output arrays. Also winding count
 * of the top-left corner of the second result rectangle gets calculated simultaneously with splitting.
 * Winding count of the first result rectangle is the same as of the source rectangle.
 *
 * 3) When the splitting is done to the tile level, there are 3 possible outcome:
 * - Tile doesn't have segments at all--fill it with solid color in accordance with winding count.
 * - Tile have only 1 segment--use simple half-plane filling algorithm.
 * - Generic case with 2 or more segments.
 * In the latter case each segment gets rasterized as right trapezoid into buffer
 * with additive or subtractive blending.
 */


// Helper struct for spline split decision
typedef struct {
    ASS_Vector r;
    int64_t r2, er;
} OutlineSegment;

static inline void segment_init(OutlineSegment *seg,
                                ASS_Vector beg, ASS_Vector end,
                                int32_t outline_error)
{
    int32_t x = end.x - beg.x;
    int32_t y = end.y - beg.y;
    int32_t abs_x = x < 0 ? -x : x;
    int32_t abs_y = y < 0 ? -y : y;

    seg->r.x = x;
    seg->r.y = y;
    seg->r2 = x * (int64_t) x + y * (int64_t) y;
    seg->er = outline_error * (int64_t) FFMAX(abs_x, abs_y);
}

static inline bool segment_subdivide(const OutlineSegment *seg,
                                     ASS_Vector beg, ASS_Vector pt)
{
    int32_t x = pt.x - beg.x;
    int32_t y = pt.y - beg.y;
    int64_t pdr = seg->r.x * (int64_t) x + seg->r.y * (int64_t) y;
    int64_t pcr = seg->r.x * (int64_t) y - seg->r.y * (int64_t) x;
    return pdr < -seg->er || pdr > seg->r2 + seg->er ||
        (pcr < 0 ? -pcr : pcr) > seg->er;
}

/**
 * \brief Add new segment to polyline
 */
static bool add_line(RasterizerData *rst, ASS_Vector pt0, ASS_Vector pt1)
{
    int32_t x = pt1.x - pt0.x;
    int32_t y = pt1.y - pt0.y;
    if (!x && !y)
        return true;

    if (!check_capacity(rst, 0, 1))
        return false;
    struct segment *line = rst->linebuf[0] + rst->size[0];
    rst->size[0]++;

    line->flags = SEGFLAG_EXACT_LEFT | SEGFLAG_EXACT_RIGHT |
                  SEGFLAG_EXACT_TOP | SEGFLAG_EXACT_BOTTOM;
    if (x < 0)
        line->flags ^= SEGFLAG_UL_DR;
    if (y >= 0)
        line->flags ^= SEGFLAG_DN | SEGFLAG_UL_DR;

    line->x_min = FFMIN(pt0.x, pt1.x);
    line->x_max = FFMAX(pt0.x, pt1.x);
    line->y_min = FFMIN(pt0.y, pt1.y);
    line->y_max = FFMAX(pt0.y, pt1.y);

    line->a = y;
    line->b = -x;
    line->c = y * (int64_t) pt0.x - x * (int64_t) pt0.y;

    // halfplane normalization
    int32_t abs_x = x < 0 ? -x : x;
    int32_t abs_y = y < 0 ? -y : y;
    uint32_t max_ab = (abs_x > abs_y ? abs_x : abs_y);
    int shift = 30 - ilog2(max_ab);
    max_ab <<= shift + 1;
    line->a *= 1 << shift;
    line->b *= 1 << shift;
    line->c *= 1 << shift;
    line->scale = (uint64_t) 0x53333333 * (uint32_t) (max_ab * (uint64_t) max_ab >> 32) >> 32;
    line->scale += 0x8810624D - (0xBBC6A7EF * (uint64_t) max_ab >> 32);
    //line->scale = ((uint64_t) 1 << 61) / max_ab;
    return true;
}

/**
 * \brief Add quadratic spline to polyline
 * Performs recursive subdivision if necessary.
 */
static bool add_quadratic(RasterizerData *rst, const ASS_Vector *pt)
{
    OutlineSegment seg;
    segment_init(&seg, pt[0], pt[2], rst->outline_error);
    if (!segment_subdivide(&seg, pt[0], pt[1]))
        return add_line(rst, pt[0], pt[2]);

    ASS_Vector next[5];
    next[1].x = pt[0].x + pt[1].x;
    next[1].y = pt[0].y + pt[1].y;
    next[3].x = pt[1].x + pt[2].x;
    next[3].y = pt[1].y + pt[2].y;
    next[2].x = (next[1].x + next[3].x + 2) >> 2;
    next[2].y = (next[1].y + next[3].y + 2) >> 2;
    next[1].x >>= 1;
    next[1].y >>= 1;
    next[3].x >>= 1;
    next[3].y >>= 1;
    next[0] = pt[0];
    next[4] = pt[2];
    return add_quadratic(rst, next) && add_quadratic(rst, next + 2);
}

/**
 * \brief Add cubic spline to polyline
 * Performs recursive subdivision if necessary.
 */
static bool add_cubic(RasterizerData *rst, const ASS_Vector *pt)
{
    OutlineSegment seg;
    segment_init(&seg, pt[0], pt[3], rst->outline_error);
    if (!segment_subdivide(&seg, pt[0], pt[1]) && !segment_subdivide(&seg, pt[0], pt[2]))
        return add_line(rst, pt[0], pt[3]);

    ASS_Vector next[7], center;
    next[1].x = pt[0].x + pt[1].x;
    next[1].y = pt[0].y + pt[1].y;
    center.x = pt[1].x + pt[2].x + 2;
    center.y = pt[1].y + pt[2].y + 2;
    next[5].x = pt[2].x + pt[3].x;
    next[5].y = pt[2].y + pt[3].y;
    next[2].x = next[1].x + center.x;
    next[2].y = next[1].y + center.y;
    next[4].x = center.x + next[5].x;
    next[4].y = center.y + next[5].y;
    next[3].x = (next[2].x + next[4].x - 1) >> 3;
    next[3].y = (next[2].y + next[4].y - 1) >> 3;
    next[2].x >>= 2;
    next[2].y >>= 2;
    next[4].x >>= 2;
    next[4].y >>= 2;
    next[1].x >>= 1;
    next[1].y >>= 1;
    next[5].x >>= 1;
    next[5].y >>= 1;
    next[0] = pt[0];
    next[6] = pt[3];
    return add_cubic(rst, next) && add_cubic(rst, next + 3);
}


// --- GPU per-tile export -------------------------------------------------
// Run libass's tile-split recursion but, instead of filling, capture each
// leaf tile's clipped segments + entering winding (+ the 2-group max-merge
// structure) into GPU-friendly flat buffers. A GPU shader then runs the
// generic-tile filler per tile/group and max-merges the groups -- matching
// libass's CPU output including stroke self-intersections.
#define TE_RAB(ab, scale) (((ab) * (int64_t)(scale) + ((int64_t)1 << (45 + 4))) >> (46 + 4))
#define TE_RC(c, scale)   (((int32_t)((c) >> (7 + 4)) * (int64_t)(scale) + ((int64_t)1 << 44)) >> 45)

// TE_RAB/TE_RC are the CPU tile filler's RESCALE_A_B/RESCALE_C macros
// (c/rasterizer_template.h) with TILE_ORDER hard-wired to 4, and the export's
// (bw+15)&~15 tiling assumes 16x16px tiles. The export always runs on its own
// 16px C-ref engine (ass_bitmap_engine_init(0), tile_order 4) regardless of the
// CONFIG_LARGE_TILES build option, so the blob is correct either way -- but the
// large-tiles pairing of this GPU tile-export path is unvalidated, so fail the
// build loudly rather than ship an untested combination. (CONFIG_LARGE_TILES is
// the compile-time constant this keys on; ass_outline_to_tiles additionally
// asserts eng.tile_order == 4 at runtime against a future engine-selection change.)
#if CONFIG_LARGE_TILES
#error "ass_outline_to_tiles GPU tile-export hardcodes 16px tiles (tile_order==4) and is not validated for large tiles; build without -Dlarge-tiles / --enable-large-tiles."
#endif

struct tile_export {
    float *tiles; int ntiles; size_t tiles_cap;   // TILE_EXPORT_W floats per tile
    float *segs;  int nsegs;  size_t segs_cap;     // SEG_EXPORT_W floats per segment
    uint8_t *base; ptrdiff_t stride; uint8_t *scratch;
    bool ok;
};
static __thread struct tile_export *g_te;

// append one segment (generic or halfplane params) to the pool, return its index
static int te_push_seg(float a, float b, float c, float flags, float xmin, float ymin, float ymax)
{
    struct tile_export *te = g_te;
    if ((size_t)(te->nsegs + 1) * SEG_EXPORT_W > te->segs_cap) {
        size_t nc = te->segs_cap ? te->segs_cap * 2 : 4096;
        float *p = realloc(te->segs, nc * sizeof(float));
        if (!p) { te->ok = false; return 0; }
        te->segs = p; te->segs_cap = nc;
    }
    float *s = te->segs + (size_t)te->nsegs * SEG_EXPORT_W;
    s[0]=a; s[1]=b; s[2]=c; s[3]=flags; s[4]=xmin; s[5]=ymin; s[6]=ymax; s[7]=0;
    return te->nsegs++;
}
// begin a tile group (type 0=solid,1=halfplane,2=generic) at buf; returns pointer to its 4-float group slot, or NULL
static float *te_group(uint8_t *buf)
{
    struct tile_export *te = g_te;
    if (buf == te->scratch) {                 // group 1 of the previous tile (merge)
        if (!te->ntiles) return NULL;
        float *t = te->tiles + (size_t)(te->ntiles - 1) * TILE_EXPORT_W;
        if (t[2] >= 2) return NULL;
        t[2] += 1;                            // ng -> 2
        return t + 3 + 4;                     // group1 slot
    }
    if ((size_t)(te->ntiles + 1) * TILE_EXPORT_W > te->tiles_cap) {
        size_t nc = te->tiles_cap ? te->tiles_cap * 2 : 1024 * TILE_EXPORT_W;
        float *p = realloc(te->tiles, nc * sizeof(float));
        if (!p) { te->ok = false; return NULL; }
        te->tiles = p; te->tiles_cap = nc;
    }
    ptrdiff_t off = buf - te->base;
    float *t = te->tiles + (size_t)te->ntiles * TILE_EXPORT_W;
    t[0] = (float)(off % te->stride);         // tile x
    t[1] = (float)(off / te->stride);         // tile y
    t[2] = 1;                                 // ng
    for (int i = 3; i < TILE_EXPORT_W; i++) t[i] = 0;
    te->ntiles++;
    return t + 3;                             // group0 slot
}
static void te_solid(uint8_t *buf, ptrdiff_t stride, int set)
{ (void)stride; float *g = te_group(buf); if (g){ g[0]=0; g[1]=set?1:0; g[2]=0; g[3]=0; } }
static void te_half(uint8_t *buf, ptrdiff_t stride, int32_t a, int32_t b, int64_t c, int32_t scale)
{
    (void)stride; float *g = te_group(buf); if (!g) return;
    int si = te_push_seg((float)TE_RAB(a, scale), (float)TE_RAB(b, scale), (float)TE_RC(c, scale), 0,0,0,0);
    g[0]=1; g[1]=0; g[2]=(float)si; g[3]=1;
}
static void te_generic(uint8_t *buf, ptrdiff_t stride, const struct segment *line, size_t n, int winding)
{
    (void)stride; float *g = te_group(buf); if (!g) return;
    int off = g_te->nsegs;
    for (size_t i = 0; i < n; i++) {
        const struct segment *s = &line[i];
        te_push_seg((float)TE_RAB(s->a, s->scale), (float)TE_RAB(s->b, s->scale),
                    (float)TE_RC(s->c, s->scale), (float)s->flags,
                    (float)s->x_min, (float)s->y_min, (float)s->y_max);
    }
    g[0]=2; g[1]=(float)(int8_t)winding; g[2]=(float)off; g[3]=(float)n;
}

// Returns number of tiles; *tiles/*segs are malloc'd flat buffers (caller frees).
int ass_outline_to_tiles(const ASS_Outline *o0, const ASS_Outline *o1, int outline_error,
                         float **tiles, int *n_tiles, float **segs, int *n_segs,
                         int32_t *left, int32_t *top, int32_t *w, int32_t *h)
{
    *tiles = NULL; *segs = NULL; *n_tiles = *n_segs = 0;
    BitmapEngine eng = ass_bitmap_engine_init(0);   // C ref, forced 16px tiles
    // Defensive: the TE_RAB/TE_RC rescale and the (bw+15)&~15 tiling below only
    // hold for tile_order==4. ass_bitmap_engine_init(0) forces that today; guard
    // so a future change to the engine selection fails loudly in debug and
    // degrades to an empty export in release instead of silently miscompositing.
    assert(eng.tile_order == 4);
    if (eng.tile_order != 4)
        return 0;
    RasterizerData rst;
    if (!ass_rasterizer_init(&eng, &rst, outline_error))
        return 0;
    int ret = 0; uint8_t *dummy = NULL;
    struct tile_export te = {0}; te.ok = true;
    if (!ass_rasterizer_set_outline(&rst, o0, false) ||
        (o1 && !ass_rasterizer_set_outline(&rst, o1, true)))
        goto done;
    if (rst.bbox.x_min > rst.bbox.x_max)
        goto done;
    int32_t lx = (rst.bbox.x_min - 1) >> 6, ty = (rst.bbox.y_min - 1) >> 6;
    int32_t rx = (rst.bbox.x_max + 127) >> 6, by = (rst.bbox.y_max + 127) >> 6;
    int32_t bw = rx - lx, bh = by - ty;
    // Mirror ass_outline_to_bitmap's "Glyph bounding box too large" guard (15 ==
    // the 16px tile mask this export hardcodes) so a monstrous \fs/\fscx glyph
    // degrades to an empty export instead of overflowing (bw+15) or attempting a
    // multi-GB calloc. Returning 0 here matches the ass_outline_to_bitmap failure
    // path: ass_bitmap_construct leaves an empty bitmap and the glyph is skipped.
    if (bw < 0 || bh < 0 || bw > INT_MAX - 15 || bh > INT_MAX - 15)
        goto done;
    int32_t tw = (bw + 15) & ~15, th = (bh + 15) & ~15;
    if ((int64_t) tw * th > INT_MAX)
        goto done;
    dummy = calloc(1, (size_t)tw * th);
    if (!dummy) goto done;
    eng.fill_solid = te_solid; eng.fill_halfplane = te_half; eng.fill_generic = te_generic;
    te.base = dummy; te.stride = tw; te.scratch = rst.tile;
    g_te = &te;
    ass_rasterizer_fill(&eng, &rst, dummy, lx, ty, tw, th, tw);
    g_te = NULL;
    if (!te.ok) goto done;
    *tiles = te.tiles; *n_tiles = te.ntiles; *segs = te.segs; *n_segs = te.nsegs;
    *left = lx; *top = ty; *w = bw; *h = bh;
    ret = te.ntiles;
done:
    free(dummy);
    ass_rasterizer_done(&rst);
    if (!ret) { free(te.tiles); free(te.segs); }
    return ret;
}

bool ass_rasterizer_set_outline(RasterizerData *rst,
                                const ASS_Outline *path, bool extra)
{
    if (!extra) {
        rectangle_reset(&rst->bbox);
        rst->n_first = 0;
    }
    rst->size[0] = rst->n_first;

#ifndef NDEBUG
    for (size_t i = 0; i < path->n_points; i++)
        assert(vec_in_range(path->points[i], OUTLINE_MAX));
#endif

    ASS_Vector *start = path->points, *cur = start;
    for (size_t i = 0; i < path->n_segments; i++) {
        int n = path->segments[i] & OUTLINE_COUNT_MASK;
        cur += n;

        ASS_Vector *end = cur, p[4];
        if (path->segments[i] & OUTLINE_CONTOUR_END) {
            end = start;
            start = cur;
        }

        switch (n) {
        case OUTLINE_LINE_SEGMENT:
            if (!add_line(rst, cur[-1], *end))
                return false;
            break;

        case OUTLINE_QUADRATIC_SPLINE:
            p[0] = cur[-2];
            p[1] = cur[-1];
            p[2] = *end;
            if (!add_quadratic(rst, p))
                return false;
            break;

        case OUTLINE_CUBIC_SPLINE:
            p[0] = cur[-3];
            p[1] = cur[-2];
            p[2] = cur[-1];
            p[3] = *end;
            if (!add_cubic(rst, p))
                return false;
            break;

        default:
            return false;
        }
    }
    assert(start == cur && (!cur || cur == path->points + path->n_points));

    for (size_t k = rst->n_first; k < rst->size[0]; k++) {
        struct segment *line = &rst->linebuf[0][k];
        rectangle_update(&rst->bbox,
                         line->x_min, line->y_min,
                         line->x_max, line->y_max);
    }
    if (!extra)
        rst->n_first = rst->size[0];
    return true;
}


static void segment_move_x(struct segment *line, int32_t x)
{
    line->x_min -= x;
    line->x_max -= x;
    line->x_min = FFMAX(line->x_min, 0);
    line->c -= line->a * (int64_t) x;

    static const int test = SEGFLAG_EXACT_LEFT | SEGFLAG_UL_DR;
    if (!line->x_min && (line->flags & test) == test)
        line->flags &= ~SEGFLAG_EXACT_TOP;
}

static void segment_move_y(struct segment *line, int32_t y)
{
    line->y_min -= y;
    line->y_max -= y;
    line->y_min = FFMAX(line->y_min, 0);
    line->c -= line->b * (int64_t) y;

    static const int test = SEGFLAG_EXACT_TOP | SEGFLAG_UL_DR;
    if (!line->y_min && (line->flags & test) == test)
        line->flags &= ~SEGFLAG_EXACT_LEFT;
}

static void segment_split_horz(struct segment *line, struct segment *next, int32_t x)
{
    assert(x > line->x_min && x < line->x_max);

    *next = *line;
    next->c -= line->a * (int64_t) x;
    next->x_min = 0;
    next->x_max -= x;
    line->x_max = x;

    line->flags &= ~SEGFLAG_EXACT_TOP;
    next->flags &= ~SEGFLAG_EXACT_BOTTOM;
    if (line->flags & SEGFLAG_UL_DR) {
        int32_t tmp = line->flags;
        line->flags = next->flags;
        next->flags = tmp;
    }
    line->flags |= SEGFLAG_EXACT_RIGHT;
    next->flags |= SEGFLAG_EXACT_LEFT;
}

static void segment_split_vert(struct segment *line, struct segment *next, int32_t y)
{
    assert(y > line->y_min && y < line->y_max);

    *next = *line;
    next->c -= line->b * (int64_t) y;
    next->y_min = 0;
    next->y_max -= y;
    line->y_max = y;

    line->flags &= ~SEGFLAG_EXACT_LEFT;
    next->flags &= ~SEGFLAG_EXACT_RIGHT;
    if (line->flags & SEGFLAG_UL_DR) {
        int32_t tmp = line->flags;
        line->flags = next->flags;
        next->flags = tmp;
    }
    line->flags |= SEGFLAG_EXACT_BOTTOM;
    next->flags |= SEGFLAG_EXACT_TOP;
}

static inline int segment_check_left(const struct segment *line, int32_t x)
{
    if (line->flags & SEGFLAG_EXACT_LEFT)
        return line->x_min >= x;
    int64_t cc = line->c - line->a * (int64_t) x -
        line->b * (int64_t) (line->flags & SEGFLAG_UL_DR ? line->y_min : line->y_max);
    if (line->a < 0)
        cc = -cc;
    return cc >= 0;
}

static inline int segment_check_right(const struct segment *line, int32_t x)
{
    if (line->flags & SEGFLAG_EXACT_RIGHT)
        return line->x_max <= x;
    int64_t cc = line->c - line->a * (int64_t) x -
        line->b * (int64_t) (line->flags & SEGFLAG_UL_DR ? line->y_max : line->y_min);
    if (line->a > 0)
        cc = -cc;
    return cc >= 0;
}

static inline int segment_check_top(const struct segment *line, int32_t y)
{
    if (line->flags & SEGFLAG_EXACT_TOP)
        return line->y_min >= y;
    int64_t cc = line->c - line->b * (int64_t) y -
        line->a * (int64_t) (line->flags & SEGFLAG_UL_DR ? line->x_min : line->x_max);
    if (line->b < 0)
        cc = -cc;
    return cc >= 0;
}

static inline int segment_check_bottom(const struct segment *line, int32_t y)
{
    if (line->flags & SEGFLAG_EXACT_BOTTOM)
        return line->y_max <= y;
    int64_t cc = line->c - line->b * (int64_t) y -
        line->a * (int64_t) (line->flags & SEGFLAG_UL_DR ? line->x_max : line->x_min);
    if (line->b > 0)
        cc = -cc;
    return cc >= 0;
}

/**
 * \brief Split list of segments horizontally
 * \param src in: input array, can coincide with *dst0 or *dst1
 * \param n_src in: numbers of input segments for both groups
 * \param dst0, dst1 out: output arrays of at least n_src[0] + n_src[1] size
 * \param n_dst0, n_dst1 out: numbers of output segments for both groups
 * \param winding out: resulting winding of bottom-split point
 * \param x in: split coordinate
 */
static void polyline_split_horz(const struct segment *src, const size_t n_src[2],
                                struct segment *dst0, size_t n_dst0[2],
                                struct segment *dst1, size_t n_dst1[2],
                                int winding[2], int32_t x)
{
    const struct segment *cmp = src + n_src[0];
    const struct segment *end = cmp + n_src[1];
    n_dst0[0] = n_dst0[1] = 0;
    n_dst1[0] = n_dst1[1] = 0;
    for (; src != end; src++) {
        int group = src < cmp ? 0 : 1;

        int delta = 0;
        if (!src->y_min && (src->flags & SEGFLAG_EXACT_TOP))
            delta = src->a < 0 ? 1 : -1;
        if (segment_check_right(src, x)) {
            winding[group] += delta;
            if (src->x_min >= x)
                continue;
            *dst0 = *src;
            dst0->x_max = FFMIN(dst0->x_max, x);
            n_dst0[group]++;
            dst0++;
            continue;
        }
        if (segment_check_left(src, x)) {
            *dst1 = *src;
            segment_move_x(dst1, x);
            n_dst1[group]++;
            dst1++;
            continue;
        }
        if (src->flags & SEGFLAG_UL_DR)
            winding[group] += delta;
        *dst0 = *src;
        segment_split_horz(dst0, dst1, x);
        n_dst0[group]++;
        dst0++;
        n_dst1[group]++;
        dst1++;
    }
}

/**
 * \brief Split list of segments vertically
 */
static void polyline_split_vert(const struct segment *src, const size_t n_src[2],
                                struct segment *dst0, size_t n_dst0[2],
                                struct segment *dst1, size_t n_dst1[2],
                                int winding[2], int32_t y)
{
    const struct segment *cmp = src + n_src[0];
    const struct segment *end = cmp + n_src[1];
    n_dst0[0] = n_dst0[1] = 0;
    n_dst1[0] = n_dst1[1] = 0;
    for (; src != end; src++) {
        int group = src < cmp ? 0 : 1;

        int delta = 0;
        if (!src->x_min && (src->flags & SEGFLAG_EXACT_LEFT))
            delta = src->b < 0 ? 1 : -1;
        if (segment_check_bottom(src, y)) {
            winding[group] += delta;
            if (src->y_min >= y)
                continue;
            *dst0 = *src;
            dst0->y_max = dst0->y_max < y ? dst0->y_max : y;
            n_dst0[group]++;
            dst0++;
            continue;
        }
        if (segment_check_top(src, y)) {
            *dst1 = *src;
            segment_move_y(dst1, y);
            n_dst1[group]++;
            dst1++;
            continue;
        }
        if (src->flags & SEGFLAG_UL_DR)
            winding[group] += delta;
        *dst0 = *src;
        segment_split_vert(dst0, dst1, y);
        n_dst0[group]++;
        dst0++;
        n_dst1[group]++;
        dst1++;
    }
}


static inline void rasterizer_fill_solid(const BitmapEngine *engine,
                                         uint8_t *buf, int width, int height, ptrdiff_t stride,
                                         int set)
{
    assert(!(width  & ((1 << engine->tile_order) - 1)));
    assert(!(height & ((1 << engine->tile_order) - 1)));

    ptrdiff_t step = 1 << engine->tile_order;
    ptrdiff_t tile_stride = stride * (1 << engine->tile_order);
    width  >>= engine->tile_order;
    height >>= engine->tile_order;
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++)
            engine->fill_solid(buf + x * step, stride, set);
        buf += tile_stride;
    }
}

static inline void rasterizer_fill_halfplane(const BitmapEngine *engine,
                                             uint8_t *buf, int width, int height, ptrdiff_t stride,
                                             int32_t a, int32_t b, int64_t c, int32_t scale)
{
    assert(!(width  & ((1 << engine->tile_order) - 1)));
    assert(!(height & ((1 << engine->tile_order) - 1)));
    if (width == 1 << engine->tile_order && height == 1 << engine->tile_order) {
        engine->fill_halfplane(buf, stride, a, b, c, scale);
        return;
    }

    uint32_t abs_a = a < 0 ? -a : a;
    uint32_t abs_b = b < 0 ? -b : b;
    int64_t size = (int64_t) (abs_a + abs_b) << (engine->tile_order + 5);
    int64_t offs = ((int64_t) a + b) * (1 << (engine->tile_order + 5));

    ptrdiff_t step = 1 << engine->tile_order;
    ptrdiff_t tile_stride = stride * (1 << engine->tile_order);
    width  >>= engine->tile_order;
    height >>= engine->tile_order;
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            int64_t cc = c - (a * (int64_t) x + b * (int64_t) y) * (1 << (engine->tile_order + 6));
            int64_t offs_c = offs - cc;
            int64_t abs_c = offs_c < 0 ? -offs_c : offs_c;
            if (abs_c < size)
                engine->fill_halfplane(buf + x * step, stride, a, b, cc, scale);
            else
                engine->fill_solid(buf + x * step, stride,
                                   ((uint32_t) (offs_c >> 32) ^ scale) & 0x80000000);
        }
        buf += tile_stride;
    }
}

enum {
    FLAG_SOLID     = 1,
    FLAG_COMPLEX   = 2,
    FLAG_REVERSE   = 4,
    FLAG_GENERIC   = 8,
};

static inline int get_fill_flags(struct segment *line, size_t n_lines, int winding)
{
    if (!n_lines)
        return winding ? FLAG_SOLID : 0;
    if (n_lines > 1)
        return FLAG_COMPLEX | FLAG_GENERIC;

    static const int test = SEGFLAG_UL_DR | SEGFLAG_EXACT_LEFT;
    if (((line->flags & test) != test) == !(line->flags & SEGFLAG_DN))
        winding++;

    switch (winding) {
    case 0:
        return FLAG_COMPLEX | FLAG_REVERSE;
    case 1:
        return FLAG_COMPLEX;
    default:
        return FLAG_SOLID;
    }
}

/**
 * \brief Main quad-tree filling function
 * \param index index (0 or 1) of the input segment buffer (rst->linebuf)
 * \param offs current offset from the beginning of the buffer
 * \param winding bottom-left winding value
 * \return false on error
 * Rasterizes (possibly recursive) one quad-tree level.
 * Truncates used input buffer.
 */
static bool rasterizer_fill_level(const BitmapEngine *engine, RasterizerData *rst,
                                  uint8_t *buf, int width, int height, ptrdiff_t stride,
                                  int index, const size_t n_lines[2], const int winding[2])
{
    assert(width > 0 && height > 0);
    assert((unsigned) index < 2u && n_lines[0] + n_lines[1] <= rst->size[index]);
    assert(!(width  & ((1 << engine->tile_order) - 1)));
    assert(!(height & ((1 << engine->tile_order) - 1)));

    size_t offs = rst->size[index] - n_lines[0] - n_lines[1];
    struct segment *line = rst->linebuf[index] + offs, *line1 = line + n_lines[0];
    int flags0 = get_fill_flags(line,  n_lines[0], winding[0]);
    int flags1 = get_fill_flags(line1, n_lines[1], winding[1]);
    int flags = (flags0 | flags1) ^ FLAG_COMPLEX;
    if (flags & (FLAG_SOLID | FLAG_COMPLEX)) {
        rasterizer_fill_solid(engine, buf, width, height, stride, flags & FLAG_SOLID);
        rst->size[index] = offs;
        return true;
    }
    if (!(flags & FLAG_GENERIC) && ((flags0 ^ flags1) & FLAG_COMPLEX)) {
        if (flags1 & FLAG_COMPLEX)
            line = line1;
        rasterizer_fill_halfplane(engine, buf, width, height, stride,
                                  line->a, line->b, line->c,
                                  flags & FLAG_REVERSE ? -line->scale : line->scale);
        rst->size[index] = offs;
        return true;
    }
    if (width == 1 << engine->tile_order && height == 1 << engine->tile_order) {
        if (!(flags1 & FLAG_COMPLEX)) {
            engine->fill_generic(buf, stride, line, n_lines[0], winding[0]);
            rst->size[index] = offs;
            return true;
        }
        if (!(flags0 & FLAG_COMPLEX)) {
            engine->fill_generic(buf, stride, line1, n_lines[1], winding[1]);
            rst->size[index] = offs;
            return true;
        }
        if (flags0 & FLAG_GENERIC)
            engine->fill_generic(buf, stride, line, n_lines[0], winding[0]);
        else
            engine->fill_halfplane(buf, stride, line->a, line->b, line->c,
                                   flags0 & FLAG_REVERSE ? -line->scale : line->scale);
        if (flags1 & FLAG_GENERIC)
            engine->fill_generic(rst->tile, width, line1, n_lines[1], winding[1]);
        else
            engine->fill_halfplane(rst->tile, width, line1->a, line1->b, line1->c,
                                   flags1 & FLAG_REVERSE ? -line1->scale : line1->scale);
        engine->merge(buf, stride, rst->tile);
        rst->size[index] = offs;
        return true;
    }

    size_t offs1 = rst->size[index ^ 1];
    if (!check_capacity(rst, index ^ 1, n_lines[0] + n_lines[1]))
        return false;
    struct segment *dst0 = line;
    struct segment *dst1 = rst->linebuf[index ^ 1] + offs1;

    uint8_t *buf1 = buf;
    int width1  = width;
    int height1 = height;
    size_t n_next0[2], n_next1[2];
    int winding1[2] = { winding[0], winding[1] };
    if (width > height) {
        width = 1 << ilog2(width - 1);
        width1 -= width;
        buf1 += width;
        polyline_split_horz(line, n_lines,
                            dst0, n_next0, dst1, n_next1,
                            winding1, (int32_t) width << 6);
    } else {
        height = 1 << ilog2(height - 1);
        height1 -= height;
        buf1 += height * stride;
        polyline_split_vert(line, n_lines,
                            dst0, n_next0, dst1, n_next1,
                            winding1, (int32_t) height << 6);
    }
    rst->size[index ^ 0] = offs  + n_next0[0] + n_next0[1];
    rst->size[index ^ 1] = offs1 + n_next1[0] + n_next1[1];

    if (!rasterizer_fill_level(engine, rst, buf,  width,  height,  stride, index ^ 0, n_next0,  winding))
        return false;
    assert(rst->size[index ^ 0] == offs);
    if (!rasterizer_fill_level(engine, rst, buf1, width1, height1, stride, index ^ 1, n_next1, winding1))
        return false;
    assert(rst->size[index ^ 1] == offs1);
    return true;
}

bool ass_rasterizer_fill(const BitmapEngine *engine, RasterizerData *rst,
                         uint8_t *buf, int x0, int y0,
                         int width, int height, ptrdiff_t stride)
{
    assert(width > 0 && height > 0);
    assert(!(width  & ((1 << engine->tile_order) - 1)));
    assert(!(height & ((1 << engine->tile_order) - 1)));
    x0 *= 1 << 6;  y0 *= 1 << 6;

    struct segment *line = rst->linebuf[0];
    struct segment *end = line + rst->size[0];
    for (; line != end; line++) {
        line->x_min -= x0;
        line->x_max -= x0;
        line->y_min -= y0;
        line->y_max -= y0;
        line->c -= line->a * (int64_t) x0 + line->b * (int64_t) y0;
    }
    rst->bbox.x_min -= x0;
    rst->bbox.x_max -= x0;
    rst->bbox.y_min -= y0;
    rst->bbox.y_max -= y0;

    if (!check_capacity(rst, 1, rst->size[0]))
        return false;

    size_t n_unused[2];
    size_t n_lines[2] = { rst->n_first, rst->size[0] - rst->n_first };
    int winding[2] = { 0, 0 };

    int32_t size_x = (int32_t) width << 6;
    int32_t size_y = (int32_t) height << 6;
    if (rst->bbox.x_max >= size_x) {
        polyline_split_horz(rst->linebuf[0], n_lines,
                            rst->linebuf[0], n_lines,
                            rst->linebuf[1], n_unused,
                            winding, size_x);
        winding[0] = winding[1] = 0;
    }
    if (rst->bbox.y_max >= size_y) {
        polyline_split_vert(rst->linebuf[0], n_lines,
                            rst->linebuf[0], n_lines,
                            rst->linebuf[1], n_unused,
                            winding, size_y);
        winding[0] = winding[1] = 0;
    }
    if (rst->bbox.x_min <= 0) {
        polyline_split_horz(rst->linebuf[0], n_lines,
                            rst->linebuf[1], n_unused,
                            rst->linebuf[0], n_lines,
                            winding, 0);
    }
    if (rst->bbox.y_min <= 0) {
        polyline_split_vert(rst->linebuf[0], n_lines,
                            rst->linebuf[1], n_unused,
                            rst->linebuf[0], n_lines,
                            winding, 0);
    }
    rst->size[0] = n_lines[0] + n_lines[1];
    rst->size[1] = 0;
    return rasterizer_fill_level(engine, rst,
                                 buf, width, height, stride,
                                 0, n_lines, winding);
}
