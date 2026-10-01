/*
 * int8k_harness.c -- verification harness for the integration-8k port
 *
 * Renders every *.ass file found in the given directories (fonts are loaded
 * from the same directories, ASS_FONTPROVIDER_NONE, like compare/) at a
 * deterministic set of timestamps derived from the track's events, and:
 *
 *   hash mode (default):
 *       blends each ASS_Image chain into an RGBA8 canvas (same blend as
 *       compare/compare.c) and prints an FNV-1a-64 hash per (file, time).
 *       Used for bitwise A/B between two libass builds and for verifying
 *       thread-count bit-exactness (-t N calls ass_set_render_thread_count).
 *
 *   outline mode (-m outline; not compiled with -DINT8K_NO_OUTLINE):
 *       enables ass_set_outline_deferred(r, 1) and asserts for every emitted
 *       ASS_Image: bitmap == NULL, outline != NULL, n_outline >= 2, and the
 *       tile blob layout n_outline == 2 + n_tiles*TILE_EXPORT_W +
 *       n_segs*SEG_EXPORT_W with n_tiles = outline[0] > 0 and
 *       n_segs = outline[1] > 0.
 *
 * Build (from the repo root, BUILD = a configured meson build dir):
 *   gcc -O2 -I libass -I $BUILD [-DINT8K_NO_OUTLINE] test/int8k_harness.c \
 *       $BUILD/libass/libass.a $(pkg-config --cflags --libs freetype2 \
 *       harfbuzz fribidi fontconfig) -lm -lpthread -o int8k_harness
 *
 *   blurdefer mode (-m blurdefer):
 *       self-contained fix check for ass_set_blur_deferred: renders a \be2-only
 *       event and asserts the deferred bitmap matches the non-deferred render
 *       with blur_x==blur_y==0, plus a \be2\blur3 event asserting the gaussian
 *       is deferred (blur_x/y>0) and \be is still applied. Needs a font dir
 *       only (for "Aileron"); the .ass corpus is ignored.
 *
 *   tilecmp mode (-m tilecmp; not compiled with -DINT8K_NO_OUTLINE):
 *       GPU-filler divergence isolation (no GPU needed): renders the corpus
 *       with outline_deferred, decodes every image's tile blob and rasterizes
 *       each tile twice on the CPU:
 *         ref16: the C tile fillers' exact int16 wraparound semantics
 *                (rasterizer_template.h, TILE_ORDER 4) fed the blob's
 *                pre-rescaled a/b/c -- bit-identical to libass's CPU coverage
 *                (that equivalence is itself validated by -m tileself);
 *         gpu32: a straight C port of vo_gpu_next.c's GLSL filler in plain
 *                int32 arithmetic (as shipped before the WP-C5 fix).
 *       Any differing pixel means the GLSL's 32-bit ints diverge from the
 *       CPU's wrapping int16 arithmetic for that tile's segments.
 *
 *   tileself mode (-m tileself):
 *       validates ref16 AND the blob encoding against the real CPU rasterizer:
 *       builds synthetic outlines (long thin spikes at many angles, mimicking
 *       steep 3D-perspective edges), rasterizes each directly with
 *       ass_rasterizer_fill (C engine, 16px tiles), and again from its
 *       ass_outline_to_tiles blob via ref16; the two coverage buffers must
 *       match byte for byte. Self-contained (ignores the .ass corpus).
 *
 * Usage: int8k_harness [-t threads]
 *        [-m hash|outline|blurdefer|tilecmp|tileself] [-W w] [-H h] dir...
 */

#include <dirent.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../libass/ass.h"
#ifndef INT8K_NO_OUTLINE
#include "../libass/ass_rasterizer.h"   /* TILE_EXPORT_W / SEG_EXPORT_W */
#include "../libass/ass_types.h"
#include "../libass/ass_outline.h"      /* tileself: synthetic outlines */
#include "../libass/ass_bitmap_engine.h"
#endif

#define MAX_TIMES 64

static ASS_Library *g_lib;

static void msg_cb(int level, const char *fmt, va_list va, void *data)
{
    (void) fmt; (void) va; (void) data;
    if (level > 4)  /* keep output deterministic: errors/warnings only */
        return;
    fprintf(stderr, "libass: ");
    vfprintf(stderr, fmt, va);
    fputc('\n', stderr);
}

static int has_ext(const char *name, const char *ext)
{
    size_t nl = strlen(name), el = strlen(ext);
    return nl > el && !strcasecmp(name + nl - el, ext);
}

static void load_fonts(const char *dir)
{
    DIR *d = opendir(dir);
    if (!d) {
        fprintf(stderr, "cannot open dir '%s'\n", dir);
        exit(2);
    }
    struct dirent *e;
    while ((e = readdir(d))) {
        if (!has_ext(e->d_name, ".ttf") && !has_ext(e->d_name, ".otf") &&
            !has_ext(e->d_name, ".pfb"))
            continue;
        char path[4096];
        snprintf(path, sizeof(path), "%s/%s", dir, e->d_name);
        FILE *f = fopen(path, "rb");
        if (!f)
            continue;
        fseek(f, 0, SEEK_END);
        long size = ftell(f);
        fseek(f, 0, SEEK_SET);
        char *buf = malloc(size);
        if (buf && fread(buf, 1, size, f) == (size_t) size)
            ass_add_font(g_lib, e->d_name, buf, size);
        free(buf);
        fclose(f);
    }
    closedir(d);
}

