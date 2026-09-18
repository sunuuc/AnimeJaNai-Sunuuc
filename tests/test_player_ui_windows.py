"""Exercise packaged controls with real mpv input events and D3D11 WARP."""
from pathlib import Path
import json,subprocess,sys,wave
ROOT=Path(__file__).resolve().parents[1]
APP=Path(sys.argv[1]).resolve();OUT=Path(sys.argv[2]).resolve();OUT.mkdir(parents=True,exist_ok=True)
results=[]
def run(name,args,marker,timeout=60):
    try:
        p=subprocess.run([str(APP/'mpv.exe'),*args],capture_output=True,timeout=timeout)
        log=p.stdout+p.stderr
        passed=p.returncode==0 and marker in log and b'stack traceback' not in log.lower()
        result={'case':name,'passed':passed,'exit_code':p.returncode}
    except subprocess.TimeoutExpired as e:
        log=(e.stdout or b'')+(e.stderr or b'');result={'case':name,'passed':False,'error':'timeout'}
    (OUT/(name+'.log')).write_bytes(log);results.append(result)
    if not result['passed']:print(log[-8000:].decode('utf-8',errors='replace'))
base=['--load-scripts=no','--osc=no','--ao=null','--hwdec=no','--vf=','--idle=yes']
run('player_ui-logic',['--no-config',*base,'--vo=null','--script='+str(ROOT/'tests/test_player_ui_logic.lua'),
    '--script-opts=playeruiroot='+str(APP)],b'PASS Player UI logic:')
header=b'YUV4MPEG2 W320 H180 F24:1 Ip A1:1 C420jpeg\n'
for name,value in [('first.y4m',65),('second.y4m',85)]:
    frame=b'FRAME\n'+bytes([value])*(320*180)+bytes([128])*(320*180//2)
    with (OUT/name).open('wb') as f:
        f.write(header)
        for _ in range(24*15):f.write(frame)
with wave.open(str(OUT/'audio.wav'),'wb') as f:
    f.setnchannels(1);f.setsampwidth(2);f.setframerate(8000);f.writeframes(b'\0\0'*8000*15)
(OUT/'subtitle.srt').write_text('1\n00:00:00,000 --> 00:00:12,000\n中文字幕测试\n',encoding='utf-8')
(OUT/'comments.xml').write_text('<i><d p="0,5,26,16777215">弹幕与字幕独立显示</d><d p="0,1,26,16777215">滚动弹幕</d><d p="0,4,26,16777215">固定弹幕</d></i>',encoding='utf-8')
scripts=[APP/'portable_config/scripts'/x for x in ['player_ui.lua','player_ui_danmaku.lua','animejanaistats.lua','animejanai_slot.lua']]
scripts.append(ROOT/'tests/test_player_ui_runtime.lua')
for p in scripts:assert p.is_file(),p
assert not (APP/'portable_config/scripts/modernx.lua').exists(),'Two control bars packaged'
# Exercise the delivered config directory; --no-config also disables mpv's ~~
# configuration-root lookup and is deliberately limited to the pure mock suite.
run('player_ui-windows-ui',base+['--vo=gpu','--gpu-api=d3d11','--gpu-context=d3d11','--d3d11-warp=yes',
    '--geometry=1280x720','--border=no','--pause=yes','--keep-open=yes',
    '--config-dir='+str(APP/'portable_config'),'--input-conf='+str(APP/'portable_config/input.conf'),
    '--scripts='+';'.join(map(str,scripts)),'--script-opts=playeruiout='+str(OUT),
    '--force-media-title=播放器界面测试','--sub-auto=no','--sub-file='+str(OUT/'subtitle.srt'),
    '--audio-file='+str(OUT/'audio.wav'),str(OUT/'first.y4m')],b'PASS Player UI Windows UI:')
(OUT/'results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
for p in OUT.glob('*.y4m'):p.unlink()
(OUT/'audio.wav').unlink(missing_ok=True)
print(json.dumps(results,ensure_ascii=False,indent=2))
if not all(r['passed'] for r in results):raise SystemExit(1)
