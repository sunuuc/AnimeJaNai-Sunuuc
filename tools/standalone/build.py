"""Full portable distribution builder. Bootstrap once; subsequent inputs live in our repo.
Commands: prepare / stage / package / publish. Never reads a user's installation.
"""
from pathlib import Path, PurePosixPath
import base64, configparser, hashlib, json, os, re, shutil, subprocess, sys, time, urllib.request, zipfile
R=Path.cwd(); H=R/'tools/standalone'; ST=R/'stage'; DIST=R/'dist'; E=R/'complete-evidence'
META=json.loads((R/'release.json').read_text(encoding='utf-8'))
LOCK=json.loads((H/'dependencies.json').read_text(encoding='utf-8'))
REPO='sunuuc/AnimeJaNai-zh-CN'
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
        listing=subprocess.check_output([SEVEN,'l','-slt','-sccUTF-8',str(archive)]).decode('utf-8',errors='strict').replace('\r\n','\n')
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
    # The source archive is from our tested r4, including the language/global-settings fixes.
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
    # Build temporary working copies: src/ remains free of bin/obj and test fixtures.
    for name in ('player','manager'):cp(R/'src'/name,R/name)
    for name in ('Manager','Player'):
        dest=R/'tests-generated'/(name.lower()+'-tests');dest.mkdir(parents=True,exist_ok=True)
        for ext in ('cs','csproj'):cp(R/f'tools/language-r3/{name}Tests.{ext}',dest/f'{name}Tests.{ext}')
    (R/'language-evidence').mkdir(exist_ok=True)
    # Source provenance does not claim the app was rewritten from scratch.
    dump(E/'source-inputs.json',{'ui_bootstrap':LOCK['ui_source'],'workflow_commit':os.environ.get('GITHUB_SHA'),
       'source_files':{p.relative_to(R/'src').as_posix():sha(p) for p in (R/'src').rglob('*') if p.is_file()}})

