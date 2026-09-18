"""Full portable builder. Bootstrap once; subsequent runtime inputs use our release.
Commands: prepare / stage / package. Publishing is implemented in publish.py.
No command reads or modifies a user's installation.
"""
from pathlib import Path, PurePosixPath
import configparser, hashlib, json, os, re, shutil, subprocess, sys, time, urllib.request, zipfile
R=Path.cwd(); H=R/'tools/standalone'; ST=R/'stage'; DIST=R/'dist'; E=R/'complete-evidence'
META=json.loads((R/'release.json').read_text(encoding='utf-8'))
LOCK=json.loads((H/'dependencies.json').read_text(encoding='utf-8'))
REPO='sunuuc/AnimeJaNai-zh-CN'
from gpu_target import TARGET, prune, validate as validate_gpu_target
FONTS={'.ttf','.otf','.ttc','.woff','.woff2','.fon','.fnt'}
SEVEN=shutil.which('7z') or r'C:\Program Files\7-Zip\7z.exe'

def sha(p):
    with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def dump(p,obj):
    p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(obj,ensure_ascii=False,indent=2),encoding='utf-8')
def run(*args,**kwargs):return subprocess.run(list(map(str,args)),check=True,**kwargs)
def download(item):
    dest=R/'downloads'/item['name'];dest.parent.mkdir(exist_ok=True)
    if dest.exists() and sha(dest)==item['sha256']:return dest
    url=f'https://github.com/{item["repo"]}/releases/download/{item["tag"]}/{item["name"]}'
    for attempt in range(3):
        try:
            req=urllib.request.Request(url,headers={'User-Agent':'AnimeJaNai-zh-CN-full-build'})
            with urllib.request.urlopen(req,timeout=90) as src, dest.open('wb') as out:shutil.copyfileobj(src,out,1024*1024)
            if sha(dest)!=item['sha256']:raise RuntimeError('Download hash mismatch: '+item['name'])
            print('VERIFIED INPUT',item['name'],dest.stat().st_size,flush=True);return dest
        except Exception:
            dest.unlink(missing_ok=True)
            if attempt==2:raise
            time.sleep(2*(attempt+1))
def valid_path(name):
    p=PurePosixPath(name.replace('\\','/'))
    if p.is_absolute() or '..' in p.parts or ':' in name:raise RuntimeError('Unsafe archive path: '+name)
def extract(archive,dest):
    dest.mkdir(parents=True,exist_ok=True)
    if zipfile.is_zipfile(archive):
        with zipfile.ZipFile(archive) as z:
            for i in z.infolist():valid_path(i.filename)
            z.extractall(dest)
    else:
        listing=subprocess.check_output([SEVEN,'l','-slt','-sccUTF-8',str(archive)]).decode('utf-8').replace('\r\n','\n')
        entries=listing.split('----------\n',1)[-1]
        for name in re.findall(r'^Path = (.+)$',entries,re.M):valid_path(name)
        if 'Symbolic Link = ' in entries or 'Hard Link = ' in entries:raise RuntimeError('Links in archive')
        run(SEVEN,'x','-y','-bd',f'-o{dest}',archive,stdout=subprocess.DEVNULL)
def app_root(p):
    roots=[q.parent for q in p.rglob('mpvnet.exe')]
    if len(roots)!=1:raise RuntimeError('Ambiguous application root: '+str(roots))
    return roots[0]
def cp(src,dst):
    if src.is_dir():shutil.copytree(src,dst,dirs_exist_ok=True)
    else:dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst)
def replace_once(p,old,new):
    s=p.read_text(encoding='utf-8-sig')
    if new in s:return
    if s.count(old)!=1:raise RuntimeError('Source patch context mismatch: '+str(p)+' '+old[:70])
    p.write_text(s.replace(old,new),encoding='utf-8')

