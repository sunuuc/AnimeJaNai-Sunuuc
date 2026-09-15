"""Verify live self-contained .NET apps, including statically linked singlefilehost.

Microsoft's Windows singlefilehost exports DotNetRuntimeInfo/g_CLREngineMetrics
from the EXE itself; a separate coreclr.dll is NOT required. See:
https://github.com/dotnet/runtime/blob/v10.0.0/src/native/corehost/apphost/static/singlefilehost.def
No process memory is modified and no executable is loaded by this inspector.
"""
from pathlib import Path
import ctypes as C
from ctypes import wintypes as W
import json
import mmap
import ntpath
import os
import struct

RUNTIME_EXPORTS = frozenset({'DotNetRuntimeInfo', 'g_CLREngineMetrics'})
RUNTIME_DLLS = frozenset({'coreclr.dll', 'clrjit.dll', 'hostfxr.dll', 'hostpolicy.dll'})


def pe_exports(data):
    """Parse bounded, file-backed PE64 exports without executing the image."""
    size = len(data)

    def need(offset, count):
        if offset < 0 or count < 0 or offset + count > size:
            raise ValueError('Truncated or invalid PE range')
        return offset

    def u16(offset):
        return struct.unpack_from('<H', data, need(offset, 2))[0]

    def u32(offset):
        return struct.unpack_from('<I', data, need(offset, 4))[0]

    if data[:2] != b'MZ':
        raise ValueError('Not a PE executable')
    pe = u32(0x3c)
    if data[need(pe, 24):pe + 4] != b'PE\0\0':
        raise ValueError('Bad PE signature')
    if u16(pe + 4) != 0x8664:
        raise ValueError('Expected a Windows x64 image')
    count, optsize = u16(pe + 6), u16(pe + 20)
    opt = pe + 24
    need(opt, optsize)
    if optsize < 120 or u16(opt) != 0x20b or not 1 <= count <= 96:
        raise ValueError('Invalid PE64 optional/section header')
    if u32(opt + 108) < 1:
        return set()
    export_rva, export_size = u32(opt + 112), u32(opt + 116)
    if not export_rva and not export_size:
        return set()
    if not export_rva or export_size < 40:
        raise ValueError('Invalid export directory')
    headers_size = u32(opt + 60)
    sections = []
    for index in range(count):
        s = need(opt + optsize + 40 * index, 40)
        sections.append((u32(s + 12), u32(s + 20), u32(s + 16), u32(s + 8)))

    def offset(rva, length):
        if rva < headers_size and rva + length <= headers_size:
            return need(rva, length)
        for start, raw, rawsize, virtualsize in sections:
            relative = rva - start
            if relative >= 0 and relative + length <= rawsize:
                return need(raw + relative, length)
        raise ValueError('Export RVA is not backed by file data')

    directory = offset(export_rva, 40)
    functions, names = u32(directory + 20), u32(directory + 24)
    if names > 32768 or functions > 1000000:
        raise ValueError('Unreasonable PE export table')
    fn = offset(u32(directory + 28), functions * 4)
    table = offset(u32(directory + 32), names * 4)
    ordinals = offset(u32(directory + 36), names * 2)
    result = set()
    for index in range(names):
        ordinal = u16(ordinals + index * 2)
        if ordinal >= functions:
            raise ValueError('Invalid export ordinal')
        target = u32(fn + ordinal * 4)
        name_rva = u32(table + index * 4)
        name_offset = offset(name_rva, 1)
        end = data.find(b'\0', name_offset, min(size, name_offset + 1024))
        if end < 0:
            raise ValueError('Unterminated export name')
        offset(name_rva, end - name_offset + 1)
        name = data[name_offset:end].decode('ascii')
        # Forwarders and null addresses do not prove a statically linked CLR.
        if not target or export_rva <= target < export_rva + export_size:
            continue
        # Exported data may live in zero-initialized .bss (virtual-only data).
        # Names/tables must be file-backed; the target only has to be mapped.
        if not any(start <= target < start + max(rawsize, virtualsize)
                   for start, raw, rawsize, virtualsize in sections):
            raise ValueError('Export target is outside all mapped sections')
        result.add(name)
    return result


def executable_exports(exe):
    with Path(exe).open('rb') as source:
        if not source.seek(0, 2):
            raise ValueError('Empty executable')
        source.seek(0)
        with mmap.mmap(source.fileno(), 0, access=mmap.ACCESS_READ) as data:
            return pe_exports(data)


def normalized(path):
    return ntpath.normcase(ntpath.abspath(str(path)))


def is_within(path, root):
    try:
        return ntpath.commonpath([normalized(path), normalized(root)]) == normalized(root)
    except ValueError:
        return False