def stage():
    if ST.exists():shutil.rmtree(ST)
    seed=LOCK.get('runtime_seed')
    if seed:
        for item in seed['assets']:download(item)
        first=R/'downloads'/seed['assets'][0]['name'];extract(first,R/'seed-unpack')
        cp(app_root(R/'seed-unpack'),ST);shutil.rmtree(R/'seed-unpack')
        records=json.loads((ST/'build-info/standalone/components.json').read_text(encoding='utf-8'))
    else:
        base=download(LOCK['bootstrap_core']);extract(base,R/'base-unpack');original=app_root(R/'base-unpack')
        # Keep the pinned inference stack, models, shaders, defaults and their notices.
        cp(original,ST);shutil.rmtree(R/'base-unpack');base.unlink()
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
    # No leftovers from the upstream controller set; only our maintained scripts run.
    shutil.rmtree(ST/'portable_config/scripts',ignore_errors=True)
    cp(R/'portable_config',ST/'portable_config')
    cp(R/'animejanai/animejanai.conf',ST/'animejanai/animejanai.conf')
    cp(R/'THIRD_PARTY_LICENSES',ST/'THIRD_PARTY_LICENSES');cp(R/'LICENSE',ST/'LICENSE')
    for folder in ('publish-player','publish-manager','publish-updater'):
        for p in (R/folder).rglob('*'):
            if p.is_file() and p.suffix.lower() in ('.exe','.dll','.json'):
                cp(p,ST/p.relative_to(R/folder))
    # App-local VC runtime, not a requirement to run a separate redistributable installer.
    candidates=list(Path(r'C:\Program Files\Microsoft Visual Studio\2022').glob('*/VC/Redist/MSVC/*/x64/Microsoft.VC143.CRT'))
    if candidates:
        crt=sorted(candidates)[-1]
        for p in crt.glob('*.dll'):cp(p,ST/p.name)
        dump(E/'vc-runtime.json',{'directory':str(crt),'files':{p.name:sha(p) for p in crt.glob('*.dll')}})
    for p in list(ST.rglob('*')):
        if p.is_file() and p.suffix.lower() in FONTS:p.unlink()
    # Resolve the modern control bar's icons via Windows' built-in symbols.
    p=ST/'portable_config/scripts/modernx.lua';s=p.read_text(encoding='utf-8')
    s=s.replace("local iconfont = 'fluent-system-icons'","local iconfont = 'Segoe UI Symbol'")
    marker='-- Localization'
    icons='''-- System-font fallback: no separately installed icon font is required.
icons = {play="▶",pause="Ⅱ",replay="↻",previous="|◀",next="▶|",rewind="◀◀",forward="▶▶",
 audio="♫",subtitle="CC",volume={mute="×",quiet="♪",low="♫",high="♫"},download="↓",download_initiated="✓",
 loop_off="↪",loop_on="↻",info="ⓘ",pinned_off="◇",pinned_on="◆",screenshot="▣",playlist="≡",
 fullscreen="□",fullscreen_exit="▣",jumpicons={[5]={"↶","↷"},[10]={"↶","↷"},[30]={"↶","↷"},default={"↶","↶"}},
 window={maximize="□",unmaximize="▣",minimize="−",close="×"},emoticon={view="◉",comment="…",like="+"}}
'''
    if s.count(marker)!=1:raise RuntimeError('ModernX source changed')
    s=s.replace(marker,icons+'\n'+marker)
    old='local texts = language[user_opts.language] or language["en"]'
    extra='''language["zh-CN"]={welcome="拖入视频文件或链接开始播放",off="关闭",na="不可用",none="无",video="视频",audio="音频",subtitle="字幕",nosub="没有可用字幕",noaudio="没有可用音轨",track=" 个轨道：",playlist="播放列表",playlistshuffled="已打乱播放列表",nolist="播放列表为空",chapter="章节",nochapter="没有章节",ontop="窗口置顶",ontopdisable="取消置顶",loopenable="已开启循环",loopdisable="已关闭循环",screenshot="截图",statsinfo="信息",download="下载",download_in_progress="正在下载",downloading="下载中",downloaded="已下载"}
local ui_language="zh-CN"
local pref=io.open(mp.command_native({"expand-path","~~/interface-language.json"}),"r")
if pref then local data=require("mp.utils").parse_json(pref:read("*a"));pref:close();if data and data.language=="en" then ui_language="en" elseif data and data.language=="system" then ui_language=user_opts.language end end
local texts=language[ui_language] or language["en"]'''
    if old not in s:raise RuntimeError('ModernX localization context changed')
    p.write_text(s.replace(old,extra),encoding='utf-8')
    p=ST/'portable_config/scripts/thumbfast.lua';s=p.read_text(encoding='utf-8')
    s=s.replace('local mpv_path = options.mpv_path','local mpv_path = options.mpv_path == "mpv" and mp.command_native({"expand-path", "~~/../mpv.exe"}) or options.mpv_path')
    p.write_text(s,encoding='utf-8')
    # New installs get the safe key bindings directly; no runtime migration is needed.
    for n in ('input.conf','input-animejanai.conf'):
        p=ST/'portable_config'/n;s=p.read_text(encoding='utf-8')
        s=s.replace('apply-profile upscale-on; script-message aji-slot','script-message aji-slot')
        s=s.replace('#menu: AnimeJaNai > 安装更新','#menu: AnimeJaNai > 检查本项目更新')
        p.write_text(s,encoding='utf-8')
    dump(ST/'build-info/standalone/components.json',records)
    dump(ST/'manifest.json',{'version':META['version'],'distribution':'full-portable','repository':REPO,'component_version':'3.6.0'})
    cp(R/'docs/standalone.md',ST/'使用说明.md')
    for name in ('准备使用.txt','README-full.txt'):
        (ST/name).write_text('完整便携版：直接运行 mpvnet.exe。\n不需要先安装原版，不要将此包当覆盖补丁使用。\n中文与语言选择在管理器全局设置；完整说明见 使用说明.md。\n首次生成 AI 引擎需要等待，显卡驱动仍由系统提供。\n',encoding='utf-8')
    inspect_payload()

def inspect_payload():
    required=['mpvnet.exe','mpv.exe','libmpv-2.dll','AnimeJaNaiManager.exe','AnimeJaNaiUpdater.exe',
       'portable_config/mpv.conf','portable_config/mpv-animejanai.conf','portable_config/input.conf',
       'portable_config/scripts/modernx.lua','portable_config/scripts/thumbfast.lua',
       'animejanai/animejanai.conf','animejanai/inference/aji.dll','animejanai/inference/aji_trt.dll',
       'animejanai/inference/aji_dml.dll','animejanai/inference/onnxruntime.dll','animejanai/inference/DirectML.dll',
       'animejanai/inference/nvinfer_11.dll','animejanai/inference/trtexec.exe','Locale/zh-CN/LC_MESSAGES/mpvnet.mo']
    for name in required:
        if not (ST/name).is_file() or (ST/name).stat().st_size==0:raise RuntimeError('Incomplete package: '+name)
    conf=(ST/'animejanai/animejanai.conf').read_text(encoding='utf-8-sig')
    models=set(re.findall(r'^chain_\d+_model_\d+_name=(.+)$',conf,re.M))
    for n in models:
        if not (ST/'animejanai/onnx'/(n.strip()+'.onnx')).is_file():raise RuntimeError('Missing preset model: '+n)
    rife=list((ST/'animejanai/rife').glob('*.onnx'))
    if not rife or not any('426' in p.name for p in rife):raise RuntimeError('RIFE v426 model is missing')
    for family in ('75','86','89','120'):
        if not list((ST/'animejanai/inference').glob('nvinfer_builder_resource_sm'+family+'*')):raise RuntimeError('Missing kernel family '+family)
    licenses=[p for p in (ST/'animejanai/inference').iterdir() if 'LICENSE' in p.name.upper()]
    if not any('TENSORRT' in p.name.upper() for p in licenses) or not any('CUDA' in p.name.upper() for p in licenses):raise RuntimeError('Missing NVIDIA license texts')
    if any(p.suffix.lower() in FONTS for p in ST.rglob('*') if p.is_file()):raise RuntimeError('Unexpected standalone font file')
    dump(E/'payload.json',{'required_files':required,'preset_models':sorted(models),'rife_models':len(rife),
       'license_files':[p.relative_to(ST).as_posix() for p in licenses],
       'files':len([p for p in ST.rglob('*') if p.is_file()]),'unpacked_bytes':sum(p.stat().st_size for p in ST.rglob('*') if p.is_file()),
       'gpu_inference_tested':False})