/* deterministic sample times: 5 points across every event, sorted, deduped */
static int collect_times(ASS_Track *track, long long *times)
{
    int n = 0;
    for (int i = 0; i < track->n_events && n < MAX_TIMES - 5; i++) {
        ASS_Event *ev = track->events + i;
        long long s = ev->Start, d = ev->Duration;
        long long pts[5] = { s, s + d / 4, s + d / 2, s + 3 * d / 4,
                             s + (d > 0 ? d - 1 : 0) };
        for (int k = 0; k < 5; k++)
            times[n++] = pts[k];
    }
    if (!n)
        times[n++] = 0;
    /* sort + dedup */
    for (int i = 1; i < n; i++)
        for (int j = i; j > 0 && times[j - 1] > times[j]; j--) {
            long long t = times[j]; times[j] = times[j - 1]; times[j - 1] = t;
        }
    int m = 1;
    for (int i = 1; i < n; i++)
        if (times[i] != times[m - 1])
            times[m++] = times[i];
    return m;
}

/* --- hash mode ----------------------------------------------------------- */

/* same blend arithmetic as compare/compare.c (blend_image) */
static void blend_image(uint8_t *frame, int32_t fw, int32_t fh,
                        const ASS_Image *img)
{
    if (!img->bitmap)
        return;
    int32_t x0 = img->dst_x > 0 ? img->dst_x : 0;
    int32_t y0 = img->dst_y > 0 ? img->dst_y : 0;
    int32_t x1 = img->dst_x + img->w < fw ? img->dst_x + img->w : fw;
    int32_t y1 = img->dst_y + img->h < fh ? img->dst_y + img->h : fh;
    if (x0 >= x1 || y0 >= y1)
        return;

    uint8_t r = img->color >> 24, g = img->color >> 16;
    uint8_t b = img->color >> 8,  a = img->color;
    int32_t mul = 129 * (255 - a);
    const int32_t offs = (int32_t) 1 << 22;

    int32_t stride = 4 * fw;
    uint8_t *dst = frame + y0 * stride + 4 * x0;
    const uint8_t *src = img->bitmap + (y0 - img->dst_y) * img->stride
                                     + (x0 - img->dst_x);
    for (int32_t y = y0; y < y1; y++) {
        for (int32_t x = 0; x < x1 - x0; x++) {
            int32_t k = src[x] * mul;
            dst[4 * x + 0] -= ((dst[4 * x + 0] - r) * k + offs) >> 23;
            dst[4 * x + 1] -= ((dst[4 * x + 1] - g) * k + offs) >> 23;
            dst[4 * x + 2] -= ((dst[4 * x + 2] - b) * k + offs) >> 23;
            dst[4 * x + 3] -= ((dst[4 * x + 3] - 0) * k + offs) >> 23;
        }
        dst += stride;
        src += img->stride;
    }
}

static uint64_t fnv1a64(const uint8_t *p, size_t n)
{
    uint64_t h = 0xcbf29ce484222325ull;
    for (size_t i = 0; i < n; i++) {
        h ^= p[i];
        h *= 0x100000001b3ull;
    }
    return h;
}

static int run_hash(ASS_Renderer *r, ASS_Track *track, const char *name,
                    int fw, int fh)
{
    long long times[MAX_TIMES];
    int nt = collect_times(track, times);
    uint8_t *canvas = malloc((size_t) 4 * fw * fh);
    if (!canvas)
        return 1;
    for (int i = 0; i < nt; i++) {
        ASS_Image *img = ass_render_frame(r, track, times[i], NULL);
        memset(canvas, 0, (size_t) 4 * fw * fh);
        for (ASS_Image *im = img; im; im = im->next)
            blend_image(canvas, fw, fh, im);
        printf("HASH %s %lld %016llx\n", name, times[i],
               (unsigned long long) fnv1a64(canvas, (size_t) 4 * fw * fh));
    }
    free(canvas);
    return 0;
}

/* --- outline mode -------------------------------------------------------- */

#ifndef INT8K_NO_OUTLINE
static int run_outline(ASS_Renderer *r, ASS_Track *track, const char *name)
{
    long long times[MAX_TIMES];
    int nt = collect_times(track, times);
    int failures = 0, images = 0, frames_with_images = 0;
    for (int i = 0; i < nt; i++) {
        ASS_Image *img = ass_render_frame(r, track, times[i], NULL);
        if (img)
            frames_with_images++;
        for (ASS_Image *im = img; im; im = im->next) {
            images++;
            const char *bad = NULL;
            if (im->bitmap)
                bad = "bitmap != NULL";
            else if (!im->outline)
                bad = "outline == NULL";
            else if (im->n_outline < 2)
                bad = "n_outline < 2";
            else {
                int32_t n_tiles = im->outline[0], n_segs = im->outline[1];
                if (n_tiles <= 0)
                    bad = "n_tiles <= 0";
                else if (n_segs <= 0)
                    bad = "n_segs <= 0";
                else if ((int64_t) im->n_outline !=
                         2 + (int64_t) n_tiles * TILE_EXPORT_W
                           + (int64_t) n_segs * SEG_EXPORT_W)
                    bad = "n_outline != 2 + n_tiles*TILE_EXPORT_W + n_segs*SEG_EXPORT_W";
            }
            if (bad) {
                failures++;
                printf("OUTLINE-FAIL %s %lld img#%d: %s (bitmap=%p outline=%p "
                       "n_outline=%d)\n", name, times[i], images, bad,
                       (void *) im->bitmap, (void *) im->outline,
                       im->n_outline);
            }
        }
    }
    printf("OUTLINE %s: %d frames rendered, %d with images, %d images, "
           "%d failures -> %s\n", name, nt, frames_with_images, images,
           failures, failures || !images ? "FAIL" : "PASS");
    return failures || !images;
}
#endif