def prepare():
    E.mkdir(exist_ok=True)
    if not (R/'src/player').exists():
        srczip=download(LOCK['ui_source']);extract(srczip,R/'source-bootstrap')
        for name in ('player','manager'):cp(R/'source-bootstrap'/name,R/'src'/name)
        shutil.rmtree(R/'source-bootstrap');srczip.unlink()
        for p in (R/'src').rglob('*'):
            if p.is_file() and p.suffix.lower() in FONTS:p.unlink()
    manager=R/'src/manager/AnimeJaNaiConfEditor'
    p=manager/'Views/MainWindow.axaml'
    replace_once(p,'<CheckBox Grid.Column="0" IsChecked="{Binding Selected}" VerticalAlignment="Center" Margin="0,0,12,0" />',
        '<CheckBox Grid.Column="0" IsChecked="{Binding Selected}" IsEnabled="False" VerticalAlignment="Center" Margin="0,0,12,0" />')
    replace_once(p,'<Button Content="{local:Text Key=s85045ccc056780a7}" Command="{Binding ComponentManager.Apply}" IsEnabled="{Binding ComponentManager.NotBusy}" Classes="active" />',
        '<TextBlock Text="{local:Text Key=standaloneComponentsNote}" TextWrapping="Wrap" MaxWidth="600" />')
    for p in [manager/'LanguageStrings.json',R/'src/player/src/MpvNet/LanguageStrings.json']:
        data=json.loads(p.read_text(encoding='utf-8'))
        text='Full portable edition: components are bundled. Get complete updates from this project\'s release page.'
        data['keys']['standaloneComponentsNote']=text
        data['translations'][text]='完整便携版已内置组件，无需单独安装或删除；更新请从本项目发布页下载完整程序。'
        dump(p,data)
    for name in ('player','manager'):cp(R/'src'/name,R/name)
    for name in ('Manager','Player'):
        dest=R/'tests-generated'/(name.lower()+'-tests');dest.mkdir(parents=True,exist_ok=True)
        for ext in ('cs','csproj'):cp(R/f'tools/language-r3/{name}Tests.{ext}',dest/f'{name}Tests.{ext}')
    (R/'language-evidence').mkdir(exist_ok=True)
    dump(E/'source-inputs.json',{'ui_bootstrap':LOCK['ui_source'],'workflow_commit':os.environ.get('GITHUB_SHA'),
       'source_files':{p.relative_to(R/'src').as_posix():sha(p) for p in (R/'src').rglob('*') if p.is_file()}})