def package():
    for name,marker in [('manager-tests.txt','PASS Manager language suite'),('player-tests.txt','PASS Player language suite'),('parser-tests.txt','PASS')]:
        if marker not in (R/'language-evidence'/name).read_text(encoding='utf-8-sig'):raise RuntimeError('UI regression failed: '+name)
    for n in ('results.json','scripts-results.json'):
        results=json.loads((E/'runtime'/n).read_text(encoding='utf-8'))
        if not results or not all(r['passed'] for r in results):raise RuntimeError('Runtime tests failed')
    inspect_payload();DIST.mkdir(exist_ok=True)
    info=ST/'build-info/standalone';cp(E,info/'validation');cp(R/'language-evidence',info/'ui-validation')
    dump(info/'provenance.json',{'version':META['version'],'input_commit':os.environ['GITHUB_SHA'],
      'run_id':os.environ['GITHUB_RUN_ID'],'dependencies':LOCK,'self_contained_dotnet':True,
      'gpu_inference_tested':False,'player_ui_server_tested':False})
    hashes={p.relative_to(ST).as_posix():sha(p) for p in ST.rglob('*') if p.is_file() and p!=info/'SHA256.json'}
    dump(info/'SHA256.json',hashes)
    archive=DIST/f'AnimeJaNai-zh-CN-{META["version"]}-win-x64-full.7z'
    # Archiving the contents of a clean app directory, not a patch.
    run(SEVEN,'a','-t7z','-mx=3','-mmt=2','-bd',archive,'.',cwd=ST,stdout=subprocess.DEVNULL)
    run(SEVEN,'t',archive,stdout=subprocess.DEVNULL)
    if archive.stat().st_size>=2*1024**3:
        parts=[]
        with archive.open('rb') as f:
            i=1
            while True:
                data=f.read(1900*1024**2)
                if not data:break
                part=Path(str(archive)+f'.{i:03}');part.write_bytes(data);parts.append(part);i+=1
        archive.unlink();archives=parts
    else:archives=[archive]
    dump(DIST/'artifacts.json',[{'repo':REPO,'tag':META['tag'],'name':p.name,'sha256':sha(p),'bytes':p.stat().st_size} for p in archives])
    # Test what users actually extract. Remove the staging tree first so it cannot
    # accidentally supply any files to this independent installation.
    shutil.rmtree(ST);extract(archives[0],R/'clean-install')
    run(sys.executable,H/'test_complete.py',R/'clean-install',E/'fresh-install')
    cp(E/'fresh-install',DIST/'fresh-install-evidence')
    sourcezip=DIST/f'AnimeJaNai-zh-CN-{META["version"]}-sources.zip'
    with zipfile.ZipFile(sourcezip,'w',zipfile.ZIP_DEFLATED) as z:
        for folder in ('src','tools','tests','portable_config','animejanai','THIRD_PARTY_LICENSES'):
            for p in (R/folder).rglob('*'):
                if p.is_file() and not any(x in ('bin','obj','__pycache__','.git') for x in p.relative_to(R/folder).parts) and p.suffix.lower() not in FONTS:
                    z.write(p,p.relative_to(R).as_posix())
        for n in ('LICENSE','release.json','docs/standalone.md'):z.write(R/n,n)
    files=archives+[sourcezip]
    (DIST/'SHA256SUMS.txt').write_text(''.join(sha(p)+'  '+p.name+'\n' for p in files),encoding='utf-8')
    cp(R/'docs/standalone.md',DIST/'RELEASE.md');cp(E/'payload.json',DIST/'payload-verification.json')
    print('FULL PACKAGE VERIFIED',[(p.name,p.stat().st_size) for p in archives],flush=True)

