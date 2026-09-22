# mpvapp 本地构建记录

构建时间：2026-09-19 12:19–12:25 (GMT+8)
源码版本：`sunuuc/AnimeJaNai-zh-CN` @ `main` = `7e397bcd2069cb6019fe00978326e9d95db69ba2`
产出目录：`D:\CODE\AnimeJaNai-zh-CN\mpvapp\`（1.87 GB / 324 文件）

---

## 1. 使用的工具链

| 工具 | 实际路径 | 说明 |
|---|---|---|
| .NET SDK | `D:\SDK\dotnet.exe`，**10.0.100** | ⚠️ `C:\Program Files\dotnet\sdk\10.0.301` 存在但**是空目录**，所以 `dotnet --list-sdks` 报 “No SDKs were found”。环境变量 `DOTNET_ROOT=D:\SDK` 才是有效的那份。 |
| Python | `C:\Users\howev\.workbuddy\binaries\python\versions\3.13.12\python.exe`（实际 3.13.14） | 跑项目自带的预处理脚本 |
| 7-Zip | `D:\Apps\7-Zip\7z.exe` | 本次未用到（未走 `build.py package`） |
| NuGet | 走 Clash 代理 `http://127.0.0.1:7890` | 直连 nuget.org 不可用 |

---

## 2. 编译前预处理（项目自带脚本，与 CI 同序）

```
python tools/standalone/prepare_playback.py     → Playback source updates ready
python tools/standalone/inline_player_ui_modules.py → Player UI runtime modules inlined for Unicode-safe portable paths
python tools/standalone/prepare_gpu_target.py   → RTX 5080 Laptop packaging prepared
python tools/standalone/prepare_startup.py      → Standalone startup sources prepared
```

这四步会**就地修改受版本控制的源码**（`Player.cs` / `App.cs` / `Program.cs` / `CommandLine.cs` / Lua / Manager 的 `MainWindowViewModel.cs` 等），这正是 CI 的做法。构建完成后已用 `git restore .` 把工作树还原到 `origin/main`，仓库保持干净。

---

## 3. 编译产物（本次真正编译的三个）

| 文件 | 大小 | InformationalVersion |
|---|---|---|
| `mpvnet.exe` | 174,832,059 | `7.1.2.0-sunuuc-full-1.1.6+7e397bcd2069cb6019fe00978326e9d95db69ba2` |
| `AnimeJaNaiManager.exe` | 117,990,338 | `0.6.0-sunuuc-full-1.1.6+7e397bcd2069cb6019fe00978326e9d95db69ba2` |
| `AnimeJaNaiUpdater.exe` | 73,997,978 | `1.0.0+7e397bcd2069cb6019fe00978326e9d95db69ba2` |

命令（等价于 `standalone.yml` 里的 `dotnet publish`，只是路径直接指向 `src/`）：

```
dotnet publish src/player/src/MpvNet.Windows/MpvNet.Windows.csproj -c Release -r win-x64 ^
  --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true ^
  -p:InformationalVersion=7.1.2.0-sunuuc-full-1.1.6 -o publish-player

dotnet publish src/manager/AnimeJaNaiConfEditor/AnimeJaNaiConfEditor.csproj -c Release -r win-x64 ^
  --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true ^
  -p:InformationalVersion=0.6.0-sunuuc-full-1.1.6 -o publish-manager

dotnet publish tools/standalone/Updater.csproj -c Release -o publish-updater
```

`+7e397bcd…` 是 SDK 自动附加的源码版本，等于把来源 commit 烙进了二进制。

> 中途遇到过一次 `error : Access to the path '...\hypertext.avalonia\11.0.0-rc1\HyperText.Avalonia.nuspec' is denied`，
> 删除那个损坏的包缓存后重新编译即通过。

---

## 4. 未由本仓库编译、从既有安装复制的部分

