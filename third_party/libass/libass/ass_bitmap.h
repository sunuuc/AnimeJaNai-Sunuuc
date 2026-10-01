/*
 * Copyright (C) 2006 Evgeniy Stepanov <eugeni.stepanov@gmail.com>
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

#ifndef LIBASS_BITMAP_H
#define LIBASS_BITMAP_H

#include <stdbool.h>
#include <ft2build.h>
#include FT_GLYPH_H

#include "ass.h"
#include "ass_outline.h"
#include "ass_bitmap_engine.h"

struct render_context;
struct rasterizer_data;

typedef struct {
    int32_t left, top;
    int32_t w, h;         // width, height
    ptrdiff_t stride;
    uint8_t *buffer;      // h * stride buffer (NULL in outline-deferred mode)
    uint64_t cache_id;    // unique per cached glyph bitmap (deferred-composite id)
    int32_t *segments;    // outline-deferred: the packed per-tile GPU blob
    int32_t n_segments;   //   [n_tiles, n_segs, tiles.., segs..] (int32 count;
                          //   see ASS_Image.outline in ass.h). NULL/0 otherwise.
} Bitmap;

bool ass_alloc_bitmap(const BitmapEngine *engine, Bitmap *bm, int32_t w, int32_t h, bool zero);
bool ass_realloc_bitmap(const BitmapEngine *engine, Bitmap *bm, int32_t w, int32_t h);
bool ass_copy_bitmap(const BitmapEngine *engine, Bitmap *dst, const Bitmap *src);
void ass_free_bitmap(Bitmap *bm);

struct render_context;

bool ass_outline_to_bitmap(struct render_context *state, struct rasterizer_data *rst, Bitmap *bm,
                           ASS_Outline *outline1, ASS_Outline *outline2);

// pool (an ASS_ThreadPool *, or NULL) lets a large gaussian blur farm its
// stripe-independent stages out to idle workers; NULL renders serially.
void ass_synth_blur(const BitmapEngine *engine, void *pool, Bitmap *bm,
                    int be, double blur_r2x, double blur_r2y);

bool ass_gaussian_blur(const BitmapEngine *engine, void *pool, Bitmap *bm,
                       double r2x, double r2y);
// Like ass_gaussian_blur, but only expands the bitmap to the bounds the blur
// would produce (zero-padded, content re-centred) WITHOUT convolving. Used by
// the deferred-blur mode, where the actual gaussian is applied later (e.g. on
// the GPU) within these pre-sized bounds.
bool ass_blur_expand_only(const BitmapEngine *engine, Bitmap *bm,
                          double r2x, double r2y);
void ass_shift_bitmap(Bitmap *bm, int shift_x, int shift_y);
void ass_fix_outline(Bitmap *bm_g, Bitmap *bm_o);

#endif                          /* LIBASS_BITMAP_H */