def api(endpoint,payload=None,method=None):
    cmd=['gh','api',endpoint]
    if payload is not None:
        cmd+=['--method',method or 'POST','--input','-']
        result=subprocess.check_output(cmd,input=json.dumps(payload).encode())
    else:result=subprocess.check_output(cmd)
    return json.loads(result)

def publish():
    for line in (DIST/'SHA256SUMS.txt').read_text().splitlines():
        h,n=line.split('  ',1)
        if sha(DIST/n)!=h:raise RuntimeError('Publication hash mismatch '+n)
    fresh=json.loads((E/'fresh-install/results.json').read_text())
    if not all(x['passed'] for x in fresh):raise RuntimeError('Fresh installation failed')
    head=api(f'repos/{REPO}/git/ref/heads/main')['object']['sha']
    if head!=os.environ['GITHUB_SHA']:raise RuntimeError('Main changed during build; refusing a stale source import/release')
    # Save complete UI sources and switch future packaging to our own runtime seed.
    LOCK['runtime_seed']={'assets':json.loads((DIST/'artifacts.json').read_text()),'version':META['version']}
    dump(H/'dependencies.json',LOCK)
    readme=R/'README.md';text=readme.read_text(encoding='utf-8')
    note=f'\n> **完整便携版 {META["version"]}**：[下载独立完整包](https://github.com/{REPO}/releases/tag/{META["tag"]})。解压到空目录即可使用，不再下载原项目或叠加覆盖包。包含程序、运行库、模型、语言和预设。[说明与验证范围](docs/standalone.md)。下方 r2/r3/r4 覆盖说明仅作为历史记录。\n'
    first,rest=text.split('\n',1);readme.write_text(first+'\n'+note+'\n'+rest,encoding='utf-8')
    # Commit only reviewed build inputs, with no executable/font/runtime binaries.
    paths=[p for p in (R/'src').rglob('*') if p.is_file() and not any(x in ('bin','obj','.git') for x in p.relative_to(R/'src').parts)]
    paths+=[H/'dependencies.json',readme]
    tree=[]
    for p in paths:
        if p.suffix.lower() in FONTS or p.suffix.lower() in ('.exe','.dll'):raise RuntimeError('Binary in UI source import: '+str(p))
        data=p.read_bytes()
        blob=api(f'repos/{REPO}/git/blobs',{'content':base64.b64encode(data).decode(),'encoding':'base64'})['sha']
        tree.append({'path':p.relative_to(R).as_posix(),'mode':'100644','type':'blob','sha':blob})
    base_tree=api(f'repos/{REPO}/git/commits/{head}')['tree']['sha']
    newtree=api(f'repos/{REPO}/git/trees',{'base_tree':base_tree,'tree':tree})['sha']
    commit=api(f'repos/{REPO}/git/commits',{'message':'完整便携版：保存已验证的独立 UI 源码、固定本仓库运行库种子与下载入口','tree':newtree,'parents':[head]})['sha']
    # Publish a draft by ID; do not query a non-existent draft tag.
    old=[r for r in api(f'repos/{REPO}/releases?per_page=100') if r['tag_name']==META['tag']]
    if old:raise RuntimeError('Version already exists; no overwriting published releases')
    notes=(DIST/'RELEASE.md').read_text(encoding='utf-8')+'\n\n构建来源：`'+head+'`；源码保存提交：`'+commit+'`。\n'
    rel=api(f'repos/{REPO}/releases',{'tag_name':META['tag'],'target_commitish':commit,'name':f'AnimeJaNai-zh-CN {META["version"]} 完整便携版','body':notes,'draft':True,'prerelease':META['prerelease']})
    # Upload only finished deliverables, not intermediate test recordings.
    run('gh','release','upload',META['tag'],'-R',REPO,*[p for p in DIST.iterdir() if p.is_file()])
    uploaded=api(f'repos/{REPO}/releases/{rel["id"]}')
    for item in LOCK['runtime_seed']['assets']:
        found=next(a for a in uploaded['assets'] if a['name']==item['name'])
        if found.get('digest')!='sha256:'+item['sha256']:raise RuntimeError('Uploaded full archive has the wrong hash')
    api(f'repos/{REPO}/git/refs/heads/main',{'sha':commit,'force':False},'PATCH')
    api(f'repos/{REPO}/releases/{rel["id"]}',{'draft':False},'PATCH')
    dump(DIST/'publication.json',{'release_id':rel['id'],'source_commit':commit,'build_commit':head,'url':rel['html_url']})
    print('PUBLISHED',META['tag'],commit)

if __name__=='__main__':
    {'prepare':prepare,'stage':stage,'package':package,'publish':publish}[sys.argv[1]]()
