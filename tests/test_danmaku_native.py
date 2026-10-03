"""Exercise upstream conversion and actual mpv subtitle selection, without GUI/network video."""
from pathlib import Path
import json
import os
import re
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT=Path(__file__).resolve().parents[1]
MPV=Path(os.environ.get('ANIMEJANAI_MPV_EXE',r'D:\Apps\mpv-AnimeJaNai\mpv.exe'))
FACTORY=Path(os.environ.get('DANMAKU_FACTORY',ROOT/'_probe/upstream-danmaku/cli/DanmakuFactory.exe'))
SCRIPT=Path(os.environ.get('ANIMEJANAI_DANMAKU_SCRIPT',ROOT/'portable_config/scripts/player_ui_danmaku.lua'))
UI_SCRIPT=os.environ.get('ANIMEJANAI_PLAYER_UI_SCRIPT')

class NativeDanmaku(unittest.TestCase):
    def test_playback_speed_and_viewport(self):
        with tempfile.TemporaryDirectory(prefix='danmaku-playback-') as tmp:
            folder=Path(tmp);xml=folder/'comments.xml';ass=folder/'comments.ass'
            xml.write_text('<i><d p="0,1,25,16777215">scroll</d>'
                '<d p="8,5,25,16777215">fixed</d></i>',encoding='utf-8')
            def generate(speed,time=0,timeline='0:1'):
                args=[str(FACTORY),'-i',str(xml),'-o',str(ass),'--force','--ignore-warnings',
                    '--scrolltime','12','--fixtime','5','--playback-speed',str(speed),
                    '--playback-time',str(time),'--playback-timeline',timeline]
                done=subprocess.run(args,capture_output=True,timeout=10)
                self.assertEqual(done.returncode,0,done.stderr)
                text=ass.read_text(encoding='utf-8-sig')
                lines=[line.split(',',9) for line in text.splitlines() if line.startswith('Dialogue:')]
                return text,lines
            def seconds(value):
                h,m,s=value.split(':');return int(h)*3600+int(m)*60+float(s)
            def x_at(line,time):
                start,end=seconds(line[1]),seconds(line[2])
                x0,y0,x1,y1=map(int,re.search(r'\\move\(([^)]+)\)',line[9])[1].split(','))
                return x0+(x1-x0)*(time-start)/(end-start)
            for speed in (.5,1,2,3):
                _,lines=generate(speed,timeline=f'0:{speed}')
                self.assertAlmostEqual((seconds(lines[0][2])-seconds(lines[0][1]))/speed,12,places=2)
                self.assertAlmostEqual((seconds(lines[1][2])-seconds(lines[1][1]))/speed,5,places=2)
            _,before=generate(1)
            _,after=generate(2,5,'0:1;5:2')
            self.assertAlmostEqual(x_at(before[0],5),x_at(after[0],5),delta=1)
            self.assertAlmostEqual(x_at(before[0],6),x_at(after[0],7),delta=1)
            _,again=generate(.5,9,'0:1;5:2;9:0.5')
            self.assertAlmostEqual(x_at(after[0],9),x_at(again[0],9),delta=1)
            self.assertAlmostEqual(x_at(after[0],11),x_at(again[0],9.5),delta=1)
            text,lines=generate(1)
            self.assertIn('PlayResY: 1080',text)
            self.assertIn('RenderInMargins: yes',text)
            self.assertIn('\\pos(960,0)',lines[1][9])

    def test_type_and_word_filters(self):
        with tempfile.TemporaryDirectory(prefix='danmaku-filters-') as tmp:
            folder=Path(tmp);xml=folder/'comments.xml';ass=folder/'comments.ass'
            xml.write_text('<i><d p="0,1,25,16777215,0,0,0,0">white scroll</d>'
                '<d p="1,6,25,16777215,0,0,0,0">white reverse</d><d p="2,5,25,16777215,0,0,0,0">white top</d>'
                '<d p="3,4,25,16777215,0,0,0,0">white bottom</d><d p="4,1,25,255,0,0,0,0">colored 中文</d></i>',encoding='utf-8')
            words=folder/'words.txt';words.write_text('中文\n',encoding='utf-8')
            for modes,flags,expected in [('TOP-BOTTOM',[],3),('R2L-L2R',[],2),('COLOR',[],4),
                ('null',['--blacklist',str(words)],4)]:
                done=subprocess.run([str(FACTORY),'-i',str(xml),'-o',str(ass),'--force','--ignore-warnings',
                    '--fontsize','38','--scrolltime','6','--fixtime','2.5','--displayarea','.25',
                    '--scrollarea','1','--opacity','204','--blockmode',modes,*flags],
                    capture_output=True,timeout=10)
                self.assertEqual(done.returncode,0,done.stderr)
                text=ass.read_text(encoding='utf-8-sig')
                self.assertEqual(text.count('\nDialogue:'),expected,modes)

    def test_native_track_lifecycle(self):
        self.check_native_track_lifecycle(True)

    def test_native_track_without_primary_subtitle(self):
        self.check_native_track_lifecycle(False)

    def check_native_track_lifecycle(self,primary):
        with tempfile.TemporaryDirectory(prefix='danmaku-native-') as tmp:
            app=Path(tmp);config=app/'portable_config';config.mkdir()
            converter=app/'animejanai/danmaku';converter.mkdir(parents=True)
            shutil.copy2(FACTORY,converter/'DanmakuFactory.exe')
            clip=app/'fixture.y4m'
            frame=b'FRAME\n'+b'\x60'*(160*90)+b'\x80'*(160*90//2)
            clip.write_bytes(b'YUV4MPEG2 W160 H90 F24:1 Ip A1:1 C420jpeg\n'+frame*(24*60))
            xml=app/'fixture.xml'
            xml.write_text('<i><d p="0,1,25,16777215">English &amp; 中文</d>'
                '<d p="1,5,25,65280">TOP</d><d p="2,4,25,255">BOTTOM</d>'
                '<d p="3,6,25,16711680">LEFT TO RIGHT</d></i>',encoding='utf-8')
            sub=app/'primary.srt';sub.write_text('1\n00:00:00,000 --> 00:00:20,000\nPrimary subtitle\n')
            driver=app/'driver.lua';result=app/'result.json'
            driver.write_text('''local mp=require 'mp'
local utils=require 'mp.utils'
local started=mp.get_time()
local stage=0
local records={}
local function record(name,d)
 records[#records+1]={name=name,state=d,sid=mp.get_property_native('sid'),
  secondary=mp.get_property_native('secondary-sid'),style=mp.get_property('secondary-sub-ass-override'),
  visible=mp.get_property_bool('secondary-sub-visibility'),time=mp.get_property_number('time-pos'),
  ui=mp.get_property_native('user-data/player_ui/ui')}
end
mp.add_periodic_timer(.05,function()
 local d=mp.get_property_native('user-data/player_ui/danmaku',{})
 if stage==0 and d.track then
  record('loaded',d);mp.commandv('script-message','player_ui-danmaku-toggle');stage=1
 elseif stage==1 and not d.enabled then
  record('hidden',d);mp.commandv('script-message','player_ui-danmaku-toggle');mp.commandv('seek',10,'absolute');stage=2
 elseif stage==2 and d.enabled and (mp.get_property_number('time-pos',0)>9) then
  record('seek',d)
  mp.commandv('script-message','player_ui-danmaku-setting','fontsize','50')
  mp.commandv('script-message','player_ui-danmaku-setting','speed','2')
  mp.commandv('script-message','player_ui-danmaku-setting','area','25')
  mp.commandv('script-message','player_ui-danmaku-setting','opacity-percent','80')
  mp.commandv('script-message','player_ui-menu','danmaku-settings')
  mp.commandv('script-message','player_ui-danmaku-save-words','TOP');stage=3
 elseif stage==3 and d.track and not d.render_pending and d.settings.fontsize==50 then
  mp.commandv('script-message','player_ui-menu','danmaku-settings');stage=3.5
 elseif stage==3.5 then
  record('settings',d);mp.commandv('script-message','player_ui-danmaku-clear');stage=4
 elseif stage==4 and not d.loaded then
  record('clear',d);stage=5
  local f=assert(io.open(RESULT,'wb'));f:write(utils.format_json(records));f:close();mp.commandv('quit',0)
 elseif mp.get_time()-started>40 then mp.commandv('quit',2) end
end)
'''.replace('RESULT',json.dumps(result.as_posix())),encoding='utf-8')
            env=os.environ.copy();env['LOCALAPPDATA']=str(app);env['TEMP']=str(app)
            startupinfo=None
            if os.name=='nt':
                startupinfo=subprocess.STARTUPINFO();startupinfo.dwFlags|=subprocess.STARTF_USESHOWWINDOW
                startupinfo.wShowWindow=subprocess.SW_HIDE
            completed=subprocess.run([str(MPV),
                *(['--process-instance=multi'] if MPV.name.lower()=='AnimeVE.exe' else []),'--load-scripts=no',f'--config-dir={config}',
                '--vo=null','--ao=null','--hwdec=no',
                *(['--sid=1','--sub-file='+str(sub)] if primary else ['--sid=auto']),
                '--script='+str(SCRIPT),*(['--script='+UI_SCRIPT] if UI_SCRIPT else []),'--script='+str(driver),
                '--script-opts=player_ui_danmaku-autoload_danmaku=no',str(clip)],
                env=env,capture_output=True,text=True,encoding='utf-8',errors='replace',startupinfo=startupinfo,timeout=120)
            self.assertEqual(completed.returncode,0,completed.stdout+completed.stderr)
            self.assertTrue(result.exists(),completed.stdout+completed.stderr)
            records=json.loads(result.read_text());self.assertEqual(len(records),5)
            loaded,hidden,seek,settings,clear=records
            if UI_SCRIPT:
                # vo=null has no OSD surface. Menu layout is covered by the fake-mp suite.
                self.assertNotIn('[player_ui] Lua error',completed.stdout+completed.stderr)
                self.assertNotIn('Error loading',completed.stdout+completed.stderr)
            if os.environ.get('ANIMEJANAI_TEST_EVIDENCE'):
                evidence=Path(os.environ['ANIMEJANAI_TEST_EVIDENCE']);evidence.mkdir(parents=True,exist_ok=True)
                (evidence/('with-primary.json' if primary else 'without-primary.json')).write_text(
                    json.dumps(records,ensure_ascii=False,indent=2),encoding='utf-8')
            self.assertEqual(loaded['sid'],1 if primary else False)
            self.assertEqual(loaded['secondary'],loaded['state']['track'])
            self.assertEqual(loaded['style'],'no')
            self.assertEqual(loaded['state']['count'],4)
            self.assertFalse(hidden['visible']);self.assertEqual(hidden['sid'],1 if primary else False)
            self.assertEqual(seek['secondary'],loaded['secondary']);self.assertEqual(seek['sid'],1 if primary else False)
            self.assertEqual(settings['state']['settings']['fontsize'],50)
            self.assertEqual(settings['state']['count'],3)
            self.assertEqual(settings['state']['settings']['scrolltime'],6)
            self.assertEqual(settings['state']['settings']['fixtime'],2.5)
            self.assertEqual(settings['state']['settings']['displayArea'],.25)
            self.assertEqual(settings['state']['settings']['scrollArea'],1)
            self.assertEqual(settings['state']['settings']['opacity'],204)
            self.assertEqual(settings['sid'],1 if primary else False)
            self.assertEqual(clear['secondary'],False)
            self.assertEqual(clear['sid'],1 if primary else False)
            self.assertNotIn('render_fps',loaded['state'])

    def test_upstream_dense_conversion_and_animation(self):
        with tempfile.TemporaryDirectory(prefix='danmaku-factory-') as tmp:
            folder=Path(tmp);xml=folder/'中文 comments.xml';ass=folder/'result.ass'
            xml.write_text('<i>'+''.join(f'<d p="{i/8:.3f},1,25,16777215">Comment {i} 中文</d>'
                for i in range(10000))+'</i>',encoding='utf-8')
            start=time.perf_counter()
            done=subprocess.run([str(FACTORY),'-i',str(xml),'-o',str(ass),'--force','--ignore-warnings'],
                capture_output=True,timeout=30)
            self.assertEqual(done.returncode,0,done.stderr)
            text=ass.read_text(encoding='utf-8-sig')
            self.assertIn('\\move(',text);self.assertEqual(text.count('\nDialogue:'),10000)
            self.assertIn('PlayResX: 1920',text);self.assertIn('PlayResY: 1080',text)
            print(f'DanmakuFactory 10000 comments: {time.perf_counter()-start:.3f}s')

if __name__=='__main__':unittest.main()