/* --- blur-deferred mode (verifies the \be fix in blur-deferred-only mode) --
 *
 * ass_set_blur_deferred(1) defers ONLY the gaussian \blur (recorded as
 * ASS_Image.blur_x/blur_y); the box blur \be must still be applied on the CPU.
 * Self-contained: builds one borderless white event in memory, so it needs no
 * .ass corpus -- only a font dir (for "Aileron") on the command line. */

static const char *BLURDEFER_TEMPLATE =
    "[Script Info]\n"
    "PlayResX: 1280\nPlayResY: 720\nScaledBorderAndShadow: yes\n\n"
    "[V4+ Styles]\n"
    "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, "
    "OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, "
    "ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, "
    "MarginR, MarginV, Encoding\n"
    "Style: T,Aileron,72,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,"
    "100,100,0,0,1,0,0,5,10,10,10,1\n\n"
    "[Events]\n"
    "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, "
    "Text\n"
    "Dialogue: 0,0:00:00.00,0:00:10.00,T,,0,0,0,,{%s}Blur Wg\n";

/* Render the one-event track built from `override` at t=1000ms with the given
 * blur_deferred setting; returns the blended-canvas hash and reports the max
 * emitted blur_x/blur_y over the image chain. */
static uint64_t blurdefer_render(ASS_Renderer *r, int fw, int fh,
                                 const char *override, int deferred,
                                 double *max_bx, double *max_by)
{
    char doc[1024];
    int n = snprintf(doc, sizeof(doc), BLURDEFER_TEMPLATE, override);
    ASS_Track *track = ass_read_memory(g_lib, doc, (size_t) n, NULL);
    if (!track) {
        fprintf(stderr, "blurdefer: ass_read_memory failed\n");
        exit(1);
    }
    ass_set_blur_deferred(r, deferred);
    ASS_Image *img = ass_render_frame(r, track, 1000, NULL);
    uint8_t *canvas = calloc(1, (size_t) 4 * fw * fh);
    double bx = 0, by = 0;
    for (ASS_Image *im = img; im; im = im->next) {
        if (im->blur_x > bx) bx = im->blur_x;
        if (im->blur_y > by) by = im->blur_y;
        blend_image(canvas, fw, fh, im);
    }
    uint64_t h = fnv1a64(canvas, (size_t) 4 * fw * fh);
    free(canvas);
    ass_free_track(track);
    if (max_bx) *max_bx = bx;
    if (max_by) *max_by = by;
    return h;
}

static int run_blurdefer(ASS_Renderer *r, int fw, int fh)
{
    int fails = 0;
    double bx, by, bx2, by2;

    /* Case 1 (\be only): the deferred render must match the non-deferred render
     * bit-for-bit -- the box blur is applied on the CPU in both -- and no
     * gaussian may be deferred (blur_x == blur_y == 0). */
    uint64_t ref = blurdefer_render(r, fw, fh, "\\be2", 0, &bx,  &by);
    uint64_t def = blurdefer_render(r, fw, fh, "\\be2", 1, &bx2, &by2);
    int c1 = (def == ref) && bx2 == 0.0 && by2 == 0.0;
    printf("BLURDEFER be-only: ref=%016llx def=%016llx blur=(%.3f,%.3f) -> %s\n",
           (unsigned long long) ref, (unsigned long long) def, bx2, by2,
           c1 ? "PASS" : "FAIL");
    fails += !c1;

    /* Case 2 (\be + \blur): the gaussian must be deferred (blur_x/blur_y > 0)
     * and \be must still be applied. The exact pre-gaussian intermediate is not
     * reachable through the public API, so the documented discriminator is:
     * with the fix the deferred bitmap differs from the pure-unblurred coverage;
     * without the fix \be is dropped and it would equal that raw coverage. */
    uint64_t plain  = blurdefer_render(r, fw, fh, "",           1, &bx,  &by);
    uint64_t beblur = blurdefer_render(r, fw, fh, "\\be2\\blur3", 1, &bx2, &by2);
    int c2 = (bx2 > 0.0) && (by2 > 0.0) && (beblur != plain);
    printf("BLURDEFER be+blur: plain=%016llx beblur=%016llx blur=(%.3f,%.3f) -> %s\n",
           (unsigned long long) plain, (unsigned long long) beblur, bx2, by2,
           c2 ? "PASS" : "FAIL");
    fails += !c2;

    printf("BLURDEFER: %d failures -> %s\n", fails, fails ? "FAIL" : "PASS");
    return fails != 0;
}

