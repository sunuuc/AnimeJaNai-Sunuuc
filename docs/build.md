# mpv-AnimeVE 构建

## GitHub Actions

在 Actions 中选择 **Standalone complete portable release**，点击 **Run workflow**。`publish` 控制是否上传正式发行包；关闭时输出构建产物。

## 本地编译

需要 Windows x64、Git、Python 3.14、.NET SDK 10、7-Zip 和 GitHub CLI。在仓库根目录执行：

```powershell
python tools/standalone/build.py prepare
$version = (Get-Content release.json | ConvertFrom-Json).version
dotnet publish player/src/MpvNet.Windows/MpvNet.Windows.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=false -p:InformationalVersion=$version -o publish-player
dotnet publish manager/AnimeJaNaiConfEditor/AnimeJaNaiConfEditor.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=false -p:InformationalVersion=$version -o publish-manager
dotnet publish tools/standalone/Updater.csproj -c Release -o publish-updater
python tools/standalone/build.py stage
```

`stage` 目录为组装后的程序。构建脚本会下载并校验固定版本的依赖，编译 DanmakuFactory 和 libass，生成可选组件目录及独立模型包。

完整发行还需运行工作流中的扫描、回归及空目录安装检查，然后执行 `build.py package` 和 `publish.py`。步骤顺序见[构建工作流](https://github.com/sunuuc/mpv-AnimeVE/blob/main/.github/workflows/standalone.yml)。

## 源码与记录

- `src/player`：mpv.net 播放器前端。
- `src/manager`：配置与组件管理器。
- `portable_config`：播放脚本和默认配置。
- `third_party/danmaku-factory`、`third_party/libass`：随包编译的修改源码。
- `tools/standalone`：依赖、编译、打包与发布工具。
- `app/build-info/standalone`：发行包中的构建来源、文件校验值与验证报告。

发布说明从 `CHANGELOG.md` 中提取与 `release.json` 版本对应的条目。
