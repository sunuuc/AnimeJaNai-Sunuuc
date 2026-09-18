"""Integrate hardware-targeted packaging without altering playback presets."""
from pathlib import Path
import json
R = Path(__file__).resolve().parents[2]

def edit(name, old, new):
    p=R/name; text=p.read_text(encoding='utf-8-sig')
    if new in text: return
    if text.count(old)!=1: raise RuntimeError('Target integration context changed: '+name+' '+old[:70])
    p.write_text(text.replace(old,new),encoding='utf-8')

build='tools/standalone/build.py'
edit(build,'FONTS={', 'from gpu_target import TARGET, prune, validate as validate_gpu_target\nFONTS={')
edit(build,"    dump(ST/'build-info/standalone/components.json',records)",
     "    records=prune(ST,records,E)\n    dump(ST/'build-info/standalone/components.json',records)")
edit(build,"'component_version':'3.6.0'", "'component_version':'3.6.0','gpu_target':TARGET")
old="       'animejanai/inference/aji_dml.dll','animejanai/inference/onnxruntime.dll','animejanai/inference/DirectML.dll',\n"
p=R/build;s=p.read_text(encoding='utf-8-sig')
if old in s:s=s.replace(old,'');p.write_text(s,encoding='utf-8')
edit(build,"for family in ('75','86','89','120'):","for family in ('120',):")
edit(build,"    dump(E/'payload.json',", "    validate_gpu_target(ST,E)\n    dump(E/'payload.json',")
edit(build,'-win-x64-full.7z\'', '-rtx5080-laptop-win-x64-full.7z\'')
edit(build,"    run(sys.executable,H/'test_complete.py',R/'clean-install',E/'fresh-install')",
     "    run(sys.executable,R/'tests/test_gpu_target.py',R/'clean-install',E/'fresh-install')\n    run(sys.executable,H/'test_complete.py',R/'clean-install',E/'fresh-install')")
edit(build,"info=ST/'build-info/standalone';cp(E,info/'validation');cp(R/'language-evidence',info/'ui-validation')",
     "info=ST/'build-info/standalone'\n    shutil.rmtree(info/'validation',ignore_errors=True)\n    shutil.rmtree(info/'ui-validation',ignore_errors=True)\n    cp(E,info/'validation');cp(R/'language-evidence',info/'ui-validation')")
complete='tools/standalone/test_complete.py'
edit(complete,"    assert data['offline'] and len(data['packs'])>=7,data",
     "    assert data['offline'] and {x['name'] for x in data['packs']}=={'trt-runtime','trt-sm120','rife'},data")

vm='src/manager/AnimeJaNaiConfEditor/ViewModels/MainWindowViewModel.cs'
edit(vm,'        public static bool TrtOnDisk() =>',
     '''        public static bool TensorRtOnly =>
            File.Exists(Path.Combine(DataDir, "inference", "gpu-target.json"));
        public bool DirectMlAvailable => !TensorRtOnly;

        public static bool TrtOnDisk() =>''')
edit(vm,'            if (trtUsable && AnimeJaNaiConf != null && AnimeJaNaiConf.DirectMlSelected &&',
     '''            if (TensorRtOnly)
            {
                if (AnimeJaNaiConf != null)
                {
                    AnimeJaNaiConf.BackendAutoFallback = false;
                    AnimeJaNaiConf.SetTensorRtSelected();
                }
                if (!trtUsable)
                    notice = AnimeJaNai.Localization.UiText.T(nvidia == false
                        ? "TensorRT requires an NVIDIA GPU."
                        : "TensorRT is not installed.");
            }
            else if (trtUsable && AnimeJaNaiConf != null && AnimeJaNaiConf.DirectMlSelected &&''')
edit(vm,'        public void UserSelectDirectMl()\n        {',
     '        public void UserSelectDirectMl()\n        {\n            if (MainWindowViewModel.TensorRtOnly) return;')
view='src/manager/AnimeJaNaiConfEditor/Views/MainWindow.axaml'
edit(view,'<ToggleButton IsChecked="{Binding AnimeJaNaiConf.DirectMlSelected}"',
     '<ToggleButton IsVisible="{Binding DirectMlAvailable}" IsChecked="{Binding AnimeJaNaiConf.DirectMlSelected}"')
edit(view,'<TextBlock Grid.Column="1" Classes="help" Margin="40,0,0,0" xml:space="preserve"><Bold>TensorRT</Bold>',
     '<TextBlock IsVisible="{Binding DirectMlAvailable}" Grid.Column="1" Classes="help" Margin="40,0,0,0" xml:space="preserve"><Bold>TensorRT</Bold>')
