"""Publish the tested full package and corresponding source tree."""
from pathlib import Path
import base64,json,os,subprocess,zipfile
from build import R,H,E,DIST,REPO,META,LOCK,FONTS,sha,dump,run,api

for line in (DIST/'SHA256SUMS.txt').read_text().splitlines():
    h,n=line.split('  ',1)
    if sha(DIST/n)!=h:raise RuntimeError('Publication checksum mismatch: '+n)
fresh=json.loads((E/'fresh-install/results.json').read_text())
assert len(fresh)==5 and all(x['passed'] for x in fresh)
for p in (E/'player_ui/results.json',E/'fresh-install/player_ui/results.json'):
    tests=json.loads(p.read_text());assert len(tests)==2 and all(t['passed'] for t in tests),p
head=api(f'repos/{REPO}/git/ref/heads/main')['object']['sha']
assert head==os.environ['GITHUB_SHA'],'Main changed during the build'
assets=json.loads((DIST/'artifacts.json').read_text())
assert assets and all(x['repo']==REPO for x in assets)
LOCK['runtime_seed']={'assets':assets,'version':META['version']}
dump(H/'dependencies.json',LOCK)
sourcezip=DIST/f'AnimeJaNai-zh-CN-{META["version"]}-sources.zip'
# Keep source rebuild inputs available after superseded downloads are removed.
temp=sourcezip.with_suffix('.pending.zip')
with zipfile.ZipFile(sourcezip) as src,zipfile.ZipFile(temp,'w',zipfile.ZIP_DEFLATED) as dst:
    for item in src.infolist():
        if item.filename!='tools/standalone/dependencies.json':dst.writestr(item,src.read(item.filename))
    dst.write(H/'dependencies.json','tools/standalone/dependencies.json')
    dst.write(R/'README.md','README.md')
    dst.write(R/'.github/workflows/standalone.yml','.github/workflows/standalone.yml')
temp.replace(sourcezip)
user_assets=[DIST/x['name'] for x in assets]
checksums=DIST/'SHA256SUMS.txt'
checksums.write_text(''.join(sha(p)+'  '+p.name+'\n' for p in user_assets+[sourcezip]),encoding='utf-8')
paths=[p for p in (R/'src').rglob('*') if p.is_file() and not any(x in ('bin','obj','.git') for x in p.relative_to(R/'src').parts)]
paths += [p for p in (R/'portable_config').rglob('*') if p.is_file()]
paths += [H/'dependencies.json',H/'build.py']
tree=[]
for p in paths:
    assert p.suffix.lower() not in FONTS|{'.exe','.dll'},p
    entry={'path':p.relative_to(R).as_posix(),'mode':'100644','type':'blob'};raw=p.read_bytes()
    try:entry['content']=raw.decode('utf-8')
    except UnicodeDecodeError:entry['sha']=api(f'repos/{REPO}/git/blobs',{'content':base64.b64encode(raw).decode(),'encoding':'base64'})['sha']
    tree.append(entry)
tracked=set(subprocess.check_output(['git','ls-files'],text=True).splitlines())
for name in ('portable_config/scripts/modernx.lua','portable_config/script-opts/modernx.conf'):
    if name in tracked:tree.append({'path':name,'mode':'100644','type':'blob','sha':None})
base_tree=api(f'repos/{REPO}/git/commits/{head}')['tree']['sha']
newtree=api(f'repos/{REPO}/git/trees',{'base_tree':base_tree,'tree':tree})['sha']
commit=api(f'repos/{REPO}/git/commits',{'message':f'Release {META["version"]} sources','tree':newtree,'parents':[head]})['sha']
old=[r for r in api(f'repos/{REPO}/releases?per_page=100') if r['tag_name']==META['tag']]
assert not old,'Release tag already exists; refusing to overwrite'
notes=(DIST/'RELEASE.md').read_text(encoding='utf-8')
rel=api(f'repos/{REPO}/releases',{'tag_name':META['tag'],'target_commitish':commit,'name':f'AnimeJaNai-zh-CN {META["version"]}','body':notes,'draft':True,'prerelease':META['prerelease']})
run('gh','release','upload',META['tag'],'-R',REPO,*user_assets,sourcezip,checksums)
uploaded=api(f'repos/{REPO}/releases/{rel["id"]}')
for p in user_assets+[sourcezip,checksums]:
    a=next(x for x in uploaded['assets'] if x['name']==p.name)
    assert a.get('digest')=='sha256:'+sha(p) and a['state']=='uploaded'
assert {a['name'] for a in uploaded['assets']}=={p.name for p in user_assets+[sourcezip,checksums]}
api(f'repos/{REPO}/git/refs/heads/main',{'sha':commit,'force':False},'PATCH')
api(f'repos/{REPO}/releases/{rel["id"]}',{'draft':False},'PATCH')
published=api(f'repos/{REPO}/releases/tags/{META["tag"]}');assert published['id']==rel['id'] and not published['draft']
# The owner requested that superseded releases no longer be distributed.
for previous in api(f'repos/{REPO}/releases?per_page=100'):
    if previous['tag_name']=='standalone-v1.0.1' and META['tag']=='standalone-v1.1.0':
        run('gh','release','delete',previous['tag_name'],'-R',REPO,'--yes','--cleanup-tag')
dump(DIST/'publication.json',{'release_id':rel['id'],'source_commit':commit,'build_commit':head,'tag':META['tag'],'assets':assets})
print('PUBLISHED',META['tag'],commit)
