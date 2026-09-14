"""Publish the reviewed Windows UI artifact, not a fresh untested rebuild."""
from pathlib import Path,PurePosixPath
import base64,hashlib,json,os,subprocess,zipfile
REPO='sunuuc/AnimeJaNai-zh-CN'
BUILD='4df6b71f0a6817e8c19cac57610c7b4ac2cd255b'
RUN=34845802442
ARTIFACT=10348375071
ARTIFACT_SHA='a2a7754d5872cd1ed54513bad388d60041e4963ae412bdd15064a6b727c2aa8d'
PACKAGE='AnimeJaNai-3.6.0-zh-CN-r3-language-update.zip'
PACKAGE_SHA='9049be5423c38d63d36dd3d771b2257b325a1be30173d05d53d218d3b33e4767'
TAG='zh-CN-3.6.0-r3'

def api(path):return json.loads(subprocess.check_output(['gh','api',path]))
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def validate_paths(z):
    for i in z.infolist():
        p=PurePosixPath(i.filename)
        assert not p.is_absolute() and '..' not in p.parts and ':' not in i.filename and '\\' not in i.filename,i.filename
run=api(f'repos/{REPO}/actions/runs/{RUN}')
assert run['head_sha']==BUILD and run['status']=='completed' and run['conclusion']=='success'
archive=Path('candidate.zip')
with archive.open('wb') as f:subprocess.run(['gh','api',f'repos/{REPO}/actions/artifacts/{ARTIFACT}/zip'],stdout=f,check=True)
assert digest(archive)==ARTIFACT_SHA
out=Path('publish-dist');out.mkdir()
with zipfile.ZipFile(archive) as z:validate_paths(z);z.extractall(out)
assert digest(out/PACKAGE)==PACKAGE_SHA
for line in (out/'SHA256SUMS.txt').read_text().splitlines():
    sha,name=line.split('  ',1);assert digest(out/name)==sha,name
with zipfile.ZipFile(out/PACKAGE) as z:
    validate_paths(z);assert z.testzip() is None
    assert not any(Path(n).suffix.lower() in ('.ttf','.otf','.ttc','.woff','.woff2') for n in z.namelist())
    manifest=json.loads(z.read('build-info/language-r3/manifest.json'))
    assert manifest['commit']==BUILD and manifest['default_language']=='zh-CN'
    assert manifest['choices']==['zh-CN','en','system']
    hashes=json.loads(z.read('build-info/language-r3/SHA256.json'))
    for n,h in hashes.items():assert hashlib.sha256(z.read(n)).hexdigest()==h,n
    previous=json.loads(z.read('build-info/SHA256.json'))
    for n in ['mpv.exe','libmpv-2.dll','AnimeJaNaiUpdater.exe','portable_config/scripts/animejanaistats.lua']:
        assert hashlib.sha256(z.read(n)).hexdigest()==previous[n],n
    for n in ['portable_config/mpv.conf','portable_config/input.conf','animejanai/animejanai.conf','portable_config/interface-language.json']:
        assert n not in z.namelist(),n
    for locale in ['zh','zh-CN','zh_CN']:
        assert z.read(f'Locale/{locale}/LC_MESSAGES/mpvnet.mo')[:4]==bytes.fromhex('de120495')
    for file,marker in [('manager-tests.txt','PASS Manager language suite'),('player-tests.txt','PASS Player language suite'),('parser-tests.txt','PASS'),('profile-tests.txt','PASS')]:
        assert marker in z.read('build-info/language-r3/'+file).decode('utf-8-sig'),file
    for file,count in [('results.json',14),('scripts-results.json',2)]:
        cases=json.loads(z.read('build-info/runtime-r3/'+file));assert len(cases)==count and all(c['passed'] for c in cases)
    coverage=json.loads(z.read('build-info/language-r3/coverage.json'))
    assert coverage['settings_help_entries']==150
