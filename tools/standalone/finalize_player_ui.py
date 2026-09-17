"""Prepare layout sources and package checks before compiling the portable release."""
from pathlib import Path
import runpy
ROOT=Path(__file__).resolve().parents[2]
runpy.run_path(str(ROOT/'tools/standalone/layout_player_ui.py'))
p=ROOT/'portable_config/script-modules/player_ui_menu.lua';s=p.read_text(encoding='utf-8')
s=s.replace("    function M.wheel(delta,x,y)\n        for", "    function M.wheel(delta,x,y)\n        if not s.menu then return false end\n        for")
s=s.replace("    function M.hover(b)\n        local", "    function M.hover(b)\n        if not s.menu then close_timer();return end\n        local")
s=s.replace("        close_timer();s.menu=nil;", "        close_timer();M.boxes={};M.rows={};s.menu=nil;")
# Escape means back even if the pointer remains over the parent menu item.
s=s.replace("        close_timer()\n        if s.menu==kind", "        close_timer();M.hover_blocked=nil\n        if s.menu==kind")
s=s.replace("        if s.parent then s.menu=s.parent;", "        if s.parent then M.hover_blocked=s.menu;s.menu=s.parent;")
old="        local target=r and r.target\n"
new=old+"        if target~=M.hover_blocked then M.hover_blocked=nil end\n        if target and target==M.hover_blocked then close_timer();return end\n"
if new not in s:
    assert s.count(old)==1
    s=s.replace(old,new)
p.write_text(s,encoding='utf-8')
p=ROOT/'portable_config/scripts/player_ui.lua';s=p.read_text(encoding='utf-8')
old="    state.x=-1;state.y=-1;state.hover=nil;"
new="    menus.hover(nil);state.x=-1;state.y=-1;state.hover=nil;"
if new not in s:s=s.replace(old,new)
s=s.replace("function()state.menu=nil;state.hover=nil;hide()end", "function()menus.close();state.hover=nil;hide()end")
# ASS PlayRes is an integer even when DPI/layout calculations are fractional.
s=s.replace('ui.res_x=layout.w;ui.res_y=layout.h;',
    'ui.res_x=math.floor(layout.w+.5);ui.res_y=math.floor(layout.h+.5);')
# Append clipping after the reset tag; do not match an incorrectly escaped backslash.
a=s.index('local function line(s)');b=s.index('local function rect(',a)
s=s[:a]+r'''local function line(s)
    if clip_region then
        s=s:gsub('^(%{[^}]*)(%})',function(tags,ending)return tags..clip_region..ending end,1)
    end
    output[#output+1]=s
end
'''+s[b:]
old="    if ui.data=='' then ui:remove() else ui:update() end"
new="""    if ui.data=='' then
        ui:remove();state.overlay_ok=false;state.overlay_error=nil
    else
        local result,err=ui:update()
        state.overlay_ok=err==nil;state.overlay_error=err
        if err and err~=state.last_overlay_error then require('mp.msg').error('Player UI overlay: '..tostring(err)) end
        state.last_overlay_error=err
    end"""
if old in s:s=s.replace(old,new)
elif new not in s:raise RuntimeError('Overlay update context changed')
old="controls=buttons,scale=layout.scale,menu_boxes=boxes,"
new="controls=buttons,scale=layout.scale,hover=state.hover,mouse_x=state.x,mouse_y=state.y,overlay_ok=state.overlay_ok,overlay_error=state.overlay_error,menu_boxes=boxes,"
if old in s:s=s.replace(old,new)
elif new not in s:raise RuntimeError('Controller state context changed')
# Mouse-down can reach the script before a queued mouse-move notification.
old="    local e=event and event.event or 'press'\n"
new=old+"""    local px,py=mp.get_mouse_pos()
    if layout and core.finite(px) and core.finite(py) then
        state.x=px/layout.scale;state.y=py/layout.scale
    end
"""
if new not in s:
    if s.count(old)!=1:raise RuntimeError('Mouse event context changed')
    s=s.replace(old,new)
# Do not redefine the same input section on every pause, volume or OSD change.
old="    if state.menu then mp.add_forced_key_binding('ESC','player_ui-menu-escape',escape) else mp.remove_key_binding('player_ui-menu-escape') end"
new="""    local menu_open=state.menu~=nil
    if menu_open~=menu_escape_bound then
        menu_escape_bound=menu_open
        if menu_open then mp.add_forced_key_binding('ESC','player_ui-menu-escape',escape)
        else mp.remove_key_binding('player_ui-menu-escape') end
    end"""
if old in s:
    s=s.replace('sync_timers=function()', 'local menu_escape_bound=false\nsync_timers=function()',1)
    s=s.replace(old,new)
elif new not in s:raise RuntimeError('Menu key binding context changed')
p.write_text(s,encoding='utf-8')
p=ROOT/'tools/standalone/build.py';s=p.read_text(encoding='utf-8')
old="'portable_config/script-modules/player_ui_core.lua','portable_config/script-modules/player_ui_metrics.lua',"
new=old+"\n       'portable_config/script-modules/player_ui_menu.lua',"
if new not in s:
    assert old in s
    s=s.replace(old,new)
# A runtime seed and staged tests may contain resume records. They are not defaults.
old="    shutil.rmtree(ST/'portable_config/scripts',ignore_errors=True)"
new="    shutil.rmtree(ST/'portable_config/watch_later',ignore_errors=True)\n"+old
if new not in s:
    assert old in s
    s=s.replace(old,new)
old='    inspect_payload();DIST.mkdir(exist_ok=True)'
new="    shutil.rmtree(ST/'portable_config/watch_later',ignore_errors=True)\n"+old
if new not in s:
    assert old in s
    s=s.replace(old,new)
p.write_text(s,encoding='utf-8')
p=ROOT/'tools/standalone/publish.py';s=p.read_text(encoding='utf-8')
old="previous['tag_name']=='standalone-v1.0.1' and META['tag']=='standalone-v1.1.0'"
s=s.replace(old,"previous['tag_name']=='standalone-v1.1.0' and META['tag']=='standalone-v1.1.1'")
p.write_text(s,encoding='utf-8')
