"""Prepare layout sources and package checks before compiling the portable release."""
from pathlib import Path
import runpy
ROOT=Path(__file__).resolve().parents[2]
runpy.run_path(str(ROOT/'tools/standalone/layout_player_ui.py'))
p=ROOT/'portable_config/script-modules/player_ui_menu.lua';s=p.read_text(encoding='utf-8')
s=s.replace("    function M.wheel(delta,x,y)\n        for", "    function M.wheel(delta,x,y)\n        if not s.menu then return false end\n        for")
s=s.replace("    function M.hover(b)\n        local", "    function M.hover(b)\n        if not s.menu then close_timer();return end\n        local")
s=s.replace("        close_timer();s.menu=nil;", "        close_timer();M.boxes={};M.rows={};s.menu=nil;")
p.write_text(s,encoding='utf-8')
p=ROOT/'portable_config/scripts/player_ui.lua';s=p.read_text(encoding='utf-8')
s=s.replace("    state.x=-1;state.y=-1;state.hover=nil;", "    menus.hover(nil);state.x=-1;state.y=-1;state.hover=nil;")
s=s.replace("function()state.menu=nil;state.hover=nil;hide()end", "function()menus.close();state.hover=nil;hide()end")
p.write_text(s,encoding='utf-8')
p=ROOT/'tools/standalone/build.py';s=p.read_text(encoding='utf-8')
old="'portable_config/script-modules/player_ui_core.lua','portable_config/script-modules/player_ui_metrics.lua',"
new=old+"\n       'portable_config/script-modules/player_ui_menu.lua',"
if new not in s:
    assert old in s
    s=s.replace(old,new)
p.write_text(s,encoding='utf-8')
p=ROOT/'tools/standalone/publish.py';s=p.read_text(encoding='utf-8')
old="previous['tag_name']=='standalone-v1.0.1' and META['tag']=='standalone-v1.1.0'"
s=s.replace(old,"previous['tag_name']=='standalone-v1.1.0' and META['tag']=='standalone-v1.1.1'")
p.write_text(s,encoding='utf-8')