def stage():
    if ST.exists():shutil.rmtree(ST)
    seed=LOCK.get('runtime_seed')
    if seed:
        for item in seed['assets']:download(item)
        extract(R/'downloads'/seed['assets'][0]['name'],R/'seed-unpack')
        cp(app_root(R/'seed-unpack'),ST);shutil.rmtree(R/'seed-unpack')
        records=json.loads((ST/'build-info/standalone/components.json').read_text(encoding='utf-8'))
    else:
        base=download(LOCK['bootstrap_core']);extract(base,R/'base-unpack')
        cp(app_root(R/'base-unpack'),ST);shutil.rmtree(R/'base-unpack');base.unlink()
        native=download(LOCK['native_and_ui_resources']);extract(native,ST);native.unlink()
        records=[]
        for item in LOCK['components']:
            archive=download(item);temp=R/'component-unpack';extract(archive,temp)
            files=[]
            for p in temp.rglob('*'):
                if not p.is_file():continue
                rel=p.relative_to(temp).as_posix()
                if not rel.startswith('animejanai/'):raise RuntimeError('Unexpected component location: '+rel)
                files.append({'path':rel,'bytes':p.stat().st_size,'sha256':sha(p)})
                cp(p,ST/rel)
            if not files:raise RuntimeError('Empty component pack')
            records.append({'name':item['id'],'source':item,'files':files})
            shutil.rmtree(temp);archive.unlink()
    dump(E/'component-inputs.json',records)
    shutil.rmtree(ST/'portable_config/watch_later',ignore_errors=True)
    shutil.rmtree(ST/'portable_config/scripts',ignore_errors=True)
    cp(R/'portable_config',ST/'portable_config')
    cp(R/'animejanai/animejanai.conf',ST/'animejanai/animejanai.conf')
    cp(R/'THIRD_PARTY_LICENSES',ST/'THIRD_PARTY_LICENSES');cp(R/'LICENSE',ST/'LICENSE')
    for folder in ('publish-player','publish-manager','publish-updater'):
        for p in (R/folder).rglob('*'):
            if p.is_file() and p.suffix.lower() in ('.exe','.dll','.json'):cp(p,ST/p.relative_to(R/folder))
    candidates=list(Path(r'C:\Program Files\Microsoft Visual Studio\2022').glob('*/VC/Redist/MSVC/*/x64/Microsoft.VC143.CRT'))
    if candidates:
        crt=sorted(candidates)[-1]
        for p in crt.glob('*.dll'):cp(p,ST/p.name)
        dump(E/'vc-runtime.json',{'directory':str(crt),'files':{p.name:sha(p) for p in crt.glob('*.dll')}})
    for p in list(ST.rglob('*')):
        if p.is_file() and p.suffix.lower() in FONTS:p.unlink()
    from vendor_notices import collect
    collect(ST,E)
    (ST/'portable_config/scripts/modernx.lua').unlink(missing_ok=True)
    (ST/'portable_config/script-opts/modernx.conf').unlink(missing_ok=True)
    p=ST/'portable_config/scripts/thumbfast.lua';s=p.read_text(encoding='utf-8')
    s=s.replace('local mpv_path = options.mpv_path','local mpv_path = options.mpv_path == "mpv" and mp.command_native({"expand-path", "~~/../mpv.exe"}) or options.mpv_path')
    p.write_text(s,encoding='utf-8')
    for n in ('input.conf','input-animejanai.conf'):
        p=ST/'portable_config'/n;s=p.read_text(encoding='utf-8')
        s=s.replace('apply-profile upscale-on; script-message aji-slot','script-message aji-slot')
        p.write_text(s,encoding='utf-8')
    records=prune(ST,records,E)
    dump(ST/'build-info/standalone/components.json',records)
    dump(ST/'manifest.json',{'version':META['version'],'distribution':'full-portable','repository':REPO,'component_version':'3.6.0','gpu_target':TARGET})
    cp(R/'docs/standalone.md',ST/'使用说明.md')
    for name in ('准备使用.txt','README-full.txt'):
        (ST/name).write_text('完整便携版：直接运行 mpvnet.exe。\n不需要先安装原版，不要将此包当覆盖补丁使用。\n中文与语言选择在管理器全局设置；完整说明见 使用说明.md。\n首次生成 AI 引擎需要等待，显卡驱动仍由系统提供。\n',encoding='utf-8')
    inspect_payload()

def clean_session_files(app):
    for folder in ('cache','watch_later'):
        shutil.rmtree(app/'portable_config'/folder,ignore_errors=True)
    for name in ('settings.xml','saved-props.json','startup-diagnostic.json','startup-diagnostic.json.tmp','playback-diagnostic.json'):
        (app/'portable_config'/name).unlink(missing_ok=True)