/* --- tilecmp / tileself modes ---------------------------------------------
 *
 * Two CPU rasterizations of an ass_outline_to_tiles blob:
 *
 *   ref16: the semantics of libass's C tile fillers (rasterizer_template.h,
 *          TILE_ORDER 4). Their arithmetic lives in int16_t, so every store
 *          wraps mod 2^16 -- and the wraps are REACHABLE: a segment clipped
 *          to a 16px tile can carry |RESCALE_C| up to ~32768 and per-pixel
 *          line-equation values up to ~(|a|+|b|)*16 + |c| ~ 64K. Steep long
 *          edges (3D perspective) hit this; the SIMD fillers use 16-bit lanes
 *          too, so the wrap IS the reference output.
 *   gpu32: the GLSL filler of vo_gpu_next.c in plain int32 (no wrap).
 *
 * The blob's a/b/c are the CPU fillers' own RESCALE_AB/RESCALE_C results
 * before their int16 truncation (exact in float32: |a|,|b| <= 2048,
 * |c| <= ~32768), so ref16's int16 stores reproduce the truncation exactly.
 */
#ifndef INT8K_NO_OUTLINE

#define TC_FULL 1024   /* FULL_VALUE at TILE_ORDER 4 */

typedef struct {
    int32_t a, b, c, flags, x_min, y_min, y_max;
} TcSeg;

static void tc_seg(const float *s, TcSeg *o)
{
    o->a = (int32_t) s[0]; o->b = (int32_t) s[1]; o->c = (int32_t) s[2];
    o->flags = (int32_t) s[3]; o->x_min = (int32_t) s[4];
    o->y_min = (int32_t) s[5]; o->y_max = (int32_t) s[6];
}

/* ---- ref16: rasterizer_template.h semantics (int16 wraps included) ------ */

static void tc_ubl16(int16_t res[16], int16_t abs_a, const int16_t va[16],
                     int16_t b, int16_t abs_b, int16_t c, int up, int dn)
{
    int16_t size = dn - up;
    int16_t w = TC_FULL + (size << 4) - abs_a;
    w = (w < TC_FULL ? w : TC_FULL) << 3;
    int16_t dc_b = abs_b * (int32_t) size >> 6;
    int16_t dc = ((abs_a < dc_b ? abs_a : dc_b) + 2) >> 2;
    int16_t base = (int32_t) b * (int16_t) (up + dn) >> 7;
    int16_t offs1 = size - ((base + dc) * (int32_t) w >> 16);
    int16_t offs2 = size - ((base - dc) * (int32_t) w >> 16);
    size <<= 1;
    for (int x = 0; x < 16; x++) {
        int16_t cw = (c - va[x]) * (int32_t) w >> 16;
        int16_t c1 = cw + offs1, c2 = cw + offs2;
        c1 = c1 < 0 ? 0 : c1 > size ? size : c1;
        c2 = c2 < 0 ? 0 : c2 > size ? size : c2;
        res[x] += c1 + c2;
    }
}

static void tc_generic16(uint8_t buf[16][16], const TcSeg *segs, int n, int wind)
{
    int16_t res[16][16] = {{0}};
    int16_t delta[16 + 2] = {0};
    for (int i = 0; i < n; i++) {
        const TcSeg *L = &segs[i];
        int16_t up_delta = L->flags & SEGFLAG_DN ? 4 : 0;
        int16_t dn_delta = up_delta;
        if (!L->x_min && (L->flags & SEGFLAG_EXACT_LEFT))
            dn_delta ^= 4;
        if (L->flags & SEGFLAG_UL_DR) {
            int16_t t = up_delta; up_delta = dn_delta; dn_delta = t;
        }
        int up = L->y_min >> 6, dn = L->y_max >> 6;
        int16_t up_pos = L->y_min & 63;
        int16_t up_delta1 = up_delta * up_pos;
        int16_t dn_pos = L->y_max & 63;
        int16_t dn_delta1 = dn_delta * dn_pos;
        delta[up + 1] -= up_delta1;
        delta[up] -= (up_delta << 6) - up_delta1;
        delta[dn + 1] += dn_delta1;
        delta[dn] += (dn_delta << 6) - dn_delta1;
        if (L->y_min == L->y_max)
            continue;

        int16_t a = (int16_t) L->a, b = (int16_t) L->b;
        int16_t c = L->c - (a >> 1) - b * up;   /* int16 store: wraps like C ref */
        int16_t va[16];
        for (int x = 0; x < 16; x++)
            va[x] = a * x;
        int16_t abs_a = a < 0 ? -a : a;
        int16_t abs_b = b < 0 ? -b : b;
        int16_t dc = ((abs_a < abs_b ? abs_a : abs_b) + 2) >> 2;
        int16_t base = TC_FULL / 2 - (b >> 1);
        int16_t dc1 = base + dc, dc2 = base - dc;

        if (up_pos) {
            if (dn == up) {
                tc_ubl16(res[up], abs_a, va, b, abs_b, c, up_pos, dn_pos);
                continue;
            }
            tc_ubl16(res[up], abs_a, va, b, abs_b, c, up_pos, 64);
            up++;
            c -= b;
        }
        for (int y = up; y < dn; y++) {
            for (int x = 0; x < 16; x++) {
                int16_t c1 = c - va[x] + dc1;
                int16_t c2 = c - va[x] + dc2;
                c1 = c1 < 0 ? 0 : c1 > TC_FULL ? TC_FULL : c1;
                c2 = c2 < 0 ? 0 : c2 > TC_FULL ? TC_FULL : c2;
                res[y][x] += (c1 + c2) >> 3;
            }
            c -= b;
        }
        if (dn_pos)
            tc_ubl16(res[dn], abs_a, va, b, abs_b, c, 0, dn_pos);
    }
    int16_t cur = 256 * (int8_t) wind;
    for (int y = 0; y < 16; y++) {
        cur += delta[y];
        for (int x = 0; x < 16; x++) {
            int16_t val = res[y][x] + cur, neg = -val;
            val = val > neg ? val : neg;
            buf[y][x] = (uint8_t) (val < 255 ? val : 255);
        }
    }
}

