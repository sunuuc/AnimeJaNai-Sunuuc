"""Run tests/test_player_ui_logic.lua through the player's own Lua 5.1 DLL.

The Player UI logic suite stubs the whole `mp` API, so it needs no player and no
window - only a Lua 5.1 interpreter and `arg[1] = <repo root>`. Driving it via
mpvapp/lua51.dll keeps the loop fast and lets a debug line be injected into a
copy of the suite without touching the real test file.

Usage:
    python tools/run_player_ui_logic.py [--patch-before LINE --patch-code CODE]
"""
from __future__ import annotations

import argparse
import ctypes
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = (HERE / "..").resolve()
DLL = ROOT / "mpvapp" / "lua51.dll"
SUITE = ROOT / "tests" / "test_player_ui_logic.lua"

_lua = ctypes.CDLL(str(DLL))
_lua.luaL_newstate.restype = ctypes.c_void_p
_lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
_lua.luaL_loadfile.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
_lua.luaL_loadfile.restype = ctypes.c_int
_lua.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
_lua.luaL_loadstring.restype = ctypes.c_int
_lua.lua_pcall.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int]
_lua.lua_pcall.restype = ctypes.c_int
_lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(ctypes.c_size_t)]
_lua.lua_tolstring.restype = ctypes.c_char_p


def run(chunk_name: str, code: str) -> int:
    L = _lua.luaL_newstate()
    _lua.luaL_openlibs(L)

    # The suite asserts arg[1] is the repo root.
    boot = (
        "arg = { [0] = 'test_player_ui_logic', "
        f"[1] = {str(ROOT).replace(chr(92), '/')!r} }}"
    )
    if _lua.luaL_loadstring(L, boot.encode()) != 0 or _lua.lua_pcall(L, 0, 0, 0) != 0:
        print("bootstrap failed")
        return 2

    if _lua.luaL_loadstring(L, code.encode("utf-8")) != 0:
        n = ctypes.c_size_t()
        msg = _lua.lua_tolstring(L, -1, ctypes.byref(n))
        print("LOAD ERROR:", msg.decode("utf-8", "replace") if msg else "?")
        return 3

    rc = _lua.lua_pcall(L, 0, 0, 0)
    if rc != 0:
        n = ctypes.c_size_t()
        msg = _lua.lua_tolstring(L, -1, ctypes.byref(n))
        print("ERROR:", msg.decode("utf-8", "replace") if msg else "?")
    return rc


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--patch-before", type=int, default=0)
    ap.add_argument("--patch-code", default="")
    args = ap.parse_args()

    src = SUITE.read_text(encoding="utf-8")
    if args.patch_before and args.patch_code:
        lines = src.split("\n")
        idx = args.patch_before - 1
        lines.insert(idx, args.patch_code)
        src = "\n".join(lines)
        print(f"injected debug before line {args.patch_before}\n")

    rc = run("test_player_ui_logic", src)
    print("exit", rc)
    return rc


if __name__ == "__main__":
    sys.exit(main())
