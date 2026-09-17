"""Migrate portable defaults and build inputs to the Player UI controller."""
from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[2]
def write(path,text):path.write_text(text,encoding='utf-8')
for name in ('input.conf','input-animejanai.conf'):
    p=ROOT/'portable_config'/name;s=p.read_text(encoding='utf-8-sig')
    s,n=re.subn(r'(?mi)^Up\s+.*$', 'Up          add volume 5                 #menu: 音量 > 增大',s)
    if n!=1:raise RuntimeError('Expected one Up binding in '+name)
    s,n=re.subn(r'(?mi)^Down\s+.*$', 'Down        add volume -5                #menu: 音量 > 减小',s)
    if n!=1:raise RuntimeError('Expected one Down binding in '+name)
    s=re.sub(r'(?mi)^ESC\s+.*$', 'ESC         set fullscreen no',s)
    if not re.search(r'(?mi)^ESC\s+',s):s+='\nESC         set fullscreen no\n'
    s=s.replace('osc/visibility','player_ui/visibility').replace('modernx/visibility','player_ui/visibility')
    s=s.replace('apply-profile upscale-on; script-message aji-slot','script-message aji-slot')
    write(p,s)
p=ROOT/'portable_config/mpv.conf';s=p.read_text(encoding='utf-8-sig')
write(p,re.sub(r'^#.*\n','# AnimeJaNai 播放配置\n',s,count=1))
p=ROOT/'portable_config/script-opts/thumbfast.conf';s=p.read_text(encoding='utf-8-sig')
s=re.sub(r'(?m)^spawn_first=.*$','spawn_first=no',s)
s=re.sub(r'(?m)^quit_after_inactivity=.*$','quit_after_inactivity=15',s)
if not re.search(r'(?m)^quit_after_inactivity=',s):s+='\nquit_after_inactivity=15\n'
write(p,s)
p=ROOT/'portable_config/script-modules/player_ui_core.lua';s=p.read_text(encoding='utf-8')
write(p,s.replace('scale=math.min(scale,pw/860)','scale=math.min(scale,pw/860,ph/360)'))
p=ROOT/'portable_config/scripts/player_ui_danmaku.lua';s=p.read_text(encoding='utf-8')
s=s.replace('if ok and result.status==0','if ok and result and result.status==0').replace('elseif not ok or result.status~=0','elseif not ok or not result or result.status~=0')
old="options.read_options(o,'player_ui_danmaku')"
new=old+"\no.opacity=core.clamp(tonumber(o.opacity) or 85,10,100)\no.area=core.clamp(tonumber(o.area) or 50,25,70)\no.font_size=core.clamp(tonumber(o.font_size) or 26,16,40)"
if new not in s:s=s.replace(old,new)
write(p,s)
p=ROOT/'tools/standalone/build.py';s=p.read_text(encoding='utf-8')
begin="    p=ST/'portable_config/scripts/modernx.lua';s=p.read_text(encoding='utf-8')"
end="    p=ST/'portable_config/scripts/thumbfast.lua';s=p.read_text(encoding='utf-8')"
replacement="    (ST/'portable_config/scripts/modernx.lua').unlink(missing_ok=True)\n    (ST/'portable_config/script-opts/modernx.conf').unlink(missing_ok=True)\n"
if begin in s:
    a=s.index(begin);b=s.index(end,a);s=s[:a]+replacement+s[b:]
elif replacement not in s:raise RuntimeError('Controller staging context changed')
s=s.replace("'portable_config/scripts/modernx.lua','portable_config/scripts/thumbfast.lua',", "'portable_config/scripts/player_ui.lua','portable_config/scripts/player_ui_danmaku.lua','portable_config/scripts/thumbfast.lua',\n       'portable_config/script-modules/player_ui_core.lua','portable_config/script-modules/player_ui_metrics.lua',")
old="    run(sys.executable,H/'test_complete.py',R/'clean-install',E/'fresh-install')"
new=old+"\n    run(sys.executable,R/'tests/test_player_ui_windows.py',R/'clean-install',E/'fresh-install/player_ui')"
if new not in s:
    if s.count(old)!=1:raise RuntimeError('Fresh-install test hook changed')
    s=s.replace(old,new)
write(p,s)
for name in ('portable_config/scripts/modernx.lua','portable_config/script-opts/modernx.conf'):(ROOT/name).unlink(missing_ok=True)
print('Player UI build inputs prepared')