component='src/manager/AnimeJaNaiConfEditor/ViewModels/ComponentManagerViewModel.cs'
edit(component,'"trt-runtime" => AnimeJaNai.Localization.UiText.T("NVIDIA GPU 上最快的超分后端。未安装时，NVIDIA 用户将回退到速度更慢的 DirectML 后端。"),',
     '"trt-runtime" => MainWindowViewModel.TensorRtOnly ? "TensorRT" : AnimeJaNai.Localization.UiText.T("NVIDIA GPU 上最快的超分后端。未安装时，NVIDIA 用户将回退到速度更慢的 DirectML 后端。"),')
edit(component,': AnimeJaNai.Localization.UiText.T("GPU：未检测到 NVIDIA 设备；内置 DirectML 后端可用于 AMD 和 Intel GPU");',
     ': MainWindowViewModel.TensorRtOnly ? AnimeJaNai.Localization.UiText.T("TensorRT requires an NVIDIA GPU.") : AnimeJaNai.Localization.UiText.T("GPU：未检测到 NVIDIA 设备；内置 DirectML 后端可用于 AMD 和 Intel GPU");')
tests='tools/language-r3/ManagerTests.cs'
edit(tests,'w.Close();Dispatcher.UIThread.RunJobs();',
     '''w.Close();Dispatcher.UIThread.RunJobs();
File.WriteAllText(Path.Combine(fixture,"inference","gpu-target.json"),"{}");
var targetVm=new MainWindowViewModel();targetVm.RefreshComponentAwareness();
Check(!targetVm.DirectMlAvailable && targetVm.AnimeJaNaiConf.TensorRtSelected &&
      !targetVm.AnimeJaNaiConf.BackendAutoFallback,"target package never falls back to missing DirectML");
targetVm.AnimeJaNaiConf.UserSelectDirectMl();
Check(targetVm.AnimeJaNaiConf.TensorRtSelected && !targetVm.AnimeJaNaiConf.DirectMlSelected,
      "unavailable backend cannot be selected");''')
pub='tools/standalone/publish.py'
edit(pub,"paths += [H/'dependencies.json',H/'build.py']",
     "paths += [H/'dependencies.json',H/'build.py',H/'publish.py',H/'test_complete.py',R/'tools/language-r3/ManagerTests.cs']")
edit(pub,"head=api(f'repos/{REPO}/git/ref/heads/main')['object']['sha']",
     """for path in (E/'gpu-target.json',E/'fresh-install/gpu-target.json'):
    target=json.loads(path.read_text());assert target['passed'] and target['target']['id']=='rtx5080-laptop',path
head=api(f'repos/{REPO}/git/ref/heads/main')['object']['sha']""")
p=R/pub;s=p.read_text(encoding='utf-8')
start=s.index('# Validate the public artifact before retiring superseded downloads.' if '# Validate the public artifact before retiring superseded downloads.' in s else '# The owner requested that superseded releases no longer be distributed.')
end=s.index("dump(DIST/'publication.json'",start)
s=s[:start]+'''# Validate the public artifact before retiring superseded downloads.
import hashlib, urllib.request
public_assets=[]
for file in user_assets+[sourcezip,checksums]:
    asset=next(a for a in published['assets'] if a['name']==file.name)
    digest=hashlib.sha256();count=0
    request=urllib.request.Request(asset['browser_download_url'],headers={'User-Agent':'AnimeJaNai-release-verification'})
    with urllib.request.urlopen(request,timeout=120) as response:
        while chunk:=response.read(1024*1024):
            digest.update(chunk);count+=len(chunk)
    assert count==file.stat().st_size and digest.hexdigest()==sha(file),file.name
    public_assets.append({'name':file.name,'bytes':count,'sha256':digest.hexdigest()})
dump(DIST/'public-downloads.json',{'passed':True,'assets':public_assets})
for previous in api(f'repos/{REPO}/releases?per_page=100'):
    if not previous['draft'] and previous['tag_name'].startswith('standalone-v') and previous['tag_name']!=META['tag']:
        run('gh','release','delete',previous['tag_name'],'-R',REPO,'--yes','--cleanup-tag')
'''+s[end:]
p.write_text(s,encoding='utf-8')
p=R/'tools/standalone/dependencies.json';lock=json.loads(p.read_text(encoding='utf-8'))
lock['components']=[c for c in lock['components'] if c['id'] in ('trt-runtime','trt-sm120','rife')]
lock['gpu_target']='rtx5080-laptop'
p.write_text(json.dumps(lock,ensure_ascii=False,indent=2),encoding='utf-8')
print('RTX 5080 Laptop packaging prepared')
