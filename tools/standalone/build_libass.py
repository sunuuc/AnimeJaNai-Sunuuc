"""Build vendored libass with its native SIMD and DirectWrite support on Windows."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
PACKAGES = Path(__file__).with_name('libass-build-packages.json')
REPOSITORY = 'https://repo.msys2.org/mingw/ucrt64/'


def toolchain(cache):
    # Frozen official package hashes make the build independent of later repo updates.
    cache.mkdir(parents=True, exist_ok=True)
    for package in json.loads(PACKAGES.read_text(encoding='utf-8')):
        archive = cache / package['file']
        if not archive.exists() or hashlib.sha256(archive.read_bytes()).hexdigest() != package['sha256']:
            urllib.request.urlretrieve(REPOSITORY + package['file'], archive)
        if hashlib.sha256(archive.read_bytes()).hexdigest() != package['sha256']:
            raise RuntimeError('Build dependency hash mismatch: ' + package['file'])
        with tarfile.open(archive) as source:
            # Only the compiler prefix is needed; tar's data filter rejects unsafe links/paths.
            members = [item for item in source.getmembers() if item.name.startswith('ucrt64/')]
            source.extractall(cache, members=members, filter='data')
    return cache / 'ucrt64'


def build(output, compiler=None, cache=None):
    if compiler is None:
        if sys.version_info < (3, 14):
            raise RuntimeError('Python 3.14 is required to unpack the pinned Zstandard build packages')
        compiler = toolchain(cache or ROOT / 'downloads/libass-build')
    compiler = compiler.resolve()
    source = ROOT / 'third_party/libass'
    output = output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    work = output.parent / 'libass-build'
    work.mkdir(exist_ok=True)
    upstream = json.loads((source / 'UPSTREAM.json').read_text(encoding='utf-8'))
    config = {'ARCH_X86': 1, 'ARCH_X86_64': 1, 'CONFIG_ASM': 1, 'CONFIG_LARGE_TILES': 0,
              'CONFIG_DIRECTWRITE': 1, 'CONFIG_THREADS': 1, 'CONFIG_ICONV': 1, 'CONFIG_UNIBREAK': 1,
              'HAVE_FSTAT': 1, 'HAVE_STRDUP': 1, 'HAVE_STRNDUP': 1,
              'CONFIG_SOURCEVERSION': '"' + upstream['commit'] + ' viewport"'}
    (work / 'config.h').write_text(''.join(f'#define {key} {value}\n' for key, value in config.items()), encoding='utf-8')
    env = os.environ.copy()
    env['PATH'] = str(compiler / 'bin') + os.pathsep + env['PATH']
    objects = []
    for name in ('be_blur', 'blend_bitmaps', 'blur', 'cpuid', 'rasterizer'):
        obj = work / (name + '.obj')
        subprocess.run([str(compiler / 'bin/nasm.exe'), '-f', 'win64', '-Dprivate_prefix=ass', '-DPIC=1',
                        '-DARCH_X86_64=1', '-DCONFIG_LARGE_TILES=0', '-I' + str(source / 'libass') + '/',
                        str(source / 'libass/x86' / (name + '.asm')), '-o', str(obj)], env=env, check=True)
        objects.append(str(obj))
    meson = (source / 'libass/meson.build').read_text(encoding='utf-8')
    start = meson.index('libass_src = files(')
    end = meson.index('\n)', start)
    sources = re.findall(r"'([^']+\.c)'", meson[start:end]) + ['ass_directwrite.c', 'ass_threading.c']
    exports = work / 'libass.def'
    exports.write_text('EXPORTS\n' + (source / 'libass/libass.sym').read_text(encoding='utf-8'), encoding='utf-8')
    subprocess.run([str(compiler / 'bin/gcc.exe'), '-shared', '-O2', '-std=gnu11', '-static-libgcc', '-DHAVE_CONFIG_H',
                    '-I' + str(work), '-I' + str(source / 'libass'),
                    *['-I' + str(compiler / 'include' / name) for name in ('freetype2', 'harfbuzz', 'fribidi')],
                    *[str(source / 'libass' / name) for name in sources], *objects, str(exports),
                    '-L' + str(compiler / 'lib'), '-lfreetype', '-lharfbuzz', '-lfribidi', '-lunibreak', '-liconv',
                    '-lgdi32', '-lole32', '-luuid', '-o', str(output)], env=env, check=True)
    print('Built libass:', hashlib.sha256(output.read_bytes()).hexdigest())


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--toolchain', type=Path)
    parser.add_argument('--cache-dir', type=Path)
    args = parser.parse_args()
    build(args.output, args.toolchain, args.cache_dir)
