"""Publish only the explicitly pinned, fully tested candidate without rebuilding it."""
from pathlib import Path
import hashlib,json,os,shutil,subprocess,sys,zipfile
from stage_r2 import extract
ROOT=Path(__file__).resolve().parents[1]
DIST=ROOT/'release-dist';DIST.mkdir(exist_ok=True)
REPO='sunuuc/AnimeJaNai-zh-CN';TAG='zh-CN-3.6.0-r2'
ARTIFACT_ID=os.environ['CANDIDATE_ID']
ARTIFACT_SHA=os.environ['CANDIDATE_SHA256']
PACKAGE_SHA=os.environ['PACKAGE_SHA256']
BUILD_SHA=os.environ['SOURCE_BUILD_SHA']
ARCHIVE=ROOT/'verified-candidate.zip'
with ARCHIVE.open('wb') as out:
    subprocess.run(['gh','api',f'repos/{REPO}/actions/artifacts/{ARTIFACT_ID}/zip'],stdout=out,check=True)
assert hashlib.sha256(ARCHIVE.read_bytes()).hexdigest()==ARTIFACT_SHA
extract(ARCHIVE,DIST)
package=DIST/'AnimeJaNai-3.6.0-zh-CN-r2-update.zip'
assert hashlib.sha256(package.read_bytes()).hexdigest()==PACKAGE_SHA
bundle=ROOT/'release-test';extract(package,bundle)
hashes=json.loads((bundle/'build-info/SHA256.json').read_text(encoding='utf-8'))
for n,h in hashes.items():assert hashlib.sha256((bundle/n).read_bytes()).hexdigest()==h,n
assert not any(p.suffix.lower() in ('.ttf','.otf','.ttc','.woff','.woff2') for p in bundle.rglob('*'))
for n in ('portable_config/mpv.conf','portable_config/input.conf','animejanai/animejanai.conf'):
    assert not (bundle/n).exists(),'Refusing to overwrite personal settings: '+n
provenance=json.loads((bundle/'build-info/provenance.json').read_text(encoding='utf-8'))
assert provenance['revision']==BUILD_SHA
results=json.loads((DIST/'runtime-results.json').read_text(encoding='utf-8'))
assert len(results)==14 and all(r['passed'] for r in results)
controls=json.loads((bundle/'build-info/runtime-r2/scripts-results.json').read_text(encoding='utf-8'))
assert len(controls)==2 and all(r['passed'] for r in controls)
# Exercise the exact packaged scripts once more on the publication runner.
subprocess.run([sys.executable,str(ROOT/'tests/test_script_suite.py'),str(bundle),str(DIST)],check=True,timeout=75)
assert hashlib.sha256(package.read_bytes()).hexdigest()==PACKAGE_SHA
summary={'package_sha256':PACKAGE_SHA,'files_checked':len(hashes),'runtime_cases':len(results),
         'controller_groups':controls,'publish_commit':os.environ['GITHUB_SHA'],
         'source_build_commit':BUILD_SHA,'source_build_run':provenance['run_id'],
         'gpu_tested':False,'player_ui_real_account_tested':False}
(DIST/'release-verification.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
with zipfile.ZipFile(DIST/'release-verification-sources.zip','w',zipfile.ZIP_DEFLATED) as z:
    for name in ['tests/test_controls.lua','tests/test_smoke.lua','tests/test_script_suite.py',
                 'tools/publish_r2.py','tools/stage_r2.py','.github/workflows/publish-r2.yml']:
        z.write(ROOT/name,name)
notes=(DIST/'RELEASE-r2.md').read_text(encoding='utf-8')
notes+='\n\n## 发布校验\n14 组 Windows 回归、15 项更新器回归、2 组控制脚本/真实 Lua API 回归均通过。\n'
notes+='安装包 SHA-256：`'+PACKAGE_SHA+'`\n'
notes+='源码构建提交：`'+BUILD_SHA+'`；发布复核提交：`'+os.environ['GITHUB_SHA']+'`。\n'
notes+='本修复包保留为预发布，尚未在用户的 RTX5080 与 Player UI 实际服务器上验证。\n'
(DIST/'RELEASE-r2.md').write_text(notes,encoding='utf-8')
existing=subprocess.run(['gh','api',f'repos/{REPO}/releases/tags/{TAG}'],capture_output=True)
if existing.returncode==0:
    release=json.loads(existing.stdout)
    assert release['target_commitish']==os.environ['GITHUB_SHA'],'Refusing to replace a different release'
else:
    subprocess.run(['gh','release','create',TAG,'-R',REPO,'--target',os.environ['GITHUB_SHA'],
        '--title','AnimeJaNai 3.6.0 中文修复包 r2','--draft','--prerelease',
        '--notes-file',str(DIST/'RELEASE-r2.md')],check=True)
subprocess.run(['gh','release','upload',TAG,'-R',REPO,'--clobber',
    *[str(p) for p in DIST.iterdir() if p.is_file()]],check=True)
subprocess.run(['gh','release','edit',TAG,'-R',REPO,'--draft=false','--prerelease',
    '--notes-file',str(DIST/'RELEASE-r2.md')],check=True)
print(json.dumps(summary,indent=2))
