"""Apply guarded source updates before compilation; publish the resulting sources."""
from pathlib import Path
import re
R=Path(__file__).resolve().parents[2]

def edit(name,old,new):
    p=R/name;s=p.read_text(encoding='utf-8-sig')
    if (new and new in s) or (not new and old not in s):return
    if s.count(old)!=1:raise RuntimeError(f'Patch context changed: {name}: {old[:70]}')
    p.write_text(s.replace(old,new),encoding='utf-8')

p='portable_config/scripts/player_ui.lua'
edit(p,"volume_step=5,font=", "volume_step=5,ui_scale=1.00,text_outline=1,font=")
edit(p,"options.read_options(o,'player_ui')", "options.read_options(o,'player_ui')\no.ui_scale=core.clamp(tonumber(o.ui_scale) or 1.00,.45,1.5)")
edit(p,"if bool('idle-active',true) then title='拖入视频或链接开始播放' end", "if bool('idle-active',true) then title='' end")
edit(p,"version='1.1.1'", "version='1.1.2'")
for name in ('pw,ph','w,h'):
    edit(p,f"core.layout({name},num('playlist-count',0),num('display-hidpi-scale',1))",
         f"core.layout({name},num('playlist-count',0),num('display-hidpi-scale',1),o.ui_scale)")
edit(p,'local function thumb(t,x)', "local function thumb(t,x)\n    if not core.local_media(mp.get_property('path',''),mp.get_property('stream-open-filename',''),bool('demuxer-via-network')) then hide_thumb();return end")
edit(p,'        thumb_timer=nil;state.thumb_time=t', "        thumb_timer=nil\n        if not core.local_media(mp.get_property('path',''),mp.get_property('stream-open-filename',''),bool('demuxer-via-network')) then hide_thumb();return end\n        state.thumb_time=t")
edit('portable_config/scripts/animejanai_slot.lua', "and mp.get_property_bool('seekable',false) then", "and mp.get_property_bool('seekable',false) and not mp.get_property_bool('demuxer-via-network',false) then")

p='portable_config/script-modules/player_ui_core.lua'
edit(p,'function M.layout(pw,ph,count,dpi)', 'function M.layout(pw,ph,count,dpi,ui_scale)')
# The layout must keep the ASS PlayRes at 1:1 with the window: resampling it is
# what made the text soft. Verify that contract instead of rewriting the body.
_core=(R/'portable_config/script-modules/player_ui_core.lua').read_text(encoding='utf-8-sig')
for _marker in ('local want=M.clamp(tonumber(ui_scale)','local w,h=pw,ph','return built or'):
    if _marker not in _core:raise RuntimeError('Player UI 1:1 layout contract missing: '+_marker)
for _bad in ('pw/scale','pw/920','ph/620'):
    if _bad in _core:raise RuntimeError('Player UI layout still resamples the ASS PlayRes: '+_bad)
edit(p,'return M\n', '''function M.local_media(path,opened,network)
    if network or type(path)~='string' or path=='' then return false end
    local function file_path(s)
        if not s or s=='' then return true end
        if s:match('^%a:[/\\\\]') then return true end
        if s:match('^%a[%w+.-]*:') or s:sub(1,2)=='//' or s:sub(1,2)=='\\\\\\\\' then return false end
        return true
    end
    return file_path(path) and file_path(opened)
end
return M
''')
p='portable_config/scripts/thumbfast.lua'
edit(p,'local function spawn(time)\n    if disabled then return end', '''local function local_file_only()
    local path=mp.get_property('path','')
    local opened=mp.get_property('stream-open-filename','')
    local function ordinary(s)
        if s=='' then return true end
        if s:match('^%a:[/\\\\]') then return true end
        return not s:match('^%a[%w+.-]*:') and s:sub(1,2)~='//' and s:sub(1,2)~='\\\\\\\\'
    end
    if path=='' or mp.get_property_bool('demuxer-via-network',false) or not ordinary(path) or not ordinary(opened) then return false end
    local file=mp.utils.file_info(path)
    return file and file.is_file or false
end
local function spawn(time)
    if disabled or not local_file_only() then return end''')