static void tc_half16(uint8_t buf[16][16], int32_t a, int32_t b, int32_t c)
{
    int16_t aa = (int16_t) a, bb = (int16_t) b;
    int16_t cc = c + TC_FULL / 2 - ((aa + bb) >> 1);   /* int16 store: wraps */
    int16_t abs_a = aa < 0 ? -aa : aa;
    int16_t abs_b = bb < 0 ? -bb : bb;
    int16_t delta = ((abs_a < abs_b ? abs_a : abs_b) + 2) >> 2;
    int16_t va1[16], va2[16];
    for (int x = 0; x < 16; x++) {
        va1[x] = aa * x - delta;
        va2[x] = aa * x + delta;
    }
    for (int y = 0; y < 16; y++) {
        for (int x = 0; x < 16; x++) {
            int16_t c1 = cc - va1[x], c2 = cc - va2[x];
            c1 = c1 < 0 ? 0 : c1 > TC_FULL ? TC_FULL : c1;
            c2 = c2 < 0 ? 0 : c2 > TC_FULL ? TC_FULL : c2;
            int16_t r = (c1 + c2) >> 3;
            buf[y][x] = (uint8_t) (r < 255 ? r : 255);
        }
        cc -= bb;
    }
}

/* one blob-tile group in ref16 semantics */
static void tc_group16(uint8_t buf[16][16], int type, int wind,
                       const TcSeg *segs, int n)
{
    if (type == 0) {
        memset(buf, wind ? 255 : 0, 256);
    } else if (type == 1) {
        tc_half16(buf, segs[0].a, segs[0].b, segs[0].c);
    } else {
        tc_generic16(buf, segs, n, wind);
    }
}

/* ---- gpu32: straight port of vo_gpu_next.c's GLSL filler (plain int32) -- */

static int tc_ubl32(int px, int abs_a, int a, int b, int abs_b, int c,
                    int up, int dn)
{
    int size = dn - up;
    int w = 1024 + (size << 4) - abs_a;
    w = (w < 1024 ? w : 1024) << 3;
    int dc_b = (abs_b * size) >> 6;
    int dc = ((abs_a < dc_b ? abs_a : dc_b) + 2) >> 2;
    int base = (b * (up + dn)) >> 7;
    int offs1 = size - (((base + dc) * w) >> 16);
    int offs2 = size - (((base - dc) * w) >> 16);
    int size2 = size * 2;
    int cw = ((c - a * px) * w) >> 16;
    int c1 = cw + offs1, c2 = cw + offs2;
    c1 = c1 < 0 ? 0 : c1 > size2 ? size2 : c1;
    c2 = c2 < 0 ? 0 : c2 > size2 ? size2 : c2;
    return c1 + c2;
}

static int tc_pixel32(int type, int wind, const TcSeg *segs, int n,
                      int lx, int ly)
{
    if (type == 0)
        return wind ? 255 : 0;
    if (type == 1) {
        int aa = segs[0].a, bb = segs[0].b;
        int cc = segs[0].c + 512 - ((aa + bb) >> 1) - bb * ly;
        int abs_a = aa < 0 ? -aa : aa, abs_b = bb < 0 ? -bb : bb;
        int dl = ((abs_a < abs_b ? abs_a : abs_b) + 2) >> 2;
        int c1 = cc - aa * lx + dl, c2 = cc - aa * lx - dl;
        c1 = c1 < 0 ? 0 : c1 > 1024 ? 1024 : c1;
        c2 = c2 < 0 ? 0 : c2 > 1024 ? 1024 : c2;
        int v = (c1 + c2) >> 3;
        return v < 255 ? v : 255;
    }
    int res = 0, cur = 256 * wind;
    for (int i = 0; i < n; i++) {
        int a = segs[i].a, b = segs[i].b, c0 = segs[i].c;
        int flags = segs[i].flags, xmin = segs[i].x_min;
        int ymn = segs[i].y_min, ymx = segs[i].y_max;
        int upd = (flags & 1) ? 4 : 0, dnd = upd;
        if (xmin == 0 && (flags & 4))
            dnd = 4 - dnd;
        if (flags & 2) { int t = upd; upd = dnd; dnd = t; }
        int up = ymn >> 6, dn = ymx >> 6, upp = ymn & 63, dnp = ymx & 63;
        if (up     <= ly) cur -= (upd << 6) - upd * upp;
        if (up + 1 <= ly) cur -= upd * upp;
        if (dn     <= ly) cur += (dnd << 6) - dnd * dnp;
        if (dn + 1 <= ly) cur += dnd * dnp;
        if (ymn == ymx)
            continue;
        int abs_a = a < 0 ? -a : a, abs_b = b < 0 ? -b : b;
        int dc = ((abs_a < abs_b ? abs_a : abs_b) + 2) >> 2;
        int base = 512 - (b >> 1);
        int c = c0 - (a >> 1) - b * up, rup = up;
        if (upp != 0) {
            if (dn == up) {
                if (ly == up)
                    res += tc_ubl32(lx, abs_a, a, b, abs_b, c, upp, dnp);
                continue;
            }
            if (ly == up)
                res += tc_ubl32(lx, abs_a, a, b, abs_b, c, upp, 64);
            rup = up + 1;
            c -= b;
        }
        if (ly >= rup && ly < dn) {
            int cy = c - b * (ly - rup);
            int c1 = cy - a * lx + base + dc;
            int c2 = cy - a * lx + base - dc;
            c1 = c1 < 0 ? 0 : c1 > 1024 ? 1024 : c1;
            c2 = c2 < 0 ? 0 : c2 > 1024 ? 1024 : c2;
            res += (c1 + c2) >> 3;
        }
        if (dnp != 0 && ly == dn) {
            int cy = c - b * (dn - rup);
            res += tc_ubl32(lx, abs_a, a, b, abs_b, cy, 0, dnp);
        }
    }
    int val = res + cur, neg = -val;
    val = val > neg ? val : neg;
    return val < 255 ? val : 255;
}