def classify_runtime(exe, modules, exports, allowed_roots):
    """Accept only a proven static CLR or a CLR loaded from delivered files."""
    if not modules or not any(normalized(m) == normalized(exe) for m in modules):
        raise RuntimeError('Module enumeration did not include the expected executable')
    runtime = [m for m in modules if ntpath.basename(m).lower() in RUNTIME_DLLS]
    external = [m for m in runtime if not any(is_within(m, root) for root in allowed_roots)]
    if external:
        raise RuntimeError('External .NET runtime loaded: ' + repr(external))
    if RUNTIME_EXPORTS.issubset(exports):
        return {'runtime_mode': 'statically-linked-singlefilehost',
                'static_runtime_exports': sorted(RUNTIME_EXPORTS), 'runtime_dlls': runtime}
    if any(ntpath.basename(m).lower() == 'coreclr.dll' for m in runtime):
        return {'runtime_mode': 'bundled-coreclr-dll', 'runtime_dlls': runtime}
    raise RuntimeError('No statically linked CLR or bundled coreclr.dll was verified')


def process_modules(pid):
    """Read the exact process image and native module paths using Unicode Win32 APIs."""
    if os.name != 'nt' or C.sizeof(C.c_void_p) != 8:
        raise RuntimeError('Live inspection requires Windows x64 Python')
    kernel = C.WinDLL('kernel32', use_last_error=True)
    psapi = C.WinDLL('psapi', use_last_error=True)
    kernel.OpenProcess.argtypes = [W.DWORD, W.BOOL, W.DWORD]
    kernel.OpenProcess.restype = W.HANDLE
    kernel.CloseHandle.argtypes = [W.HANDLE]
    kernel.CloseHandle.restype = W.BOOL
    kernel.QueryFullProcessImageNameW.argtypes = [W.HANDLE, W.DWORD, W.LPWSTR, C.POINTER(W.DWORD)]
    kernel.QueryFullProcessImageNameW.restype = W.BOOL
    psapi.EnumProcessModulesEx.argtypes = [W.HANDLE, C.POINTER(W.HMODULE), W.DWORD, C.POINTER(W.DWORD), W.DWORD]
    psapi.EnumProcessModulesEx.restype = W.BOOL
    psapi.GetModuleFileNameExW.argtypes = [W.HANDLE, W.HMODULE, W.LPWSTR, W.DWORD]
    psapi.GetModuleFileNameExW.restype = W.DWORD
    handle = kernel.OpenProcess(0x0400 | 0x0010, False, pid)
    if not handle:
        raise C.WinError(C.get_last_error())
    try:
        image = C.create_unicode_buffer(32768)
        length = W.DWORD(len(image))
        if not kernel.QueryFullProcessImageNameW(handle, 0, image, C.byref(length)):
            raise C.WinError(C.get_last_error())
        capacity = 1024
        for _ in range(4):
            handles = (W.HMODULE * capacity)()
            needed = W.DWORD()
            if not psapi.EnumProcessModulesEx(handle, handles, C.sizeof(handles), C.byref(needed), 3):
                raise C.WinError(C.get_last_error())
            if needed.value <= C.sizeof(handles):
                break
            capacity = needed.value // C.sizeof(W.HMODULE) + 64
        else:
            raise RuntimeError('Process module list did not stabilize')
        paths = []
        for h in handles[:needed.value // C.sizeof(W.HMODULE)]:
            buf = C.create_unicode_buffer(32768)
            size = psapi.GetModuleFileNameExW(handle, h, buf, len(buf))
            if not size or size >= len(buf):
                raise C.WinError(C.get_last_error())
            paths.append(buf.value)
        return image.value, paths
    finally:
        kernel.CloseHandle(handle)


def verify_process(pid, exe, app_root, bundle_root, evidence):
    image, modules = process_modules(pid)
    exports = executable_exports(exe)
    proof = {'pid': pid, 'image': image, 'expected_image': str(exe),
             'modules': modules, 'executable_exports': sorted(exports)}
    path = Path(evidence)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(proof, ensure_ascii=False, indent=2), encoding='utf-8')
    # Save raw evidence BEFORE assertions, including for a failed run.
    if normalized(image) != normalized(exe):
        raise RuntimeError('Inspected the wrong executable: ' + image)
    proof.update(classify_runtime(exe, modules, exports, [app_root, bundle_root]))
    proof['external_dotnet_used'] = False
    path.write_text(json.dumps(proof, ensure_ascii=False, indent=2), encoding='utf-8')
    return {k: proof[k] for k in ('runtime_mode', 'external_dotnet_used', 'runtime_dlls')}
