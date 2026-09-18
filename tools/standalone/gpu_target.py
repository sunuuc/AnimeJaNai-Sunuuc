"""Select the CUDA kernel family in a complete, self-contained distribution."""
from __future__ import annotations
import configparser
import hashlib
import json
import mmap
from pathlib import Path
import struct

TARGET = {'id': 'rtx5080-laptop', 'gpu': 'NVIDIA GeForce RTX 5080 Laptop GPU',
          'backend': 'TensorRT', 'sm': '120'}
COMPONENTS = {'trt-runtime', 'trt-sm120', 'rife'}
DML_FILES = {'aji_dml.dll', 'aji_harness_dml.exe', 'directml.dll',
             'onnxruntime.dll', 'onnxruntime_providers_shared.dll'}
REQUIRED = ('aji.dll', 'aji_trt.dll', 'cudart64_13.dll', 'nvinfer_11.dll',
            'nvinfer_plugin_11.dll', 'nvonnxparser_11.dll', 'trtexec.exe',
            'nvinfer_builder_resource_sm120_11.dll')

def sha(path: Path) -> str:
    with path.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()

def forbidden(name: str) -> bool:
    name = name.lower()
    if name in DML_FILES:
        return True
    if name.startswith('nvinfer_builder_resource_') and name.endswith('.dll'):
        return not name.startswith('nvinfer_builder_resource_sm120_')
    return False

def write(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')

def prune(app: Path, records: list, evidence: Path) -> list:
    inf = app/'animejanai/inference'
    before = {p.relative_to(app).as_posix(): (p.stat().st_size, sha(p))
              for folder in ('onnx', 'rife') for p in (app/'animejanai'/folder).rglob('*.onnx')}
    config_hash = sha(app/'animejanai/animejanai.conf')
    removed = []
    for p in inf.iterdir():
        if p.is_file() and forbidden(p.name):
            removed.append({'path': p.relative_to(app).as_posix(), 'bytes': p.stat().st_size, 'sha256': sha(p)})
            p.unlink()
    selected = []
    for record in records:
        if record['name'] not in COMPONENTS:
            continue
        retained = []
        for f in record['files']:
            p = app/f['path']
            if not p.is_file():
                raise RuntimeError('Required component file missing: '+f['path'])
            if p.stat().st_size != f['bytes'] or sha(p) != f['sha256']:
                raise RuntimeError('Component changed while repacking: '+f['path'])
            retained.append(f)
        selected.append({**record, 'files': retained})
    if {r['name'] for r in selected} != COMPONENTS:
        raise RuntimeError('Target components are incomplete')
    write(inf/'gpu-target.json', TARGET)
    after = {p.relative_to(app).as_posix(): (p.stat().st_size, sha(p))
             for folder in ('onnx', 'rife') for p in (app/'animejanai'/folder).rglob('*.onnx')}
    if before != after or config_hash != sha(app/'animejanai/animejanai.conf'):
        raise RuntimeError('Hardware packaging must not change models or presets')
    report = {'target': TARGET, 'removed_files': removed,
              'removed_bytes': sum(p['bytes'] for p in removed),
              'model_files_preserved': len(after), 'presets_sha256': config_hash,
              'gpu_inference_tested': False}
    write(evidence/'gpu-pruning.json', report)
    return selected

def pe_imports(path: Path) -> list[str]:
    """Read ordinary and delay-load import names without executing a binary."""
    with path.open('rb') as f, mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ) as data:
        def u16(at): return struct.unpack_from('<H', data, at)[0]
        def u32(at): return struct.unpack_from('<I', data, at)[0]
        if data[:2] != b'MZ':
            raise RuntimeError('Invalid PE file: '+str(path))
        pe = u32(0x3c)
        if data[pe:pe+4] != b'PE\0\0':
            raise RuntimeError('Invalid PE header: '+str(path))
        count = u16(pe+6); opt = pe+24; opt_size = u16(pe+20)
        magic = u16(opt)
        if magic not in (0x10b, 0x20b):
            raise RuntimeError('Unknown PE optional header')
        dirs = opt+(112 if magic == 0x20b else 96)
        directory_count = u32(dirs-4)
        image_base = struct.unpack_from('<Q' if magic == 0x20b else '<I', data, opt+(24 if magic == 0x20b else 28))[0]
        sections = []
        for i in range(count):
            pos = opt+opt_size+40*i
            sections.append((u32(pos+12), u32(pos+16), u32(pos+20)))
        def offset(rva):
            if rva < u32(opt+60): return rva
            for va, size, raw in sections:
                if va <= rva < va+size: return raw+rva-va
            raise RuntimeError('Invalid PE RVA in '+str(path))
        names = []
        for index, size, name_field in ((1,20,12),(13,32,4)):
            if directory_count <= index: continue
            rva = u32(dirs+index*8); length = u32(dirs+index*8+4)
            if not rva or not length: continue
            at = offset(rva)
            for i in range(min(length//size, 4096)):
                pos = at+i*size
                if not any(data[pos:pos+size]): break
                name_rva = u32(pos+name_field)
                if index == 13 and not (u32(pos) & 1): name_rva -= image_base
                start = offset(name_rva); end = data.find(b'\0', start, start+512)
                if end < 0: raise RuntimeError('Unterminated PE import')
                names.append(data[start:end].decode('ascii').lower())
        return sorted(set(names))

def validate(app: Path, evidence: Path | None = None) -> dict:
    inf = app/'animejanai/inference'
    target = json.loads((inf/'gpu-target.json').read_text(encoding='utf-8'))
    if target != TARGET: raise RuntimeError('GPU target mismatch')
    for name in REQUIRED:
        if not (inf/name).is_file() or (inf/name).stat().st_size == 0:
            raise RuntimeError('Missing TensorRT dependency: '+name)
    bad = [str(p.relative_to(app)) for p in app.rglob('*') if p.is_file() and forbidden(p.name)]
    if bad: raise RuntimeError('Other GPU binaries in target package: '+repr(bad))
    imports = {}
    for p in inf.iterdir():
        if p.suffix.lower() not in ('.exe','.dll'): continue
        names = pe_imports(p); imports[p.name] = names
        missing = [n for n in names if forbidden(n)]
        if missing: raise RuntimeError('Retained binary needs removed dependency: '+p.name+' '+repr(missing))
    parser = configparser.ConfigParser(interpolation=None,strict=False)
    parser.read(app/'animejanai/animejanai.conf', encoding='utf-8-sig')
    if parser['global'].get('backend','').lower() != 'tensorrt':
        raise RuntimeError('Target backend must be TensorRT')
    report = {'passed': True, 'target': target,
              'kernel_files': sorted(p.name for p in inf.glob('nvinfer_builder_resource_*.dll')),
              'native_imports': imports, 'gpu_inference_tested': False}
    if evidence is not None: write(evidence/'gpu-target.json', report)
    return report
