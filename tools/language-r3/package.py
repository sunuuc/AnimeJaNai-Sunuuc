"""Cumulative r3 patch over the exact r2 release; no models or user configs."""
from pathlib import Path,PurePosixPath
import hashlib,json,os,shutil,subprocess,sys,urllib.request,zipfile
R=Path.cwd();stage=R/'stage';evidence=R/'language-evidence';dist=R/'dist';dist.mkdir(exist_ok=True)
name='AnimeJaNai-3.6.0-zh-CN-r3-language-update.zip'
oldsha='90bb725313ee624df6938d4a84e21da149374043dc043cc378680b863470dee8'
def hashfile(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def safe_extract(archive,folder):
    with zipfile.ZipFile(archive) as z:
        for i in z.infolist():
            p=PurePosixPath(i.filename)
            assert not p.is_absolute() and '..' not in p.parts and ':' not in i.filename and '\\' not in i.filename
        z.extractall(folder)
def stage_files():
    url='https://github.com/sunuuc/AnimeJaNai-zh-CN/releases/download/zh-CN-3.6.0-r2/AnimeJaNai-3.6.0-zh-CN-r2-update.zip'
    urllib.request.urlretrieve(url,R/'r2-base.zip');assert hashfile(R/'r2-base.zip')==oldsha
    safe_extract(R/'r2-base.zip',stage)
    for folder in ('publish-player','publish-manager'):
        for p in (R/folder).rglob('*'):
            if p.is_file() and p.suffix.lower() in ('.exe','.dll','.json'):
                dst=stage/p.relative_to(R/folder);dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dst)
    shutil.copytree(R/'locale',stage/'Locale',dirs_exist_ok=True)
    with zipfile.ZipFile(R/'r2-base.zip') as z:
        for p in ('libmpv-2.dll','mpv.exe','AnimeJaNaiUpdater.exe','portable_config/scripts/animejanaistats.lua'):
            assert (stage/p).read_bytes()==z.read(p),p
    for p in ('mpvnet.exe','AnimeJaNaiManager.exe'):assert (stage/p).stat().st_size>1000000
    for p in ('zh-CN','zh_CN','zh'):assert (stage/'Locale'/p/'LC_MESSAGES/mpvnet.mo').stat().st_size>10000

def finish():
    for f,marker in [('manager-tests.txt','PASS Manager language suite'),('player-tests.txt','PASS Player language suite'),
                     ('parser-tests.txt','PASS'),('profile-tests.txt','PASS')]:
        assert marker in (evidence/f).read_text(encoding='utf-8-sig'),f
    for filename in ('results.json','scripts-results.json'):
        result=json.loads((stage/'build-info/runtime-r3'/filename).read_text(encoding='utf-8'))
        assert result and all(r['passed'] for r in result),filename
    assert not any((stage/p).exists() for p in ['portable_config/interface-language.json','portable_config/mpv.conf','portable_config/input.conf','animejanai/animejanai.conf'])
    assert not any(p.suffix.lower() in ('.otf','.ttf','.ttc','.woff','.woff2') for p in stage.rglob('*'))
    info=stage/'build-info/language-r3';shutil.copytree(evidence,info,dirs_exist_ok=True)
    shutil.copy2(R/'language-coverage.json',info/'coverage.json')
    manifest={'commit':os.environ['GITHUB_SHA'],'build_run':os.environ['GITHUB_RUN_ID'],
        'r2_base_sha256':oldsha,'player_base':'23946b4e9fefc8cef0d57b6c10131b47af5ace38',
        'manager_base':'bdcf21af308d9494d23a309055196e7937819afc','default_language':'zh-CN',
        'choices':['zh-CN','en','system'],'restart_required':True,'settings_help_entries':150,
        'gpu_playback_retested':False,'native_runtime':'byte-identical to r2'}
    (info/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    shutil.copy2(R/'docs/RELEASE-r3.md',stage/'更新说明-r3.md')
    with zipfile.ZipFile(dist/'r3-ui-sources.zip','w',zipfile.ZIP_DEFLATED) as z:
        for folder in ('player','manager','tools/language-r3'):
            for p in (R/folder).rglob('*'):
                if p.is_file() and not any(c in ('.git','bin','obj') for c in p.relative_to(R/folder).parts):
                    if p.suffix.lower() in ('.cs','.csproj','.props','.targets','.xaml','.axaml','.json','.py','.txt','.tsv','.md','.po','.resx','.config','.xml','.manifest','.ico','.png','.svg','.sln') or p.name=='LICENSE':
                        z.write(p,p.relative_to(R).as_posix())
    hashes={p.relative_to(stage).as_posix():hashfile(p) for p in stage.rglob('*') if p.is_file()}
    (info/'SHA256.json').write_text(json.dumps(hashes,ensure_ascii=False,indent=2),encoding='utf-8')
    with zipfile.ZipFile(dist/name,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for p in stage.rglob('*'):
            if p.is_file():z.write(p,p.relative_to(stage).as_posix())
    with zipfile.ZipFile(dist/name) as z:
        assert z.testzip() is None
        for p,h in hashes.items():assert hashlib.sha256(z.read(p)).hexdigest()==h,p
    (dist/'SHA256SUMS.txt').write_text(''.join(hashfile(p)+'  '+p.name+'\n' for p in [dist/name,dist/'r3-ui-sources.zip']))
    shutil.copy2(info/'manifest.json',dist/'manifest.json');shutil.copy2(R/'docs/RELEASE-r3.md',dist/'RELEASE-r3.md')
    print('VERIFIED',name,(dist/name).stat().st_size,hashfile(dist/name))

def publish():
    for line in (dist/'SHA256SUMS.txt').read_text().splitlines():
        h,n=line.split('  ',1);assert hashfile(dist/n)==h
    tag='zh-CN-3.6.0-r3';repo='sunuuc/AnimeJaNai-zh-CN'
    exists=subprocess.run(['gh','release','view',tag,'-R',repo],capture_output=True)
    if exists.returncode==0:raise RuntimeError('Release already exists; refusing to replace it')
    subprocess.run(['gh','release','create',tag,'-R',repo,'--target',os.environ['GITHUB_SHA'],'--draft','--prerelease',
        '--title','AnimeJaNai 3.6.0 中文修复包 r3 · 语言设置','--notes-file',str(dist/'RELEASE-r3.md')],check=True)
    subprocess.run(['gh','release','upload',tag,'-R',repo,*map(str,dist.iterdir())],check=True)
    subprocess.run(['gh','release','edit',tag,'-R',repo,'--draft=false','--prerelease'],check=True)
if __name__=='__main__':{'stage':stage_files,'finish':finish,'publish':publish}[sys.argv[1]]()