def inspect_payload():
    clean_session_files(ST)
    files=[p for p in ST.rglob('*') if p.is_file()]
    dump(E/'file-inventory.json',{p.relative_to(ST).as_posix():p.stat().st_size for p in files})
    required=['mpvnet.exe','mpv.exe','libmpv-2.dll','AnimeJaNaiManager.exe','AnimeJaNaiUpdater.exe',
       'portable_config/mpv.conf','portable_config/mpv-animejanai.conf','portable_config/input.conf',
       'portable_config/scripts/network_playback.lua','portable_config/scripts/network_playback.lua','portable_config/scripts/network_playback.lua','portable_config/scripts/network_playback.lua','portable_config/scripts/player_ui.lua','portable_config/scripts/player_ui_danmaku.lua','portable_config/scripts/thumbfast.lua',
       'portable_config/script-modules/player_ui_core.lua','portable_config/script-modules/player_ui_metrics.lua',
       'portable_config/script-modules/player_ui_menu.lua',
       'animejanai/animejanai.conf','animejanai/inference/aji.dll','animejanai/inference/aji_trt.dll',
       'animejanai/inference/nvinfer_11.dll','animejanai/inference/trtexec.exe','Locale/zh-CN/LC_MESSAGES/mpvnet.mo']
    for name in required:
        if not (ST/name).is_file() or (ST/name).stat().st_size==0:raise RuntimeError('Incomplete package: '+name)
    conf=(ST/'animejanai/animejanai.conf').read_text(encoding='utf-8-sig')
    models=set(re.findall(r'^chain_\d+_model_\d+_name=(.+)$',conf,re.M))
    for n in models:
        if not (ST/'animejanai/onnx'/(n.strip()+'.onnx')).is_file():raise RuntimeError('Missing preset model: '+n)
    parser=configparser.ConfigParser(interpolation=None,strict=False);parser.read_string(conf)
    rife_required=set()
    for section in parser.values():
        for k,code in section.items():
            match=re.fullmatch(r'chain_(\d+)_rife_model',k)
            if not match:continue
            code=code.strip()
            if not code.isdigit() or len(code) not in (2,3,4):raise RuntimeError('Invalid configured RIFE code: '+code)
            name='rife_v'+code[0]+'.'+code[1:3]
            if len(code)==4 and code[-1]=='1':name+='_lite'
            if section.get('chain_'+match[1]+'_rife_ensemble','no').strip().lower() in ('yes','true','1'):name+='_ensemble'
            rife_required.add(name+'.onnx')
    for name in rife_required:
        if not (ST/'animejanai/rife'/name).is_file():raise RuntimeError('Missing configured RIFE file: '+name)
    rife=list((ST/'animejanai/rife').glob('*.onnx'))
    if not rife or not rife_required:raise RuntimeError('Missing RIFE model collection')
    for family in ('120',):
        if not list((ST/'animejanai/inference').glob('nvinfer_builder_resource_sm'+family+'*')):raise RuntimeError('Missing kernel family '+family)
    licenses=[p for p in (ST/'animejanai/inference').iterdir() if 'LICENSE' in p.name.upper()]
    texts={p.name:p.read_text(encoding='utf-8',errors='replace') for p in licenses if p.is_file()}
    dump(E/'license-inventory.json',texts)
    trt=any('TENSORRT' in n.upper() or ('TensorRT' in t and 'AGREEMENT' in t and 'NVIDIA' in t) for n,t in texts.items())
    cuda=any('CUDA' in n.upper() or ('CUDA' in t and 'AGREEMENT' in t and 'NVIDIA' in t) for n,t in texts.items())
    if not trt or not cuda:raise RuntimeError('Missing NVIDIA license texts; inspect license-inventory.json')
    if any(p.suffix.lower() in FONTS for p in files):raise RuntimeError('Unexpected standalone font file')
    validate_gpu_target(ST,E)
    dump(E/'payload.json',{'required_files':required,'preset_models':sorted(models),'rife_models':len(rife),'required_rife_files':sorted(rife_required),
       'license_files':[p.relative_to(ST).as_posix() for p in licenses],
       'files':len(files),'unpacked_bytes':sum(p.stat().st_size for p in files),'gpu_inference_tested':False})