| 文件 | 来源 | 说明 |
|---|---|---|
| `mpv.exe` | `D:\Apps\mpv-AnimeJaNai\` | 版本 `v0.41.0-dev-gd4c06dd34-dirty` → 正是 `the-database/mpv` 的 pinned commit `d4c06dd3`，`-dirty` 表示已打上 `tools/apply_native_r2.py` 的 `vo-presented-frame-count` 补丁 |
| `libmpv-2.dll` | 同上 | 20,372,242 字节 |
| 其余 158 个 DLL + `mpv.com` / `mpvnet.com` / `MediaInfo.dll` / `yt-dlp.exe` | 同上 | ffmpeg、Skia、HarfBuzz、Vulkan、MSVC 运行库等 |
| `animejanai/{inference,onnx,rife}` | 同上 | 1.29 GB，TensorRT 运行库 / SM120 内核 / 超分与 RIFE 模型 |
| `portable_config/shaders/`、`portable_config/mpv-animejanai.conf` | 同上 | **本仓库里没有这两个**，但 `mpv.conf` 与 `input.conf` 会引用它们 |
| `build-info/standalone/components.json` | 同上 | `AnimeJaNaiUpdater.exe --components` 需要它 |

这与审计结论一致：**本仓库的发布链路不编译原生 mpv**，`mpv.exe` / `libmpv-2.dll` 始终来自预构建包。

来自本仓库的则是 `portable_config/`（打了 Player UI 内联等补丁的版本）、`animejanai/animejanai.conf`（9 档中文预设）、`LICENSE`、`THIRD_PARTY_LICENSES/`、`docs/standalone.md`。

---

## 5. 组装与清理

**合并顺序**（顺序有意义）：
1. 先铺安装版的 `portable_config` —— 拿到本仓库缺失的 `shaders/` 与 `mpv-animejanai.conf`
2. 再用本仓库的 `portable_config` 覆盖 —— 拿到打过补丁的 `player_ui.lua`、`input.conf`、`mpv.conf`
3. `animejanai/` 铺安装版的 `inference|onnx|rife`，但 `animejanai.conf` 用本仓库的

**已从 mpvapp 中剔除**（保证「只保存编译好的应用」）：

- `*.pdb`（调试符号）
- `portable_config/{cache,watch_later}`、`settings.xml`、`input.conf.backup`
- `portable_config/{startup,playback}-diagnostic.json`
- `build-info/standalone/{validation,ui-validation}`（CI 证据：48 个日志 + 界面截图）
- `animejanai/benchmarks/`

**保留**：`animejanai/rife/` 下 2 个 TensorRT 引擎构建日志（各约 10 KB，属于模型目录元数据，记录引擎是按 RTX 5080 Laptop / TRT 11.1.0 / sm12 构建的）。mpvapp 内无 `bin` / `obj` / `*.pdb`。

构建中间产物已全部删除：`publish-player/`、`publish-manager/`、`publish-updater/`，以及全仓库的 4 个 `bin`/`obj` 目录。`git restore .` 后工作树无任何修改。

---

## 6. 验证结果

| 验证 | 结果 |
|---|---|
| 重建 `build-info/standalone/SHA256.json`（321 条） | 完成 |
| `AnimeJaNaiUpdater.exe --verify` | **`{"ok":true,"failed":[]}`** —— 321 个文件逐一哈希匹配 |
| `AnimeJaNaiUpdater.exe --components --json` | `NVIDIA GeForce RTX 5080 Laptop GPU`、`nvidia:true`；`trt-runtime`(437 MB)/`trt-sm120`(263 MB)/`rife`(506 MB) 均 `installed:true`、`offline:true`、`distribution:full-portable` |
| 启动后 `portable_config/startup-diagnostic.json` | `version:3`，`phases=[process-started, native-initialized, external-handoff-ready]`，**`configuration: "portable"`**，`native_initialized:true`，`option_error:null` |
| `portable_config/playback-diagnostic.json` | 由 `network_playback.lua` 正常写出，`phase:"idle"` |
| 进程 | `mpvnet.exe` pid 44796，窗口标题 `mpv.net`，约 464 MB 常驻 |

`startup-diagnostic.json` 里 `phases` 齐全 + `configuration: portable`，说明这份二进制确实带上了 `prepare_startup.py` 注入的 `StartupDiagnostics` 与 `config-dir` 修复，并且正确识别到 `mpvapp\portable_config`。

---

## 7. 已知限制

1. **AI 推理未实机验证。** 本次只做到「程序能起、配置能读、组件能识别」。TensorRT 实际出帧需要显卡驱动在位，并在首次使用时为每个模型/分辨率构建引擎（会暂停播放，日志会出现 `Building TensorRT engine`）。
2. **`mpv.exe` / `libmpv-2.dll` 不是本次编译的**，是既有安装里的原生运行时。
3. **`mpvapp/mpvnet.exe` 与 1.1.5 发布包里的同名文件哈希不同** —— 这是重新编译的正常结果，不是校验失败。`SHA256.json` 已按 mpvapp 的**实际内容**重建，所以 `--verify` 通过。
4. **工作区新增了两个未跟踪文件**：`docs/AUDIT-phase1.md`、`docs/BUILD-mpvapp.md`，以及新增的 `.gitignore`（内容为 `/mpvapp/` 与 `/.workbuddy/`，防止 1.87 GB 的 mpvapp 被误提交）。三者都未提交。
5. 启动 GUI 程序时，从沙箱命令行 `Start-Process` 出来的进程会在命令结束时被宿主连带终止；本次改用 Explorer 代理启动才让 `mpvnet.exe` 独立存活。

---

*本文件为构建记录，未修改任何现有源码，未创建 commit，未创建 Release。*