static void tc_group32(uint8_t buf[16][16], int type, int wind,
                       const TcSeg *segs, int n)
{
    for (int y = 0; y < 16; y++)
        for (int x = 0; x < 16; x++)
            buf[y][x] = (uint8_t) tc_pixel32(type, wind, segs, n, x, y);
}

/* Rasterize one blob tile (<=2 groups, max-merged) with a group filler. */
typedef void (*tc_group_fn)(uint8_t buf[16][16], int type, int wind,
                            const TcSeg *segs, int n);

static void tc_tile(tc_group_fn fn, const float *tile, const float *segpool,
                    uint8_t out[16][16])
{
    int ng = (int) tile[2];
    for (int g = 0; g < ng && g < 2; g++) {
        const float *G = tile + 3 + 4 * g;
        int type = (int) G[0], wind = (int) G[1];
        int soff = (int) G[2], scnt = (int) G[3];
        TcSeg sbuf[64], *segs = sbuf;
        if (scnt > 64 && !(segs = malloc((size_t) scnt * sizeof(TcSeg))))
            return;
        int n = scnt;
        for (int i = 0; i < n; i++)
            tc_seg(segpool + (size_t) (soff + i) * SEG_EXPORT_W, &segs[i]);
        uint8_t tmp[16][16];
        fn(tmp, type, wind, segs, n);
        if (segs != sbuf)
            free(segs);
        if (g == 0) {
            memcpy(out, tmp, 256);
        } else {
            for (int y = 0; y < 16; y++)
                for (int x = 0; x < 16; x++)
                    out[y][x] = out[y][x] > tmp[y][x] ? out[y][x] : tmp[y][x];
        }
    }
    if (!ng)
        memset(out, 0, 256);
}

/* Reconstruct a whole glyph coverage buffer (bw x bh, stride bw) from a blob. */
static void tc_blob_fill(tc_group_fn fn, const int32_t *blob,
                         int bw, int bh, uint8_t *out)
{
    int nt = blob[0];
    const float *tiles = (const float *) (blob + 2);
    const float *segpool = tiles + (size_t) nt * TILE_EXPORT_W;
    for (int t = 0; t < nt; t++) {
        const float *T = tiles + (size_t) t * TILE_EXPORT_W;
        int tx = (int) T[0], ty = (int) T[1];
        uint8_t cov[16][16];
        tc_tile(fn, T, segpool, cov);
        for (int y = 0; y < 16 && ty + y < bh; y++)
            for (int x = 0; x < 16 && tx + x < bw; x++)
                out[(size_t) (ty + y) * bw + tx + x] = cov[y][x];
    }
}

static int run_tilecmp(ASS_Renderer *r, ASS_Track *track, const char *name)
{
    long long times[MAX_TIMES];
    int nt = collect_times(track, times);
    long long images = 0, tiles = 0, diff_tiles = 0, diff_px = 0;
    int maxdiff = 0, shown = 0;
    for (int i = 0; i < nt; i++) {
        ASS_Image *img = ass_render_frame(r, track, times[i], NULL);
        for (ASS_Image *im = img; im; im = im->next) {
            if (!im->outline || im->n_outline < 2)
                continue;
            images++;
            const int32_t *blob = im->outline;
            int n_tiles = blob[0];
            const float *tarr = (const float *) (blob + 2);
            const float *segpool = tarr + (size_t) n_tiles * TILE_EXPORT_W;
            for (int t = 0; t < n_tiles; t++) {
                const float *T = tarr + (size_t) t * TILE_EXPORT_W;
                int tx = (int) T[0], ty = (int) T[1];
                uint8_t c16[16][16], c32[16][16];
                tc_tile(tc_group16, T, segpool, c16);
                tc_tile(tc_group32, T, segpool, c32);
                tiles++;
                int tile_diff = 0;
                for (int y = 0; y < 16 && ty + y < im->h; y++)
                    for (int x = 0; x < 16 && tx + x < im->w; x++) {
                        int d = (int) c16[y][x] - (int) c32[y][x];
                        if (d < 0)
                            d = -d;
                        if (d) {
                            tile_diff++;
                            if (d > maxdiff)
                                maxdiff = d;
                            if (shown < 8) {
                                shown++;
                                printf("TILECMP-DIFF %s t=%lld img w=%d h=%d "
                                       "tile(%d,%d) px(%d,%d) ref16=%d gpu32=%d "
                                       "ng=%d g0=(type %d wind %d nseg %d)\n",
                                       name, times[i], im->w, im->h, tx, ty,
                                       x, y, c16[y][x], c32[y][x], (int) T[2],
                                       (int) T[3], (int) T[4], (int) T[6]);
                            }
                        }
                    }
                if (tile_diff) {
                    diff_tiles++;
                    diff_px += tile_diff;
                }
            }
        }
    }
    printf("TILECMP %s: %lld images, %lld tiles, %lld diff-tiles, "
           "%lld diff-px, maxdiff %d -> %s\n", name, images, tiles,
           diff_tiles, diff_px, maxdiff, diff_tiles ? "DIVERGES" : "MATCHES");
    return 0;   /* informational: divergence is the finding, not a failure */
}