def package():
    for name,marker in [('manager-tests.txt','PASS Manager language suite'),('player-tests.txt','PASS Player language suite'),('parser-tests.txt','PASS')]:
        if marker not in (R/'language-evidence'/name).read_text(encoding='utf-8-sig'):raise RuntimeError('UI regression failed: '+name)
    for n in ('results.json','scripts-results.json'):
        results=json.loads((E/'runtime'/n).read_text(encoding='utf-8'))
        if not results or not all(r['passed'] for r in results):raise RuntimeError('Runtime tests failed')
    shutil.rmtree(ST/'portable_config/watch_later',ignore_errors=True)
    inspect_payload();DIST.mkdir(exist_ok=True)
    info=ST/'build-info/standalone'
    shutil.rmtree(info/'validation',ignore_errors=True)
    shutil.rmtree(info/'ui-validation',ignore_errors=True)
    cp(E,info/'validation');cp(R/'language-evidence',info/'ui-validation')
    dump(info/'provenance.json',{'version':META['version'],'input_commit':os.environ['GITHUB_SHA'],
      'run_id':os.environ['GITHUB_RUN_ID'],'dependencies':LOCK,'self_contained_dotnet':True,
      'gpu_inference_tested':False,'player_ui_server_tested':False})
    dump(info/'SHA256.json',{p.relative_to(ST).as_posix():sha(p) for p in ST.rglob('*') if p.is_file() and p!=info/'SHA256.json'})
    archive=DIST/f'AnimeJaNai-zh-CN-{META["version"]}-rtx5080-laptop-win-x64-full.7z'
    run(SEVEN,'a','-t7z','-mx=3','-mmt=2','-bd',archive,'.',cwd=ST,stdout=subprocess.DEVNULL)
    run(SEVEN,'t',archive,stdout=subprocess.DEVNULL)
    archives=[archive]
    if archive.stat().st_size>=2*1024**3:
        archives=[]
        with archive.open('rb') as f:
            index=1
            while f.tell()<archive.stat().st_size:
                part=Path(str(archive)+f'.{index:03}')
                with part.open('wb') as out:
                    remaining=1900*1024**2
                    while remaining:
                        data=f.read(min(remaining,1024*1024))
                        if not data:break
                        out.write(data);remaining-=len(data)
                archives.append(part);index+=1
        archive.unlink()
    dump(DIST/'artifacts.json',[{'repo':REPO,'tag':META['tag'],'name':p.name,'sha256':sha(p),'bytes':p.stat().st_size} for p in archives])
    shutil.rmtree(ST);extract(archives[0],R/'clean-install')
    run(sys.executable,R/'tests/test_gpu_target.py',R/'clean-install',E/'fresh-install')
    run(sys.executable,H/'test_complete.py',R/'clean-install',E/'fresh-install')
    run(sys.executable,R/'tests/test_player_ui_windows.py',R/'clean-install',E/'fresh-install/player_ui')
    run(sys.executable,R/'tests/test_network_playback.py',R/'clean-install',E/'fresh-install/network')
    run(sys.executable,R/'tests/test_startup_playback.py',R/'clean-install',E/'fresh-install/startup')
    run(sys.executable,R/'tests/test_player_ui_empty_scope.py',R/'clean-install',E/'fresh-install/player_ui-handoff')
    cp(E/'fresh-install',DIST/'fresh-install-evidence')
    sourcezip=DIST/f'AnimeJaNai-zh-CN-{META["version"]}-sources.zip'
    with zipfile.ZipFile(sourcezip,'w',zipfile.ZIP_DEFLATED) as z:
        for folder in ('src','tools','tests','portable_config','animejanai','THIRD_PARTY_LICENSES'):
            for p in (R/folder).rglob('*'):
                if p.is_file() and not any(x in ('bin','obj','__pycache__','.git') for x in p.relative_to(R/folder).parts) and p.suffix.lower() not in FONTS:z.write(p,p.relative_to(R).as_posix())
        for n in ('LICENSE','release.json','docs/standalone.md'):z.write(R/n,n)
    (DIST/'SHA256SUMS.txt').write_text(''.join(sha(p)+'  '+p.name+'\n' for p in archives+[sourcezip]),encoding='utf-8')
    cp(R/'docs/standalone.md',DIST/'RELEASE.md');cp(E/'payload.json',DIST/'payload-verification.json')
    print('FULL PACKAGE VERIFIED',[(p.name,p.stat().st_size) for p in archives],flush=True)

def api(endpoint,payload=None,method=None):
    cmd=['gh','api',endpoint]
    if payload is not None:result=subprocess.check_output(cmd+['--method',method or 'POST','--input','-'],input=json.dumps(payload).encode())
    else:result=subprocess.check_output(cmd)
    return json.loads(result)

if __name__=='__main__':{'prepare':prepare,'stage':stage,'package':package}[sys.argv[1]]()
