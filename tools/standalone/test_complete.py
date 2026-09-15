"""Validate the exact unpacked full application without any prior player/.NET install."""
from pathlib import Path
import ctypes, json, os, subprocess, sys, time, uuid
APP=Path(sys.argv[1]).resolve();OUT=Path(sys.argv[2]).resolve();OUT.mkdir(parents=True,exist_ok=True)
ROOT=Path(__file__).resolve().parents[2]
results=[]
def record(name,fn):
    try:detail=fn() or {};results.append({'case':name,'passed':True,**detail})
    except Exception as e:results.append({'case':name,'passed':False,'error':repr(e)})
    print(json.dumps(results[-1],ensure_ascii=False),flush=True)
ENV=os.environ.copy();empty=OUT/'no-dotnet';empty.mkdir(exist_ok=True)
ENV.update({'DOTNET_ROOT':str(empty),'DOTNET_ROOT_X64':str(empty),'DOTNET_MULTILEVEL_LOOKUP':'0',
    'DOTNET_BUNDLE_EXTRACT_BASE_DIR':str(OUT/'bundles')})
for key in ('MPVNET_HOME','MPV_HOME','ANIMEJANAI_ROOT','ANIMEJANAI_DATA_DIR'):ENV.pop(key,None)
ENV['PATH']=str(APP)+os.pathsep+str(APP/'animejanai/inference')+os.pathsep+os.environ.get('SystemRoot',r'C:\Windows')+r'\System32'

def components():
    cp=subprocess.run([str(APP/'AnimeJaNaiUpdater.exe'),'--components','--json'],env=ENV,cwd=OUT,capture_output=True,timeout=40)
    (OUT/'components.log').write_bytes(cp.stdout+cp.stderr)
    assert cp.returncode==0,cp.stderr
    data=json.loads(cp.stdout)
    assert data['offline'] and len(data['packs'])>=7,data
    assert all(x['installed'] for x in data['packs']),data
    return {'packs':[x['name'] for x in data['packs']]}

def own_channel():
    cp=subprocess.run([str(APP/'AnimeJaNaiUpdater.exe'),'--check'],env=ENV,cwd=OUT,capture_output=True,timeout=30)
    assert cp.returncode==0 and b'sunuuc/AnimeJaNai-zh-CN/releases' in cp.stdout and b'the-database' not in cp.stdout
    return {'upstream_install_required':False}

sample=OUT/'blank.y4m';sample.write_bytes(b'YUV4MPEG2 W16 H16 F24:1 Ip A1:1 C420jpeg\n'+(b'FRAME\n'+bytes([100])*256+bytes([128])*128)*24*20)
def production_scripts():
    cp=subprocess.run([str(APP/'mpv.exe'),'--config-dir='+str(APP/'portable_config'),
        '--vo=null','--ao=null','--hwdec=no','--vf=','--idle=yes','--osc=no',
        '--scripts='+str(ROOT/'tools/standalone/full_smoke.lua'),str(sample)],env=ENV,cwd=OUT,capture_output=True,timeout=30)
    log=cp.stdout+cp.stderr;(OUT/'production-scripts.log').write_bytes(log)
    assert cp.returncode==0 and b'PASS empty-directory full install:' in log,log[-7000:]
    assert b'stack traceback' not in log.lower(),log[-7000:]
    return {'cpu_playback':True,'gpu_inference':False}

def frontend():
    pipe=r'\\.\pipe\ajn-full-'+uuid.uuid4().hex
    args=[str(APP/'mpvnet.exe'),'--config-dir='+str(APP/'portable_config'),'--vo=null','--ao=null',
        '--hwdec=no','--vf=','--idle=yes','--input-ipc-server='+pipe,'--log-file='+str(OUT/'frontend.mpv.log'),str(sample)]
    proc=subprocess.Popen(args,env=ENV,cwd=OUT,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    f=None
    try:
        end=time.monotonic()+35
        while time.monotonic()<end:
            assert proc.poll() is None,('Player exited',proc.returncode)
            try:f=open(pipe,'r+b',buffering=0);break
            except OSError:time.sleep(.15)
        assert f is not None,'No IPC from self-contained player'
        def get(name):
            f.write((json.dumps({'command':['get_property',name],'request_id':72})+'\n').encode())
            while True:
                d=json.loads(f.readline())
                if d.get('request_id')==72:
                    assert d.get('error')=='success',d
                    return d.get('data')
        time.sleep(1)
        assert get('vo-presented-frame-count')>0
        assert Path(get('path')).name==sample.name

        # The test environment deliberately points DOTNET_ROOT at an empty
        # directory and removes dotnet from PATH. Reaching a working IPC/video
        # loop therefore already proves the delivered executable can start
        # without an installed .NET runtime. Inspect loaded modules as an
        # additional guard against accidentally borrowing the runner's SDK.
        # .NET single-file native libraries are allowed to be bundle-loaded in
        # ways that are not always exposed as a separate coreclr.dll module, so
        # do not require coreclr.dll to appear in this diagnostic list.
        ps=Path(os.environ['SystemRoot'])/'System32/WindowsPowerShell/v1.0/powershell.exe'
        cp=subprocess.run([str(ps),'-NoProfile','-Command',f'(Get-Process -Id {proc.pid}).Modules.FileName | ConvertTo-Json -Compress'],capture_output=True,timeout=15)
        assert cp.returncode==0,cp.stderr
        raw=cp.stdout.decode('utf-8-sig').strip()
        parsed=json.loads(raw) if raw else []
        mods=[parsed] if isinstance(parsed,str) else (parsed or [])
        mods=[str(m) for m in mods]
        lower=[m.lower() for m in mods]
        forbidden=[m for m in mods if 'program files\\dotnet' in m.lower() or 'hostedtoolcache' in m.lower()]
        assert not forbidden,forbidden
        clrs=[m for m in mods if m.lower().endswith('coreclr.dll')]
        (OUT/'self-contained-modules.json').write_text(json.dumps({
            'modules':mods,'coreclr_modules':clrs,'forbidden_external_dotnet_modules':forbidden,
            'dotnet_root':ENV['DOTNET_ROOT'],'path':ENV['PATH']},indent=2),encoding='utf-8')
        return {'coreclr_modules':clrs,'external_dotnet_modules':0,
                'dotnet_root_forced_empty':True,'started_outside_install_directory':True}
    finally:
        if f:f.close()
        if proc.poll() is None:
            proc.terminate()
            try:proc.wait(5)
            except subprocess.TimeoutExpired:proc.kill();proc.wait(5)

def manager():
    proc=subprocess.Popen([str(APP/'AnimeJaNaiManager.exe')],env=ENV,cwd=OUT,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    try:
        time.sleep(5);assert proc.poll() is None,('Manager exited',proc.returncode)
        return {'launched':True,'external_dotnet_disabled':True}
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:proc.wait(5)
            except subprocess.TimeoutExpired:proc.kill();proc.wait(5)

record('offline-included-components',components)
record('own-update-channel',own_channel)
record('all-production-scripts-on-local-video',production_scripts)
record('self-contained-player',frontend)
record('self-contained-manager',manager)
(OUT/'results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
if not all(r['passed'] for r in results):raise SystemExit(1)