/* ---- tileself: ref16 + blob encoding vs the real CPU rasterizer --------- */

#define TS_RASTERIZER_PRECISION 16   /* == ass_render.c RASTERIZER_PRECISION */

static long long ts_gpu32_diverged;   /* informational: gpu32 vs direct */

static int ts_check_outline(const ASS_Outline *ol, const char *what,
                            long long *n_bytes)
{
    float *tiles = NULL, *segs = NULL;
    int n_tiles = 0, n_segs = 0;
    int32_t left, top, w, h;
    if (!ass_outline_to_tiles(ol, NULL, TS_RASTERIZER_PRECISION, &tiles,
                              &n_tiles, &segs, &n_segs, &left, &top, &w, &h)) {
        printf("TILESELF %s: empty export\n", what);
        return 1;
    }
    int tw = (w + 15) & ~15, th = (h + 15) & ~15;

    /* direct: the real CPU engine over the same window */
    BitmapEngine eng = ass_bitmap_engine_init(0);
    RasterizerData rst;
    uint8_t *direct = NULL, *from_blob = NULL;
    int32_t *blob = NULL;
    int rc = 1;
    if (!ass_rasterizer_init(&eng, &rst, TS_RASTERIZER_PRECISION))
        goto done;
    if (!ass_rasterizer_set_outline(&rst, ol, false)) {
        ass_rasterizer_done(&rst);
        goto done;
    }
    direct = aligned_alloc(32, (size_t) tw * th);
    from_blob = calloc(1, (size_t) tw * th);
    if (!direct || !from_blob ||
        !ass_rasterizer_fill(&eng, &rst, direct, left, top, tw, th, tw)) {
        ass_rasterizer_done(&rst);
        goto done;
    }
    ass_rasterizer_done(&rst);

    /* blob -> ref16 over the full tile grid (tw x th) */
    size_t total = 2 + (size_t) n_tiles * TILE_EXPORT_W
                     + (size_t) n_segs * SEG_EXPORT_W;
    blob = malloc(total * sizeof(int32_t));
    if (!blob)
        goto done;
    blob[0] = n_tiles;
    blob[1] = n_segs;
    memcpy(blob + 2, tiles, (size_t) n_tiles * TILE_EXPORT_W * sizeof(float));
    memcpy(blob + 2 + (size_t) n_tiles * TILE_EXPORT_W, segs,
           (size_t) n_segs * SEG_EXPORT_W * sizeof(float));
    tc_blob_fill(tc_group16, blob, tw, th, from_blob);

    long long bad = 0;
    for (size_t k = 0; k < (size_t) tw * th; k++)
        if (direct[k] != from_blob[k]) {
            if (!bad)
                printf("TILESELF %s: first mismatch at (%d,%d): "
                       "direct=%d ref16=%d\n", what, (int) (k % tw),
                       (int) (k / tw), direct[k], from_blob[k]);
            bad++;
        }
    *n_bytes += (long long) tw * th;

    /* informational: does the shipped int32 GLSL port reach the CPU's int16
     * wraparound cases on this synthetic steep content? */
    memset(from_blob, 0, (size_t) tw * th);
    tc_blob_fill(tc_group32, blob, tw, th, from_blob);
    for (size_t k = 0; k < (size_t) tw * th; k++)
        if (direct[k] != from_blob[k])
            ts_gpu32_diverged++;
    if (bad)
        printf("TILESELF %s: %dx%d, %lld MISMATCHED bytes -> FAIL\n",
               what, tw, th, bad);
    rc = bad != 0;
done:
    free(direct);
    free(from_blob);
    free(blob);
    free(tiles);
    free(segs);
    return rc;
}

static int run_tileself(void)
{
    /* Long thin spikes from a center at many angles: every spike edge is a
     * long steep segment; across angles this sweeps the full range of tile
     * line-equation coefficients (incl. the int16-wrapping corner cases that
     * 3D perspective produces). Coordinates in 1/64 px. */
    int fails = 0;
    long long checked = 0;
    ASS_Vector pts[3 * 720];
    char segs[3 * 720];
    for (int pass = 0; pass < 3; pass++) {
        double cx = 200.5 * 64, cy = 150.25 * 64;
        double rad = (pass == 0 ? 120 : pass == 1 ? 300 : 37.3) * 64;
        double thin = pass == 2 ? 0.001 : 0.013;   /* spike half-angle (rad) */
        int n = 0;
        int nspikes = pass == 1 ? 720 : 180;
        for (int k = 0; k < nspikes; k++) {
            double th = k * (2 * 3.14159265358979 / nspikes) + 0.0007 * pass;
            pts[n] = (ASS_Vector) { (int) cx, (int) cy };
            segs[n++] = OUTLINE_LINE_SEGMENT;
            pts[n] = (ASS_Vector) { (int) (cx + rad * cos(th - thin)),
                                    (int) (cy + rad * sin(th - thin)) };
            segs[n++] = OUTLINE_LINE_SEGMENT;
            pts[n] = (ASS_Vector) { (int) (cx + rad * cos(th + thin)),
                                    (int) (cy + rad * sin(th + thin)) };
            segs[n++] = OUTLINE_LINE_SEGMENT | OUTLINE_CONTOUR_END;
        }
        ASS_Outline ol = { .points = pts, .segments = segs,
                           .n_points = n, .n_segments = n };
        char what[64];
        snprintf(what, sizeof(what), "spikes-pass%d", pass);
        fails += ts_check_outline(&ol, what, &checked);
    }
    printf("TILESELF: %lld bytes compared, %d failures -> %s "
           "(gpu32-vs-direct diverged bytes: %lld)\n",
           checked, fails, fails ? "FAIL" : "PASS", ts_gpu32_diverged);
    return fails != 0;
}

