/*
 * int8k_copybitmap_test.c -- unit test for the ass_copy_bitmap segments fix.
 *
 * Links against the internal libass static lib (ass_copy_bitmap and friends
 * are internal, not part of the public ABI) and checks that ass_copy_bitmap
 * deep-copies the outline-deferred `segments` blob in both paths:
 *   A) src->buffer == NULL (outline-deferred bitmap: coverage lives in segments)
 *   B) src->buffer != NULL with segments also attached
 * plus that the copy is independent of the source (mutating src does not touch
 * dst) and that free()/ass_free_bitmap of both sides is clean (run under ASan).
 *
 * Build (BUILD = a configured meson build dir):
 *   gcc -O2 -I libass -I $BUILD test/int8k_copybitmap_test.c \
 *       $BUILD/libass/libass.a $(pkg-config --cflags --libs freetype2 harfbuzz \
 *       fribidi fontconfig) -lunibreak -lm -lpthread -o copybitmap_test
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../libass/ass_bitmap.h"
#include "../libass/ass_bitmap_engine.h"

static int failures;

#define CHECK(cond) do {                                             \
    if (!(cond)) {                                                   \
        printf("  FAIL: %s (line %d)\n", #cond, __LINE__);           \
        failures++;                                                  \
    }                                                                \
} while (0)

int main(void)
{
    BitmapEngine engine = ass_bitmap_engine_init(0);

    /* --- Case A: NULL buffer, segments present (outline-deferred bitmap) --- */
    {
        int32_t blob[] = { 3, 1, 7, -4, 100, 200, 300, 42 };
        int n = (int)(sizeof(blob) / sizeof(blob[0]));

        Bitmap src;
        memset(&src, 0, sizeof(src));
        src.buffer = NULL;
        src.w = 48; src.h = 24; src.left = 5; src.top = -9; src.stride = 0;
        src.n_segments = n;
        src.segments = malloc((size_t) n * sizeof(int32_t));
        memcpy(src.segments, blob, sizeof(blob));

        Bitmap dst;
        CHECK(ass_copy_bitmap(&engine, &dst, &src) == true);
        CHECK(dst.buffer == NULL);
        CHECK(dst.segments != NULL);
        CHECK(dst.segments != src.segments);            /* deep copy, not alias */
        CHECK(dst.n_segments == src.n_segments);
        CHECK(dst.w == src.w && dst.h == src.h);
        CHECK(dst.left == src.left && dst.top == src.top);
        if (dst.segments) {   /* guard so a regression FAILs cleanly, not crash */
            CHECK(memcmp(dst.segments, src.segments,
                         (size_t) n * sizeof(int32_t)) == 0);
            /* independence: mutating src must not change dst */
            src.segments[0] = 999;
            CHECK(dst.segments[0] == 3);
        }

        printf("Case A (NULL buffer + segments): %s\n",
               failures ? "see failures" : "ok");
        ass_free_bitmap(&dst);
        ass_free_bitmap(&src);
    }

    /* --- Case B: real buffer AND segments present --- */
    {
        int fa = failures;
        Bitmap src;
        CHECK(ass_alloc_bitmap(&engine, &src, 8, 4, true) == true);
        CHECK(src.segments == NULL && src.n_segments == 0);
        for (int32_t y = 0; y < src.h; y++)
            for (int32_t x = 0; x < src.w; x++)
                src.buffer[y * src.stride + x] = (uint8_t)(y * 8 + x);

        int32_t blob[] = { 11, 22, 33 };
        int n = (int)(sizeof(blob) / sizeof(blob[0]));
        src.n_segments = n;
        src.segments = malloc((size_t) n * sizeof(int32_t));
        memcpy(src.segments, blob, sizeof(blob));

        Bitmap dst;
        CHECK(ass_copy_bitmap(&engine, &dst, &src) == true);
        CHECK(dst.buffer != NULL);
        CHECK(dst.buffer != src.buffer);                /* deep copy */
        CHECK(dst.stride == src.stride);
        if (dst.buffer)
            CHECK(memcmp(dst.buffer, src.buffer,
                         (size_t) src.stride * src.h) == 0);
        CHECK(dst.segments != NULL);
        CHECK(dst.segments != src.segments);
        CHECK(dst.n_segments == n);
        if (dst.segments) {
            CHECK(memcmp(dst.segments, src.segments,
                         (size_t) n * sizeof(int32_t)) == 0);
            src.segments[0] = -1;
            CHECK(dst.segments[0] == 11);
        }

        printf("Case B (buffer + segments): %s\n",
               failures > fa ? "see failures" : "ok");
        ass_free_bitmap(&dst);
        ass_free_bitmap(&src);
    }

    printf("COPYBITMAP: %d failures -> %s\n", failures,
           failures ? "FAIL" : "PASS");
    return failures != 0;
}
