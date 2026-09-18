"""Inline Player UI Lua modules into production scripts before packaging.

LuaJIT's loadfile/dofile path handling on Windows can fail when the portable
folder contains non-ASCII characters. mpv itself can load the top-level script,
so embedding the small local modules removes that second filesystem open while
keeping the standalone module files for source-level tests.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODULES = ROOT / "portable_config" / "script-modules"
SCRIPTS = ROOT / "portable_config" / "scripts"


def wrapped(module_name: str) -> str:
    body = (MODULES / module_name).read_text(encoding="utf-8-sig").rstrip()
    return "(function()\n-- inlined module: " + module_name + "\n" + body + "\nend)()"


def replace_once(path: Path, needle: str, replacement: str) -> None:
    text = path.read_text(encoding="utf-8-sig")
    marker = "-- inlined module: "
    if needle not in text:
        if marker in text:
            return
        raise RuntimeError(f"Player UI module inclusion context changed: {path.name}: {needle}")
    if text.count(needle) != 1:
        raise RuntimeError(f"Ambiguous Player UI module inclusion: {path.name}: {needle}")
    path.write_text(text.replace(needle, replacement), encoding="utf-8")


player_ui = SCRIPTS / "player_ui.lua"
replace_once(
    player_ui,
    "dofile(mp.command_native({'expand-path','~~/script-modules/player_ui_core.lua'}))",
    wrapped("player_ui_core.lua"),
)
replace_once(
    player_ui,
    "dofile(mp.command_native({'expand-path','~~/script-modules/player_ui_metrics.lua'}))",
    wrapped("player_ui_metrics.lua"),
)
replace_once(
    player_ui,
    "dofile(mp.command_native({'expand-path','~~/script-modules/player_ui_menu.lua'}))",
    wrapped("player_ui_menu.lua"),
)

replace_once(
    SCRIPTS / "player_ui_danmaku.lua",
    "dofile(mp.command_native({'expand-path','~~/script-modules/player_ui_core.lua'}))",
    wrapped("player_ui_core.lua"),
)

for path in (player_ui, SCRIPTS / "player_ui_danmaku.lua"):
    text = path.read_text(encoding="utf-8")
    if "dofile(mp.command_native({'expand-path','~~/script-modules/" in text:
        raise RuntimeError(f"Runtime module loader remains in {path.name}")

print("Player UI runtime modules inlined for Unicode-safe portable paths")