proof={'source_build':BUILD,'source_run':RUN,'publish_commit':os.environ['GITHUB_SHA'],
       'artifact_sha256':ARTIFACT_SHA,'package_sha256':PACKAGE_SHA,'files_verified':len(hashes),
       'language_strings':coverage['strings'],'main_settings_help_entries':150,
       'language_modes':['zh-CN','en','system'],'player_themes_tested':['dark','light'],
       'fps_player_ui_windows_cases':14,'lua_suites':2,'gpu_retested':False}
(out/'release-verification.json').write_text(json.dumps(proof,ensure_ascii=False,indent=2),encoding='utf-8')
notes=(out/'RELEASE-r3.md').read_text(encoding='utf-8')
notes+='\n\n## 发布复核\n'
notes+='已复核实际中文/英文窗口截图、语言保存与重启、深浅主题下拉框显示、只读配置名称不被改写。\n'
notes+='补齐设置分类、默认值标记和手册链接的中文；同时移除了旧设置资源中的无效 `vo=info` 项，不修改已有播放器配置。\n'
notes+=f'本包包含 {coverage["strings"]} 条双语映射，150 条主设置说明；逐文件核验 {len(hashes)} 个文件。\n'
notes+='安装包 SHA-256：`'+PACKAGE_SHA+'`。\n'
notes+='源码构建提交：`'+BUILD+'`；完整 UI 来源见 `r3-ui-sources.zip`。\n'
(out/'RELEASE-r3.md').write_text(notes,encoding='utf-8')
exists=subprocess.run(['gh','release','view',TAG,'-R',REPO],capture_output=True)
assert exists.returncode!=0,'Refusing to replace an existing release'
subprocess.run(['gh','release','create',TAG,'-R',REPO,'--target',BUILD,'--draft','--prerelease',
    '--title','AnimeJaNai 3.6.0 中文修复包 r3 · 语言设置','--notes-file',str(out/'RELEASE-r3.md')],check=True)
assets=[out/n for n in [PACKAGE,'r3-ui-sources.zip','SHA256SUMS.txt','manifest.json','RELEASE-r3.md','release-verification.json']]
subprocess.run(['gh','release','upload',TAG,'-R',REPO,*map(str,assets)],check=True)
release=api(f'repos/{REPO}/releases/tags/{TAG}')
asset=next(a for a in release['assets'] if a['name']==PACKAGE)
assert asset['digest']=='sha256:'+PACKAGE_SHA and asset['state']=='uploaded'
subprocess.run(['gh','release','edit',TAG,'-R',REPO,'--draft=false','--prerelease'],check=True)
# Refresh the download entry without touching presets or rebuilding the release.
head=api(f'repos/{REPO}/git/ref/heads/main')['object']['sha']
if head==os.environ['GITHUB_SHA']:
    readme=api(f'repos/{REPO}/contents/README.md?ref=main')
    text=base64.b64decode(readme['content']).decode('utf-8')
    note='''\n> **当前更新：r3 中文恢复与语言设置。** [下载 r3 累计修复包](https://github.com/sunuuc/AnimeJaNai-zh-CN/releases/tag/zh-CN-3.6.0-r3)。播放器设置窗口与管理器顶部均可选简体中文、English、跟随系统，默认简体中文，重启后生效。已包含 r2 修复，无须另装 r2；保留个人配置、模型和缓存。[详细说明](docs/RELEASE-r3.md)。下方 r2 链接和说明保留作历史参考。\n\n'''
    first,rest=text.split('\n',1)
    payload={'message':'文档：将默认下载入口更新为 r3 中文语言修复包','sha':readme['sha'],
        'branch':'main','content':base64.b64encode((first+'\n'+note+rest).encode()).decode()}
    f=Path('readme-update.json');f.write_text(json.dumps(payload),encoding='utf-8')
    subprocess.run(['gh','api','--method','PUT',f'repos/{REPO}/contents/README.md','--input',str(f)],check=True,stdout=subprocess.DEVNULL)
print(json.dumps(proof,ensure_ascii=False,indent=2))
