"""Build the vendored converter and static PCRE2 with a pinned C toolchain."""
from pathlib import Path
import argparse
import hashlib
import re
import shutil
import subprocess
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[2]
ZIG_URL = 'https://ziglang.org/download/0.14.1/zig-x86_64-windows-0.14.1.zip'
ZIG_SHA = '554f5378228923ffd558eac35e21af020c73789d87afeabf4bfd16f2e6feed2c'
PCRE_URL = 'https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.46/pcre2-10.46.zip'
PCRE_SHA = 'd872153b2d2338f7bc7b6e9bcc2f7f0c8a529c34fe48c538fea0b3a4e062f046'


def dependency(folder, name, url, expected):
    archive = folder / name
    folder.mkdir(parents=True, exist_ok=True)
    if not archive.exists() or hashlib.sha256(archive.read_bytes()).hexdigest() != expected:
        urllib.request.urlretrieve(url, archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != expected:
        raise RuntimeError('Build dependency hash mismatch: ' + name)
    with zipfile.ZipFile(archive) as source:
        for item in source.infolist():
            target = (folder / item.filename).resolve()
            if not target.is_relative_to(folder.resolve()):
                raise RuntimeError('Invalid build archive path')
        source.extractall(folder)


def build(output, zig=None, pcre=None):
    folder = ROOT / 'downloads/danmaku-build'
    if zig is None:
        dependency(folder, 'zig.zip', ZIG_URL, ZIG_SHA)
        zig = folder / 'zig-x86_64-windows-0.14.1/zig.exe'
    if pcre is None:
        dependency(folder, 'pcre2.zip', PCRE_URL, PCRE_SHA)
        pcre = folder / 'pcre2-10.46'
    src = pcre / 'src'
    for original, generated in [('config.h.generic', 'config.h'),
                                ('pcre2.h.generic', 'pcre2.h'),
                                ('pcre2_chartables.c.dist', 'pcre2_chartables.c')]:
        shutil.copy2(src / original, src / generated)
    # PCRE2's own standalone build instructions specify this translation-unit list.
    notes = (pcre / 'NON-AUTOTOOLS-BUILD').read_text()
    start = notes.index('       pcre2_auto_possess.c')
    end = notes.index('     Make sure', start)
    pcre_sources = re.findall(r'pcre2_\w+\.c', notes[start:end])
    sources = sorted((ROOT / 'third_party/danmaku-factory/src').rglob('*.c'))
    output = output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    # A portable release must not inherit AVX/CPU features from the build host.
    # Canonical source paths also keep diagnostics independent of checkout paths.
    subprocess.run([str(zig.resolve()), 'cc', '-target', 'x86_64-windows-gnu',
                    '-mcpu=baseline', '-ffile-prefix-map=' + str(ROOT.resolve()) + '=.',
                    '-std=gnu11', '-O2', '-s',
                    '-DPCRE2_STATIC', '-DPCRE2_CODE_UNIT_WIDTH=8', '-DHAVE_CONFIG_H',
                    '-DSUPPORT_PCRE2_8', '-DSUPPORT_UNICODE', '-I' + str(src.resolve()),
                    *map(str, sources), *[str(src.resolve() / name) for name in pcre_sources],
                    '-lshell32', '-luser32', '-o', str(output)], check=True)
    print('Built DanmakuFactory:', hashlib.sha256(output.read_bytes()).hexdigest())


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--zig', type=Path)
    parser.add_argument('--pcre2-source', type=Path)
    args = parser.parse_args()
    build(args.output, args.zig, args.pcre2_source)