#endif /* !INT8K_NO_OUTLINE */

/* ------------------------------------------------------------------------- */

int main(int argc, char **argv)
{
    int threads = -1, fw = 1280, fh = 720;
    int mode = 0;   /* 0=hash 1=outline 2=blurdefer 3=tilecmp 4=tileself */
    int argi = 1;
    for (; argi < argc && argv[argi][0] == '-'; argi++) {
        if (!strcmp(argv[argi], "-t") && argi + 1 < argc)
            threads = atoi(argv[++argi]);
        else if (!strcmp(argv[argi], "-W") && argi + 1 < argc)
            fw = atoi(argv[++argi]);
        else if (!strcmp(argv[argi], "-H") && argi + 1 < argc)
            fh = atoi(argv[++argi]);
        else if (!strcmp(argv[argi], "-m") && argi + 1 < argc) {
            const char *mv = argv[++argi];
            mode = !strcmp(mv, "outline")   ? 1 :
                   !strcmp(mv, "blurdefer") ? 2 :
                   !strcmp(mv, "tilecmp")   ? 3 :
                   !strcmp(mv, "tileself")  ? 4 : 0;
        } else {
            fprintf(stderr, "unknown option '%s'\n", argv[argi]);
            return 2;
        }
    }
#ifndef INT8K_NO_OUTLINE
    if (mode == 4)   /* self-contained; needs no corpus, fonts or renderer */
        return run_tileself();
#endif
    if (argi >= argc) {
        fprintf(stderr, "usage: %s [-t threads] "
                        "[-m hash|outline|blurdefer|tilecmp|tileself] "
                        "[-W w] [-H h] dir...\n", argv[0]);
        return 2;
    }
#ifdef INT8K_NO_OUTLINE
    if (mode == 1 || mode == 3 || mode == 4) {
        fprintf(stderr, "outline modes not compiled in\n");
        return 2;
    }
#endif

    g_lib = ass_library_init();
    if (!g_lib)
        return 1;
    ass_set_message_cb(g_lib, msg_cb, NULL);
    ass_set_extract_fonts(g_lib, 1);

    for (int d = argi; d < argc; d++)
        load_fonts(argv[d]);

    ASS_Renderer *r = ass_renderer_init(g_lib);
    if (!r)
        return 1;
    ass_set_fonts(r, NULL, NULL, ASS_FONTPROVIDER_NONE, NULL, 0);
    ass_set_storage_size(r, fw, fh);
    ass_set_frame_size(r, fw, fh);
    if (threads >= 0)
        ass_set_render_thread_count(r, threads);
#ifndef INT8K_NO_OUTLINE
    if (mode == 1 || mode == 3)
        ass_set_outline_deferred(r, 1);
#endif

    if (mode == 2) {   /* self-contained; ignores the .ass corpus */
        int brc = run_blurdefer(r, fw, fh);
        ass_renderer_done(r);
        ass_library_done(g_lib);
        return brc;
    }

    int rc = 0, nsubs = 0;
    for (int d = argi; d < argc; d++) {
        DIR *dir = opendir(argv[d]);
        if (!dir)
            continue;
        /* collect + sort names for deterministic order */
        char *names[256];
        int nn = 0;
        struct dirent *e;
        while ((e = readdir(dir)) && nn < 256)
            if (has_ext(e->d_name, ".ass"))
                names[nn++] = strdup(e->d_name);
        closedir(dir);
        for (int i = 1; i < nn; i++)
            for (int j = i; j > 0 && strcmp(names[j - 1], names[j]) > 0; j--) {
                char *t = names[j]; names[j] = names[j - 1]; names[j - 1] = t;
            }
        for (int i = 0; i < nn; i++) {
            char path[4096];
            snprintf(path, sizeof(path), "%s/%s", argv[d], names[i]);
            ASS_Track *track = ass_read_file(g_lib, path, NULL);
            if (!track) {
                fprintf(stderr, "failed to load '%s'\n", path);
                rc = 1;
                continue;
            }
            nsubs++;
#ifndef INT8K_NO_OUTLINE
            if (mode == 1)
                rc |= run_outline(r, track, names[i]);
            else if (mode == 3)
                rc |= run_tilecmp(r, track, names[i]);
            else
#endif
                rc |= run_hash(r, track, names[i], fw, fh);
            ass_free_track(track);
            free(names[i]);
        }
    }
    if (!nsubs) {
        fprintf(stderr, "no .ass files found\n");
        rc = 2;
    }
    ass_renderer_done(r);
    ass_library_done(g_lib);
    return rc;
}
