"""Process memory probe.

Reports private/commit/working-set counters for a given PID (or all mpvnet
processes).  Used to investigate abnormal committed memory growth.

Usage:
    python tools/memprobe.py [pid] [--watch SECONDS]
"""
from __future__ import annotations

import ctypes
import ctypes.wintypes as w
import subprocess
import sys
import time

PROCESS_QUERY_INFORMATION = 0x0400
PROCESS_VM_READ = 0x0010

k32 = ctypes.WinDLL("kernel32", use_last_error=True)
psapi = ctypes.WinDLL("psapi", use_last_error=True)


class PROCESS_MEMORY_COUNTERS_EX(ctypes.Structure):
    _fields_ = [
        ("cb", w.DWORD),
        ("PageFaultCount", w.DWORD),
        ("PeakWorkingSetSize", ctypes.c_size_t),
        ("WorkingSetSize", ctypes.c_size_t),
        ("QuotaPeakPagedPoolUsage", ctypes.c_size_t),
        ("QuotaPagedPoolUsage", ctypes.c_size_t),
        ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t),
        ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
        ("PagefileUsage", ctypes.c_size_t),
        ("PeakPagefileUsage", ctypes.c_size_t),
        ("PrivateUsage", ctypes.c_size_t),
    ]


MB = 1024 * 1024


def mem(pid: int):
    h = k32.OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, False, pid)
    if not h:
        return None
    try:
        c = PROCESS_MEMORY_COUNTERS_EX()
        c.cb = ctypes.sizeof(c)
        ok = psapi.GetProcessMemoryInfo(h, ctypes.byref(c), c.cb)
        if not ok:
            return None
        return {
            "working_set": c.WorkingSetSize / MB,
            "peak_working_set": c.PeakWorkingSetSize / MB,
            "private": c.PrivateUsage / MB,
            "commit": c.PagefileUsage / MB,
            "peak_commit": c.PeakPagefileUsage / MB,
        }
    finally:
        k32.CloseHandle(h)


def list_pids(name: str = "mpvnet.exe"):
    out = subprocess.run(
        ["tasklist", "/FI", f"IMAGENAME eq {name}", "/FO", "CSV", "/NH"],
        capture_output=True,
        text=True,
    ).stdout
    pids = []
    for line in out.splitlines():
        line = line.strip()
        if not line.startswith('"'):
            continue
        parts = [p.strip('"') for p in line.split('","')]
        try:
            pids.append(int(parts[1]))
        except (IndexError, ValueError):
            pass
    return pids


def show(pid: int):
    m = mem(pid)
    if m is None:
        print(f"pid {pid}: cannot read")
        return
    print(
        f"pid {pid}: "
        f"commit={m['commit']:.1f}MB (peak {m['peak_commit']:.1f})  "
        f"private={m['private']:.1f}MB  "
        f"ws={m['working_set']:.1f}MB (peak {m['peak_working_set']:.1f})"
    )


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    watch = None
    if "--watch" in sys.argv:
        watch = float(sys.argv[sys.argv.index("--watch") + 1])

    pids = [int(args[0])] if args else list_pids()
    if not pids:
        print("no mpvnet process found")
        return

    if watch is None:
        for pid in pids:
            show(pid)
        return

    start = time.time()
    while time.time() - start < watch:
        for pid in pids:
            show(pid)
        time.sleep(1)


if __name__ == "__main__":
    main()