p=R/'portable_config/script-opts/thumbfast.conf';s=p.read_text(encoding='utf-8-sig')
p.write_text(re.sub(r'(?m)^network=.*$','network=no',s),encoding='utf-8')
p='src/player/src/MpvNet/Player.cs'
edit(p,'''        if ((DateTime.Now - LastLoad).TotalMilliseconds < 1000)
            append = true;

''','')
edit(p,"            if (file.Contains('|'))", "            if (!file.Contains(\"://\") && file.Contains('|'))")
edit(p,'            string ext = file.Ext();', '            string ext = file.Contains("://") ? "" : file.Ext();')
edit(p,'''        if (string.IsNullOrEmpty(GetPropertyString("path")))
            SetPropertyInt("playlist-pos", 0);''','''        // loadfile replace starts playback itself; never reopen while path is still initializing.''')
edit(p,'                    CommandV("loadfile", file, "append");',
     '                    CommandV("loadfile", file, i == 0 && GetPropertyInt("playlist-count") == 0 ? "append-play" : "append");')
# Startup argument normalization is maintained in ScopedCommandLine.cs.
# Do not replay an older text migration over the current parser.
p=R/'tools/standalone/build.py';s=p.read_text(encoding='utf-8-sig')
old="    run(sys.executable,R/'tests/test_player_ui_windows.py',R/'clean-install',E/'fresh-install/player_ui')"
new=old+"\n    run(sys.executable,R/'tests/test_network_playback.py',R/'clean-install',E/'fresh-install/network')"
if new not in s:
    assert s.count(old)==1;s=s.replace(old,new)
s=s.replace("'portable_config/scripts/player_ui.lua','portable_config/scripts/player_ui_danmaku.lua'", "'portable_config/scripts/network_playback.lua','portable_config/scripts/player_ui.lua','portable_config/scripts/player_ui_danmaku.lua'")
p.write_text(s,encoding='utf-8')
p=R/'tools/standalone/publish.py';s=p.read_text(encoding='utf-8-sig')
s=s.replace("previous['tag_name']=='standalone-v1.1.0' and META['tag']=='standalone-v1.1.1'", "previous['tag_name']=='standalone-v1.1.1' and META['tag']=='standalone-v1.1.2'")
needle="head=api(f'repos/{REPO}/git/ref/heads/main')['object']['sha']"
new="""for path in (E/'network/results.json',E/'fresh-install/network/results.json'):
    result=json.loads(path.read_text());assert result and all(t['passed'] for t in result),path
"""+needle
if new not in s:
    assert s.count(needle)==1;s=s.replace(needle,new)
p.write_text(s,encoding='utf-8')
for name in ('tests/test_player_ui_runtime.lua','tests/test_player_ui_logic.lua'):
    p=R/name;s=p.read_text(encoding='utf-8-sig').replace("'1.1.1'","'1.1.2'")
    s=s.replace('drawer.y1==720 and drawer.x1==1280','math.abs(drawer.y1*ui().scale-720)<1 and math.abs(drawer.x1*ui().scale-1280)<1')
    s=s.replace('pos.x=(b.x0+b.x1)/2;pos.y=(b.y0+b.y1)/2','pos.x=(b.x0+b.x1)*ui().scale/2;pos.y=(b.y0+b.y1)*ui().scale/2')
    p.write_text(s,encoding='utf-8')
p=R/'src/player/tests/ScopedCommandLine/Program.cs';s=p.read_text(encoding='utf-8-sig')
if 'playlist is an option value' not in s:
    marker='if(args.Length==2'
    addition='Check(ScopedCommandLine.Parse(new[]{"--playlist","episodes.m3u","--playlist-start=1"}).Entries.Count==0,"playlist is an option value");\n'
    addition+='Check(ScopedCommandLine.Parse(new[]{"--http-header-fields=Authorization: LocalTest sample","https://example.invalid/file"}).NeedsDedicatedProcess,"caller authentication preserved");\n'
    assert s.count(marker)==1;s=s.replace(marker,addition+marker)
p.write_text(s,encoding='utf-8')
p=R/'tools/standalone/publish.py';s=p.read_text(encoding='utf-8')
needle="paths += [p for p in (R/'portable_config').rglob('*') if p.is_file()]"
replacement=needle+"\npaths += [p for p in (R/'tests').rglob('*') if p.is_file() and p.suffix in ('.py','.lua')]"
if replacement not in s:
    assert needle in s;s=s.replace(needle,replacement)
p.write_text(s,encoding='utf-8')
print('Playback source updates ready')
