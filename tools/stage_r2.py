"""Stage pinned, hash-verified artifacts; never read or mutate a user's install."""
from pathlib import Path, PurePosixPath
import hashlib, json, os, shutil, subprocess, sys, zipfile
ROOT=Path(__file__).resolve().parents[1]
STAGE=ROOT/'stage'; INFO=STAGE/'build-info'
ARTIFACTS={
 'native':(10337284004,'fb7e6d2973569e93bb382cd8cbfd5eaaf43d4b7628ea46517215ed81d50d4fb6'),
 'ui':(10336697862,'6a394dbeeb01f404cd6c2afdad3cbbd97afd0262eeb38e5cf7d616d0306dcb31')}
def extract(archive,dest):
    with zipfile.ZipFile(archive) as z:
        for i in z.infolist():
            p=PurePosixPath(i.filename)
            if p.is_absolute() or '..' in p.parts or '\\' in i.filename or ':' in i.filename:
                raise RuntimeError('Unsafe archive path: '+i.filename)
        z.extractall(dest)
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def prepare():
    STAGE.mkdir(exist_ok=True);INFO.mkdir(exist_ok=True)
    for name,(aid,sha) in ARTIFACTS.items():
        archive=ROOT/(name+'.zip')
        with archive.open('wb') as f:
            subprocess.run(['gh','api',f'repos/sunuuc/AnimeJaNai-zh-CN/actions/artifacts/{aid}/zip'],stdout=f,check=True)
        if digest(archive)!=sha:raise RuntimeError('Artifact hash mismatch: '+name)
        temp=ROOT/(name+'-verified');extract(archive,temp)
        for p in temp.rglob('*'):
            if not p.is_file():continue
            rel=p.relative_to(temp)
            target=INFO/name/Path(*rel.parts[1:]) if rel.parts[0]=='build-info' else STAGE/rel
            target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,target)
    # Incremental overlay: deliberately exclude personal mpv.conf, input.conf,
    # animejanai.conf, models, inference runtimes and engine caches.
    for name in ['animejanaistats.lua','animejanai_session.lua','animejanai_engine_monitor.lua','animejanai_update.lua']:
        dest=STAGE/'portable_config/scripts'/name;dest.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(ROOT/'portable_config/scripts'/name,dest)
    for p in (ROOT/'THIRD_PARTY_LICENSES').rglob('*'):
        if p.is_file():
            dst=STAGE/p.relative_to(ROOT);dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dst)
    upstream=ROOT/'upstream'
    fixed=[]
    # Use exact upstream paths: these are mpv .hook files, not .glsl files.
    for name in ('noise_static_chroma.hook','noise_static_luma.hook'):
        rel=Path('portable_config/shaders')/name
        p=upstream/'BuildMpvUpscale2xAnimeJaNai/mpv-upscale-2x_animejanai'/rel
        assert 'vec4 noise = vec4(0.5)' in p.read_text(encoding='utf-8-sig'),name
        dest=STAGE/rel;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dest);fixed.append(rel.as_posix())
    p=upstream/'AnimeJaNaiUpdater/Program.cs';text=p.read_text(encoding='utf-8-sig')
    needle='string mode = args.Length > 0 ? args[0].ToLowerInvariant() : "--check";'
    assert text.count(needle)==1
    guard='''
// Protect the Chinese frontend and custom libmpv. Components remain intact.
if (mode is "--check" or "--apply")
{
    Console.WriteLine("MANUAL_UPDATE https://github.com/sunuuc/AnimeJaNai-zh-CN/releases");
    Console.WriteLine("请在中文版本发布页更新；组件管理不受影响。播放器不会自动退出。");
    return 0;
}
'''
    text=text.replace(needle,needle+'\n'+guard);p.write_text(text,encoding='utf-8')
    source=INFO/'sources';source.mkdir(exist_ok=True)
    shutil.copy2(p,source/'AnimeJaNaiUpdater.Program.cs')
    for name in ['stage_r2.py','../tests/test_windows_r2.py','../tests/test_stats.lua']:
        src=Path(__file__).parent/name;shutil.copy2(src,source/src.name)
    (INFO/'provenance.json').write_text(json.dumps({
        'revision':os.environ['GITHUB_SHA'],'run_id':os.environ['GITHUB_RUN_ID'],
        'player':'23946b4e9fefc8cef0d57b6c10131b47af5ace38',
        'manager_base':'bdcf21af308d9494d23a309055196e7937819afc',
        'manager_patch':'d69c523e3c21a5097a2a9366faf33516512845a2',
        'mpv':'d4c06dd3424dc06d90d4ea15b0fa92fa3ceeb62f',
        'libass':'896614fa263f9f64944f7b8650ff6806d5328c4d',
        'updater_and_shaders':'2151166dec7945d161f45cea5e8c5724731fb949',
        'verified_artifacts':ARTIFACTS,'fixed_shaders':fixed,
        'gpu_tested':False,'player_ui_real_account_tested':False,
        'component_runtime':'unchanged; use installed 3.6.0 components'},ensure_ascii=False,indent=2),encoding='utf-8')

def finish():
    results=json.loads((INFO/'runtime-r2/results.json').read_text(encoding='utf-8'))
    assert results and all(x['passed'] for x in results),'Do not package failing tests'
    assert (STAGE/'AnimeJaNaiUpdater.exe').stat().st_size>1000000
    assert 'vo-presented-frame-count' in (STAGE/'portable_config/scripts/animejanaistats.lua').read_text(encoding='utf-8')
    assert not (STAGE/'animejanai/animejanai.conf').exists()
    shutil.copy2(ROOT/'docs/RELEASE-r2.md',STAGE/'更新说明-r2.md')
    for p in INFO.rglob('*.y4m'):p.unlink()
    hashes={p.relative_to(STAGE).as_posix():digest(p) for p in sorted(STAGE.rglob('*')) if p.is_file()}
    (INFO/'SHA256.json').write_text(json.dumps(hashes,ensure_ascii=False,indent=2),encoding='utf-8')
    DIST=ROOT/'dist';DIST.mkdir(exist_ok=True)
    target=DIST/'AnimeJaNai-3.6.0-zh-CN-r2-update.zip'
    with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for p in sorted(STAGE.rglob('*')):
            if p.is_file():z.write(p,p.relative_to(STAGE).as_posix())
    with zipfile.ZipFile(target) as z:
        assert z.testzip() is None
        for name,sha in hashes.items():assert hashlib.sha256(z.read(name)).hexdigest()==sha,name
    (DIST/'SHA256SUMS.txt').write_text(digest(target)+'  '+target.name+'\n',encoding='utf-8')
    shutil.copy2(ROOT/'docs/RELEASE-r2.md',DIST/'RELEASE-r2.md')
    shutil.copy2(INFO/'runtime-r2/results.json',DIST/'runtime-results.json')
    print('VERIFIED PACKAGE',target,digest(target),target.stat().st_size)
if __name__=='__main__':
    {'prepare':prepare,'finish':finish}[sys.argv[1]]()
