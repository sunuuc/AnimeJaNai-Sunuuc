# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this fork is

`the-database/libass` — a fork of [`libass/libass`](https://github.com/libass/libass) that adds
**multithreaded rendering** and a set of **deferred GPU primitives**: instead of rasterizing,
blurring, and compositing subtitle bitmaps on the CPU, libass can hand the consumer the
ingredients (glyph outlines, per-glyph images, blur parameters) and let it do the work on the
GPU.

Its only consumer is `the-database/mpv`, which probes for each new symbol independently and
falls back to the CPU path when it is missing.

Remotes: `origin` = `the-database/libass`, `upstream` = `libass/libass`. `origin/master` is
currently **55 commits ahead of and 0 behind `upstream/master`**.

> **Check out `origin/master` before working here.** This clone has sat at
> `upstream/master` (`ad64758`, none of the fork work present) — branching from a stale `HEAD`
> puts your work on the wrong history. Always `git fetch origin && git checkout origin/master`
> first, and re-fetch `upstream` before judging what the fork actually changes: a stale
> `upstream` ref makes upstream's own commits look like fork changes.

Beware of a sibling clone of **plain upstream** (`origin` = `libass/libass`) kept alongside this
one as a read-only reference. Check `git remote -v` before assuming which tree you are in.

## The fork's delta

25 files vs upstream: two added sources (`libass/ass_threading.{c,h}`), three added test files
(`test/int8k_harness.c`, `test/int8k_copybitmap_test.c`, `test/int8k_giant.ass`), the build
system, and the renderer/bitmap/cache/rasterizer internals.

**The fork changes no CI.** `.github/workflows/` is untouched — `ghci.yml`, `meson.yml`,
`qemu-arch.yml`, and `vm.yml` are all exactly upstream's. Nothing is released from this repo
either: consumers clone it by ref and build it themselves.

### New public API (`libass/ass.h`)

| Symbol | Line | What |
|---|---|---|
| `ass_set_render_thread_count` / `ass_get_render_thread_count` | 813 / 821 | opt-in multithreaded rendering |
| `ass_set_blur_deferred` | 542 | emit blur parameters instead of applying the gaussian blur |
| `ass_set_composite_deferred` | 564 | emit uncombined per-glyph images for a GPU compositor |
| `ass_set_outline_deferred` | 579 | emit glyph **outlines** instead of rasterized bitmaps |
| `ass_frame_ref` / `ass_frame_unref` | 599 / 610 | refcount the frame image list so a consumer can hold it past the next render |

Plus new `ASS_Image` fields: `int32_t shift_x64, shift_y64` (line 190) carry the **fractional**
drop-shadow offset, with the exact two-pass smear formula documented in the header.

All seven functions are exported through `libass/libass.sym`, which is the version script the
autotools build applies. **A new public symbol must be added there or it will not be
exported** from a shared build.

### Build-system changes — one option, two spellings

The fork adds exactly one build option, and the two build systems default it differently.
This is the single most important thing to know here.

**meson** (`meson_options.txt`, `meson.build`, `libass/meson.build`):

```meson
option('threads', type: 'feature', description: 'Multithreaded rendering support')
```

A `feature` type defaults to `auto`, and `dependency('threads', required: get_option('threads'))`
sets `CONFIG_THREADS` and pulls `ass_threading.c` into the sources when found. Consumers that
want it guaranteed pass `-Dthreads=enabled` — which is exactly what `the-database/mpv-winbuild`
`sed`s into the toolchain's `packages/libass.cmake` for the Windows build.

**autotools** (`configure.ac`, `libass/Makefile_library.am`):

```
--disable-threads   disable multithreaded rendering support [default=check]
```

The probe tries `-pthread`, then `-lpthread`, then no flag at all (pthreads in libc on modern
glibc, or Win32 threads, which need nothing), defines `CONFIG_THREADS` on success, and errors
out only if `--enable-threads` was explicitly requested and nothing worked. `AM_CONDITIONAL([THREADS])`
then adds `ass_threading.c` to the sources.

Because autotools defaults to *check*, `mpv`'s Linux bundle script gets threading from a bare
`./configure --prefix=... --disable-static --enable-shared` with no threads flag at all.

## Building

### Linux / WSL — meson (the dev loop)

The clone at `~/src/libass` has four configured build directories; these are their
recorded option strings:

```bash
meson setup build       -Dcompare=enabled -Dtest=enabled -Dprefix=$HOME/.local \
                        -Ddefault_library=both -Db_sanitize=address -Db_ndebug=false -Db_lundef=false
meson setup build-asan  -Db_sanitize=address,undefined -Db_lundef=false
meson setup build-noth  -Dthreads=disabled -Dcompare=enabled
meson setup build-tsan  -Db_sanitize=thread -Db_lundef=false --buildtype=debugoptimized
ninja -C <dir>
```

`-Db_lundef=false` is what lets a sanitizer build link. **`build-noth` is the important one**:
`-Dthreads=disabled` is how you check that the single-threaded path still works — the threading
code is conditionally compiled, so a change that only builds with `CONFIG_THREADS` will pass
every other build.

`build-tsan` exists because this fork's bugs are concurrency bugs. The history includes
`threading: release/acquire ordering on task-region completion` and
`threading: don't touch the task region after its final done increment`; run the thread
sanitizer before trusting a change to `ass_threading.c` or the task regions.

> `--buildtype=debugoptimized` appears in `build-tsan`'s `cmd_line.txt` but not in its log's
> `Build Options:` line, so it was set either on the setup line or by a later
> `meson configure` — unverified which.

### Windows / MSYS2 UCRT64 — meson only

```bash
meson setup libass-build libass-src --prefix=<stable-prefix> -Ddefault_library=shared -Dasm=disabled
ninja -C libass-build install
# installs libass-9.dll, libass.dll.a, ass.h, ass_types.h, libass.pc
```

`-Dasm=disabled` is required because MSYS2 UCRT64 has no `nasm`.

**The autotools build cannot be run in MSYS2 UCRT64** — that environment has no `autoconf`,
`automake`, `libtool`, or `make`. Use meson on Windows.

### Linux release build — autotools

The mpv Linux bundle (`ci/build-linux-portable.sh` in `the-database/mpv`) builds this fork with
autotools, deliberately:

```bash
./autogen.sh && ./configure --prefix="$PREFIX" --disable-static --enable-shared && make && make install
```

The reason, quoted from that script: libass's meson build cannot restrict symbol visibility on
a shared library ("not suitable for distribution"), while the autotools build applies the
`libass.sym` version script. So **meson for development, autotools for anything shipped from
Linux.**

### Tests

```bash
meson test -C build            # meson
make check                     # autotools
```

`test/int8k_harness.c` is fork-added, for A/B, threading, and outline-mode verification;
its `tilecmp` / `tileself` modes check the GPU tile filler. `test/int8k_giant.ass` is the
giant-glyph corpus that goes with `int8k_copybitmap_test.c`.

## How mpv consumes this

`the-database/mpv`'s `meson.build` probes each symbol independently with
`cc.has_header_symbol(..., dependencies: libass)` — compile-only declaration checks, not link
probes — and one `cc.has_member` for `ASS_Image.shift_x64`:

| mpv feature | `config.h` | probes |
|---|---|---|
| `ass-render-thread-count` | `HAVE_ASS_RENDER_THREAD_COUNT` | `ass_set_render_thread_count` |
| `ass-blur-deferred` | `HAVE_ASS_BLUR_DEFERRED` | `ass_set_blur_deferred` |
| `ass-composite-deferred` | `HAVE_ASS_COMPOSITE_DEFERRED` | `ass_set_composite_deferred` |
| `ass-outline-deferred` | `HAVE_ASS_OUTLINE_DEFERRED` | `ass_set_outline_deferred` |
| `ass-shadow-shift` | `HAVE_ASS_SHADOW_SHIFT` | `ASS_Image.shift_x64` |

**The fork may ship any subset, and every mpv consumer is guarded separately.** That is the
compatibility contract: adding a symbol here lights up one mpv feature, and shipping without it
silently degrades that feature to the CPU path (with a one-shot `MP_WARN`) rather than breaking
the build. Removing or renaming an exported symbol therefore fails silently downstream —
verify against mpv's `config.h` after any API change.

Both shipped mpv builds clone this fork's **`master`** by ref:

- Windows — `the-database/mpv-winbuild` resolves `libass_ref` (default `master`) to a SHA and
  pins `packages/libass.cmake` to it, adding `-Dthreads=enabled`.
- Linux — `the-database/mpv`'s `ci/build-linux-portable.sh` clones `master` at depth 1.

So **landing on `master` here is the release action**; there is no tag or artifact to publish.

## Topic branches

`origin` carries the work-in-progress branches the features were developed on:
`multithreaded-rendering`, `phase3-parallel-blur`, `raster-parallel`, `deferred-composite`,
`gpu-blur-spike`, `integration-8k`, `fix-win32-thread-include`, `k1-shardprobe`,
`k4-deferredprofile`, `k7-cacheinstr`, `subtitle-work-backup`. They are historical; `master`
carries everything that shipped.

## Conventions

- Commits: author `the-database`, short imperative subject, no co-author trailers. Subjects here
  are area-prefixed (`ass:`, `threading:`, `ass_bitmap:`, `test:`).
- Keep upstream-mergeable: the fork tracks upstream by merge, and `ass_render.c` /
  `ass_bitmap.c` / `ass_cache.c` are the usual conflict sites.
- A new public symbol needs: the declaration in `ass.h`, an entry in `libass/libass.sym`, and —
  if mpv is meant to use it — a matching probe in mpv's `meson.build`.
