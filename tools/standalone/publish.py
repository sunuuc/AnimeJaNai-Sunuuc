"""Publish a verified full archive and atomically save the sources used to build it.
Text files use a single Git tree request; only binary UI artwork needs blob uploads.
"""
from pathlib import Path
import base64,json,os
from build import R,H,E,DIST,REPO,META,LOCK,FONTS,sha,dump,run,api

for line in (DIST/'SHA256SUMS.txt').read_text().splitlines():
    h,n=line.split('  ',1)
    if sha(DIST/n)!=h:raise RuntimeError('Publication checksum mismatch: '+n)
fresh=json.loads((E/'fresh-install/results.json').read_text())
assert len(fresh)==5 and all(x['passed'] for x in fresh)
head=api(f'repos/{REPO}/git/ref/heads/main')['object']['sha']
assert head==os.environ['GITHUB_SHA'],'Main changed during the build'
assets=json.loads((DIST/'artifacts.json').read_text())
assert assets and all(x['repo']==REPO for x in assets)
LOCK['runtime_seed']={'assets':assets,'version':META['version']}
dump(H/'dependencies.json',LOCK)
paths=[p for p in (R/'src').rglob('*') if p.is_file() and not any(x in ('bin','obj','.git') for x in p.relative_to(R/'src').parts)]
paths+=[H/'dependencies.json']
tree=[]
for p in paths:
    assert p.suffix.lower() not in FONTS|{'.exe','.dll'},p
    entry={'path':p.relative_to(R).as_posix(),'mode':'100644','type':'blob'}
    raw=p.read_bytes()
    try:entry['content']=raw.decode('utf-8')
    except UnicodeDecodeError:
        entry['sha']=api(f'repos/{REPO}/git/blobs',{'content':base64.b64encode(raw).decode(),'encoding':'base64'})['sha']
    tree.append(entry)
base_tree=api(f'repos/{REPO}/git/commits/{head}')['tree']['sha']
newtree=api(f'repos/{REPO}/git/trees',{'base_tree':base_tree,'tree':tree})['sha']
commit=api(f'repos/{REPO}/git/commits',{'message':'完整便携版：保存已验证 UI 源码与本仓库运行库种子，切换完整包下载入口','tree':newtree,'parents':[head]})['sha']
old=[r for r in api(f'repos/{REPO}/releases?per_page=100') if r['tag_name']==META['tag']]
assert not old,'Release tag already exists; refusing to overwrite'
notes=(DIST/'RELEASE.md').read_text(encoding='utf-8')+'\n\n构建提交：`'+head+'`；本次保存的完整 UI 源码提交：`'+commit+'`。\n'
rel=api(f'repos/{REPO}/releases',{'tag_name':META['tag'],'target_commitish':commit,'name':f'AnimeJaNai-zh-CN {META["version"]} 完整便携版','body':notes,'draft':True,'prerelease':META['prerelease']})
run('gh','release','upload',META['tag'],'-R',REPO,*[p for p in DIST.iterdir() if p.is_file()])
uploaded=api(f'repos/{REPO}/releases/{rel["id"]}')
for item in assets:
    found=next(a for a in uploaded['assets'] if a['name']==item['name'])
    assert found.get('digest')=='sha256:'+item['sha256'] and found['state']=='uploaded'
api(f'repos/{REPO}/git/refs/heads/main',{'sha':commit,'force':False},'PATCH')
api(f'repos/{REPO}/releases/{rel["id"]}',{'draft':False},'PATCH')
dump(DIST/'publication.json',{'release_id':rel['id'],'source_commit':commit,'build_commit':head,'tag':META['tag'],'assets':assets})
print('PUBLISHED FULL PORTABLE',META['tag'],commit)
