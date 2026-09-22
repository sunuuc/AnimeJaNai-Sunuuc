# AnimeJaNai-zh-CN 第一阶段项目审计

审计对象：`sunuuc/AnimeJaNai-zh-CN`
审计时间：2026-09-19
审计依据：本仓库实际文件内容（本机工作副本）、GitHub 上各仓库的实际分支/Release 资产、workflow YAML、`tools/standalone/*.py`、C# 源码、`.conf` / `.lua`。未修改任何代码，未创建 commit，未创建 Release。

---

## 0.0 版本锚定与可信度自查（2026-09-19 补做）

本机工作副本不是 git 克隆（无 `.git`，环境无 git/7z）。为排除「读到的是过时副本」这一风险，用 GitHub API 取 `main` 的递归 tree，对每个 blob 计算 **git blob SHA1**，与本地同路径文件逐个比对：

| 检查项 | 结果 |
|---|---|
| GitHub `main` HEAD | `7e397bcd2069cb6019fe00978326e9d95db69ba2`，2026-09-18T14:56:48Z |
| GitHub tree（recursive，非截断）blob 数 | 314 |
| 本地文件数 | 315 |
| **内容逐字节相同** | **314 / 314** |
| 仅本地存在 | 1 个 —— `docs/AUDIT-phase1.md`（本次审计新增） |
| 仅 GitHub 存在 / 本地缺失 | 0 |
| 内容不同 | 0 |

**结论：本地副本与 GitHub `main` HEAD 完全一致，不存在过时文件。** 本报告所有对仓库自身文件的引用都等价于引用 `main@7e397bcd`。

### 0.0.1 工作目录已改为真正的 git 工作副本（2026-09-19 追加）

原来该目录**没有 `.git`**，是一个脱离版本控制的裸文件副本。现已改为真实 git 工作副本：

| 项目 | 值 |
|---|---|
| `remote.origin.url` | `https://github.com/sunuuc/AnimeJaNai-zh-CN.git` |
| `HEAD` | `7e397bcd2069cb6019fe00978326e9d95db69ba2` |
| `origin/main` | `7e397bcd2069cb6019fe00978326e9d95db69ba2`（与 HEAD 一致） |
| 领先/落后 | `0 / 0` |
| 已跟踪文件 | 314 |
| 工作树状态 | 无任何修改；仅 2 项未跟踪：`.workbuddy/`、`docs/AUDIT-phase1.md` |
| 可用分支 | `main`、`remotes/origin/source`、`remotes/origin/fix/playlist-1.1.6` |
| 可用 tag | `standalone-v1.1.5` |
| 仓库体积 | `size-pack: 240.66 MiB`（含 ONNX 模型与完整历史） |

**`git status` 无修改这一事实，本身就是「工作树 == GitHub `main`」的第二重独立验证**（第一重是 blob SHA 比对，第三重是 codeload 归档比对）。

> 环境注意：本机 `github.com` 直连不可达，且沙箱代理对 `github.com` 返回 `502`；PortableGit 的 `exec-path` 里缺少远程传输助手。实际可用的组合是
> `GIT_EXEC_PATH=<PortableGit>\mingw64\bin` + 用户本机 Clash 代理 `http://127.0.0.1:7890`。


### 各结论的证据等级（区分开，避免把推断当事实）

| 等级 | 含义 | 本报告中对应内容 |
|---|---|---|
| **A. 直接核对** | 本地文件内容 == GitHub `main@7e397bcd`，或直接读取了 GitHub 仓库/分支/Release 页面 | 目录结构、workflow 内容、`dependencies.json`、Lua/C# 源码、`animejanai.conf`、上游各仓库的元信息与分支状态 |
| **B. 代码阅读推断** | 读取构建脚本逻辑得出，**未下载 Release 包实际验证** | 「`mpv.exe`/`libmpv-2.dll` 来自 seed」「组件包内的文件布局」「首次 bootstrap 会拉 `the-database/mpv-AnimeJaNai` 3.6.0」。这类结论来自 `tools/standalone/*.py` 的下载 URL 与解包逻辑，逻辑上成立，但**包内实际内容未经开箱验证** |
| **C. 未验证** | 仅有引用痕迹 | `zh-CN-3.6.0-r4` 资产的实际存在性（该 tag 的 release 页面当前已看不到，仅 sha256 与 `build-ui-r2.yml` 的旧链接可作旁证） |

---

## 0. 核心结论（先看这三条）

1. **这个仓库不是一个「完整独立播放器源码仓」，而是一个「发行版装配仓 + 前缀补丁仓」。**
   它自有的代码 = 中文界面层 + Player UI 控制栏 + 装配/校验流水线（`tools/standalone`）+ 回归测试 + 一处 C# 命令行解析/启动顺序补丁。
   播放器二进制分成两半：**mpvnet.exe 由本仓库编译**，**mpv.exe / libmpv-2.dll 不由本仓库编译**。

2. **真正的「独立」已经通过自举实现，但根仍然扎在 AnimeJaNai 上。**
   `tools/standalone/dependencies.json` 的 `runtime_seed` 指向**本项目自己的** `standalone-v1.1.5` 完整包；只有当 `runtime_seed` 缺失时才会回退到 `the-database/mpv-AnimeJaNai` 的 3.6.0 包。也就是说：**从 1.1.5 起是自举的，但 1.1.5 本身派生自 AnimeJaNai 3.6.0。**

3. **`build-native-counter.yml` 能真正从上游源码编译 mpv，但它的产物没有接入主流水线。**
   主流水线 `standalone.yml` 不构建原生 mpv，直接吃 seed 里的 `mpv.exe`。所以「本仓库能自己造 mpv」目前是**能力存在、链路未通**。

---

## A. 仓库关系图

### A.1 依赖来源分类

```
sunuuc/AnimeJaNai-zh-CN  (main / source / fix/playlist-1.1.6)
│
├─ 本项目自己维护 ─────────────────────────────
│   ├─ portable_config/scripts/player_ui*.lua            自研 Player UI 控制栏（无上游仓库）
│   ├─ portable_config/script-modules/player_ui_*.lua     自研（被 inline 进 player_ui.lua）
│   ├─ portable_config/scripts/network_playback.lua   自研（播放策略 + 诊断）
│   ├─ portable_config/scripts/animejanaistats.lua    自研（Ctrl+J 实际 FPS/状态）
│   ├─ portable_config/scripts/animejanai_slot.lua    自研（AI 档位唯一控制器）
│   ├─ portable_config/{input,input-animejanai,mpv}.conf 自研中文重写
│   ├─ animejanai/animejanai.conf                    自研 9 档预设（1 补帧2×…9 3×补帧+2K）
│   ├─ src/manager/**                                中文管理器（fork 后再本地化）
│   ├─ tools/standalone/**                           完整包装配/校验/发布
│   ├─ tools/language-r3/**                          双语资源生成
│   ├─ tools/apply_native_r2.py                      原生 mpv 补丁（补丁自研，目标仓库上游）
│   ├─ tests/**                                      回归测试
│   └─ ScopedCommandLine.cs / CommandLine.cs 片段     外部参数作用域修复
│
├─ 继承自 AnimeJaNai 原项目 ────────────────────
│   ├─ src/player/src/MpvNet.Windows/**              mpv.net 外壳（上游 GPL-2.0）
│   ├─ portable_config/scripts/animejanai_backend.lua 来自 mpv-AnimeJaNai 包（本地中文化）
│   ├─ portable_config/scripts/animejanai_session.lua 已被改写成惰性兼容文件
│   ├─ portable_config/scripts/animejanai_engine_monitor.lua 同上（r4 退休）
│   ├─ portable_config/mpv-animejanai.conf          ⚠ 本仓库没有，来自 AnimeJaNai 包
│   └─ portable_config/shaders/*.hook               ⚠ 本仓库没有，来自 AnimeJaNai 包
│
├─ mpv 上游（间接，经 the-database/mpv）────────
│   └─ mpv.exe / libmpv-2.dll / vf_animejanai / vo-presented-frame-count
│
├─ mpv.net 上游 ───────────────────────────────
│   └─ mpvnet-player/mpv.net v7.1.2.0（GPL-2.0）
│
├─ 第三方 Lua / UI ────────────────────────────
│   └─ po5/thumbfast（MPL-2.0）
│   └─ cyl0/ModernX（已在本发行版中被删除，见 §F）
│
└─ AI / 超分 / 补帧组件 ───────────────────────
    ├─ the-database/animejanai-inference  → aji.dll / aji_trt.dll（strict C ABI）
    ├─ NVIDIA TensorRT 11.1.0.106（含 SM120 builder resource、trtexec）
    ├─ NVIDIA CUDA 13.3.29（cudart64_13.dll）
    ├─ 超分 ONNX（2x_AnimeJaNai V3.1 / SD V1beta34 等）
    └─ RIFE ONNX（rife_v4.26 等）
```

### A.2 各组件从哪里来、到哪里去

| 层 | 产物 | 来源 | 落到包里的位置 |
|---|---|---|---|
| 前端外壳 | `mpvnet.exe` + `libmpvnet.dll` 等 | **本仓库编译** `src/player`（基于 mpv.net 7.1.2.0） | 包根目录 |
| 播放核心 | `mpv.exe`、`libmpv-2.dll` | **不由本仓库编译**；来自 `runtime_seed`（本项目 1.1.5 包）或 `bootstrap_core`（mpv-AnimeJaNai 3.6.0） | 包根目录 |
| 播放核心源码 | C（mpv fork） | `the-database/mpv`（+ `the-database/libass`） | 仅在 `build-native-counter.yml` 里出现，**产物未接入主链路** |
| AI 推理桥 | `aji.dll`、`aji_trt.dll` | `the-database/animejanai-inference` 编译产物，随 AnimeJaNai 组件包分发 | `animejanai/inference/` |
| AI 后端 | `nvinfer_11.dll`、`nvinfer_plugin_11.dll`、`nvonnxparser_11.dll`、`nvinfer_builder_resource_sm120_11.dll`、`cudart64_13.dll`、`trtexec.exe` | NVIDIA TensorRT / CUDA 官方安装包（经 AnimeJaNai 组件包 → 本项目 seed） | `animejanai/inference/` |
| 超分模型 | `*.onnx` | AnimeJaNai 分发 | `animejanai/onnx/` |
| 补帧模型 | `rife_vX.Y[_lite][_ensemble].onnx` | AnimeJaNai 分发 | `animejanai/rife/` |
| AI 预设 | `animejanai.conf` | **本仓库** | `animejanai/animejanai.conf` |
| 控制栏 UI | `player_ui.lua` 等 | **本仓库** | `portable_config/scripts/` |
| 缩略图 | `thumbfast.lua` + `.conf` | `po5/thumbfast` + 本项目补丁 | `portable_config/scripts/` |
| 配置管理器 | `AnimeJaNaiManager.exe` | **本仓库编译** `src/manager`（fork 自 `sunuuc/AnimeJaNaiManager` ← `the-database/AnimeJaNaiManager`） | 包根目录 |
| 组件检查器 | `AnimeJaNaiUpdater.exe` | **本仓库** `tools/standalone/Updater.cs` | 包根目录 |
| 中文资源 | `LanguageStrings.json`（内嵌）+ `Locale/zh-CN/LC_MESSAGES/mpvnet.mo` | **本仓库** `tools/language-r3` | 编入 exe / 包根 `Locale/` |

### A.3 运行时实际调用关系

```
mpvnet.exe
  └─ libmpvnet.dll → libmpv-2.dll(原生) ── mpv 引擎
                                          ├─ portable_config/mpv.conf
                                          │    └─ include="~~/mpv-animejanai.conf"  ← 来自 AnimeJaNai 包
                                          │    └─ profile=animejanai
                                          ├─ portable_config/scripts/*.lua  (自动加载)
                                          ├─ vf: animejanai(label=aji)
                                          │    └─ lib=~~/../animejanai/inference/aji.dll
                                          │         └─ aji_trt.dll → TensorRT → nvinfer_11.dll
                                          │              └─ nvinfer_builder_resource_sm120_11.dll (仅 SM120)
                                          │              └─ cudart64_13.dll → NVIDIA 驱动
                                          └─ vo: gpu-api=vulkan (TensorRT 路径) / d3d11 (DirectML 路径，本包已裁剪)
```

---

## B. 本仓库完整目录结构

### B.1 顶层

| 路径 | 职责 |
|---|---|
| `.github/workflows/` | 11 个 workflow。**只有这一层会被 GitHub Actions 执行**。其中真正的发布流水线是 `standalone.yml` |
| `release.json` | 全局版本锚点：`version=1.1.6`、`tag=standalone-v1.1.6`、`format=full-portable`、`gpu_target=rtx5080-laptop`。被 `build.py` 读取写入 manifest 与产物名 |
| `animejanai/animejanai.conf` | 9 个 AI 预设。`[global] backend=TensorRT`、`default_slot=1`；`[slot_N]` 定义 chain/model/RIFE |
| `portable_config/` | 播放器配置与 Lua 全集（详见 B.2） |
| `src/player/` | mpv.net 7.1.2.0 fork 完整源码（GPL-2.0）。⚠️ 与 `source` 分支**并非等价**，见下方「src/player 与 source 分支的关系」 |
| `src/manager/` | 中文 AnimeJaNai Manager（Avalonia/.NET 10）源码，含 `ChineseLocalization.cs`、`ManagerLanguage.cs`、`LanguageStrings.json` |
| `docs/` | `standalone.md`（1.1.6 发行说明）、`RELEASE-r2.md` / `RELEASE-r3.md` / `RELEASE-r4.md`（历史覆盖包说明） |
| `tests/` | 10 个 `.py` + 5 个 `.lua` 回归/冒烟测试 |
| `tools/` | 装配与发布脚本（详见 B.3） |
| `THIRD_PARTY_LICENSES/` | `AnimeJaNaiManager-GPL-3.0.txt`、`mpv.net-LICENSE.txt`、`thumbfast-LICENSE.txt` |
| `LICENSE` | 本项目许可证（GPL 系，与包含的 GPL 组件一致） |

### B.1.1 `src/player/` 与 `source` 分支的关系（实测修正）

用 git blob SHA1 逐文件比对 `src/player/`（187 个文件）与 `source@23946b4e`（182 个 blob）：

| 检查项 | 结果 |
|---|---|
| `source` 分支 HEAD | `23946b4e9fefc8cef0d57b6c10131b47af5ace38`，2026-09-14T07:08:28Z（比 `main` 早 4 天） |
| 换行符归一化后内容 | **全部相同**（抽样 8 个文件：`ScopedCommandLine.cs` / `CommandLine.cs` / `Player.cs` / `App.cs` / `Program.cs` / `tests/ScopedCommandLine/Program.cs` / `docs/manual.md` / `lang/po/zh_CN.po`，归一化后哈希全部一致） |
| 原始字节 | **全部不同** —— `main`/本地存 CRLF，`source` 分支存 LF。这是 `.gitattributes`/`autocrlf` 造成的，**不是内容差异** |
| `source` 分支**缺失**的 5 个文件 | `src/MpvNet/InterfaceLanguage.cs`、`src/MpvNet/LanguageStrings.json`、`src/MpvNet/UiText.cs`、`src/MpvNet/StartupDiagnostics.cs`、`src/MpvNet.Windows/WPF/PlayerLanguage.cs` |

**所以准确表述是：** `src/player/` = `source@23946b4e` 的源码 **+ 之后追加的中文界面层文件**（这些文件由 `tools/language-r3/` 那套工具生成，`tools/language-r3/` 里存有 `InterfaceLanguage.cs` / `PlayerLanguage.cs` / `UiText.cs` / `ManagerLanguage.cs` / `Rewriter.cs` 的同名副本），并且换了行尾。`source` 分支**没有**随后同步这些文件。

> ⚠️ 注意影响面：`build-ui-r2.yml` 把 player 源码 pin 在 `ref: 23946b4e`（即 `source` 分支），而该版本**不含**上述中文界面文件。`standalone.yml` 不用这个 pin，它在 `build.py::prepare` 阶段直接用本仓库 `src/player`（含中文层），所以当前发布链路不受影响；但 `build-ui-r2.yml` 这条历史链路与当前源码已不一致。

### B.2 `portable_config/`

| 文件 | 职责 |
|---|---|
| `mpv.conf` | 入口配置：`include="~~/mpv-animejanai.conf"`、`profile=animejanai`、`osc=no`（因为用 Player UI 代替）、`border=no`、`prefetch-playlist=no`、`demuxer-cache-wait=no`、`network-timeout=20` |
| `input.conf` | 中文快捷键与右键菜单。包含 `#@ANIMEJANAI-MANAGED-BEGIN/END` 托管区块；`Ctrl+0..9` → `script-message aji-slot N`；`Ctrl+j` → `show_animejanai_stats`；`Ctrl+e` → 启动 Manager |
| `input-animejanai.conf` | 同上，作为托管区块的刷新源 |
| `script-opts/player_ui.conf` | Player UI 参数：`ui_scale=0.70`、`hide_timeout=2.5`、`network_speed=yes` |
| `script-opts/thumbfast.conf` | thumbfast 参数：`max_height=360`、`max_width=560`、`network=no`、`quit_after_inactivity=15`、`overlay_id=42` |
| `scripts/player_ui.lua` | **控制栏主控制器**（自研）。ASS overlay 绘制，矢量图标 + 系统字体；底部按钮/进度/音量/标题/网络速度 |
| `scripts/player_ui_danmaku.lua` | 弹幕（本地 XML，与字幕独立；自动加载同名 XML） |
| `scripts/animejanai_slot.lua` | **AI 档位唯一控制器**（自研）。创建/修改 `vf` 中的 `animejanai` 滤镜、`vf-command slot N`、引擎构建期间暂停、旧 input.conf 危险组合的运行时修复 |
| `scripts/animejanai_backend.lua` | 来自 AnimeJaNai 包（中文化）。按 `backend` 对齐 `hwdec`（TensorRT→nvdec/vulkan，DirectML→d3d11va/d3d11）、应用 `subs-gpu` profile、组件缺失提示 |
| `scripts/animejanai_session.lua` | **r4 起为惰性空文件**，仅用于覆盖旧安装里的 vf observer |
| `scripts/animejanai_engine_monitor.lua` | 同上（r4 退休） |
| `scripts/animejanaistats.lua` | Ctrl+J 面板：用原生 `vo-presented-frame-count` + 真实时钟算实际 FPS，读取 AI 状态日志 |
| `scripts/network_playback.lua` | 网络播放策略：`sub-auto=no`、`ytdl=no`、缓存上限、`http_multiple=0`；写 `playback-diagnostic.json`；HTTP 401/403/404 中文提示 |
| `scripts/thumbfast.lua` | `po5/thumbfast`，本仓库打了两处补丁（见 §F） |
| `script-modules/player_ui_core.lua` | 纯函数（排版/截断/时间/速率/标题/safe-apply），被 `inline_player_ui_modules.py` 内联进 `player_ui.lua` |
| `script-modules/player_ui_menu.lua` | 菜单状态机（倍速/音轨/字幕/设置） |
| `script-modules/player_ui_metrics.lua` | 性能指标采集 |

> ⚠️ **本目录中不存在 `mpv-animejanai.conf` 和 `shaders/`**，但包内必须有——它们来自 AnimeJaNai 包（`build.py` 的 `required` 列表会硬校验 `portable_config/mpv-animejanai.conf`）。

### B.3 `tools/`

| 路径 | 职责 |
|---|---|
| `standalone/build.py` | 完整包装配核心：`prepare` / `stage` / `package` 三阶段 |
| `standalone/publish.py` | 发布：校验 → 生成源码树 → GitHub API 建 commit/release → 上传 → 公开下载复验 → 删除旧 release |
| `standalone/dependencies.json` | 依赖锁：`runtime_seed`（自举种）、`ui_source`、`bootstrap_core`、`native_and_ui_resources`、`components` |
| `standalone/gpu_target.py` | GPU 裁剪与校验：写 `inference/gpu-target.json`，删除非 SM120 内核与全部 DirectML 文件，解析 PE 导入表验证无残留依赖 |
| `standalone/prepare_playback.py` | 编译前对 Lua/C#/测试打补丁（UI 缩放、缩略图仅本地、Player.cs 播放列表/路径判断） |
| `standalone/prepare_gpu_target.py` | 把 dependencies.json 收窄到 `trt-runtime`/`trt-sm120`/`rife`；给 Manager 注入 `TensorRtOnly` 逻辑；改产物名 |
| `standalone/prepare_startup.py` | 启动顺序补丁（`config-dir`/`input-conf`、`volume`/`mute`/`audio-device` 不被前端状态覆盖、`StartupDiagnostics`） |
| `standalone/inline_player_ui_modules.py` | 把 `script-modules/*.lua` 内联进 `player_ui.lua`/`player_ui_danmaku.lua`，规避中文路径下 LuaJIT `dofile` 失败 |
| `standalone/integrate_player_ui.py` | 历史迁移脚本（ModernX → Player UI），当前主链路不调用 |
| `standalone/layout_player_ui.py` + `finalize_player_ui.py` | Player UI 排版/菜单/鼠标事件的源码级修正 |
| `standalone/vendor_notices.py` | 从 NVIDIA 官方包补齐 TensorRT/CUDA 许可证文本（不改运行时二进制） |
| `standalone/runtime_probe.py` / `test_complete.py` / `full_smoke.lua` | 解压后空目录启动验证、自包含 .NET 验证、Lua 全套冒烟 |
| `standalone/Updater.cs(.csproj)` | `AnimeJaNaiUpdater.exe`：`--components --json`（离线读组件清单）、`--verify`（按 SHA256.json 校验） |
| `apply_native_r2.py` | 对 `the-database/mpv` 打 `vo-presented-frame-count` 等原生补丁 |
| `language-r3/*` | 双语资源生成（`prepare.py`/`finalize.py`/`package.py`/`Rewriter.cs`/`Settings-zh.tsv` 150 条设置翻译）+ 管理器/播放器界面测试 |
| `publish_r2.py` / `publish_language_r3.py` / `stage_r2.py` | 历史 r2/r3 发布脚本 |

### B.4 `tests/`

| 文件 | 覆盖 |
|---|---|
| `test_gpu_target.py` | SM120-only 内核、无 DirectML、PE 导入表、无 PTX 后备 |
| `test_windows_r2.py` | Windows 端 FPS/外部播放列表/控制器 |
| `test_script_suite.py` | 脚本套件（`full_smoke.lua`） |
| `test_player_ui_windows.py` | Player UI 输入/排版/轨道/弹幕 |
| `test_player_ui_empty_scope.py` | Player UI 空 `--{ --}` 作用域握手 + 选集请求次数（`wrong_episode_requests==0`） |
| `test_network_playback.py` | 本地 HTTP 播放与请求次数回归 |
| `test_startup_playback.py` | 外部启动、Player UI 播放列表选项、原文件被删回归（7 项） |
| `test_native_runtime.py` | 原生 FPS、重复退出、短生命周期客户端线程 |
| `test_no_release_shortcut.py` | 确认没有 `Ctrl+U` 跳发布页/自动更新残留 |
| `capture_window.py` | 界面截图 |
| `test_player_ui_logic.lua` / `test_player_ui_runtime.lua` / `test_smoke.lua` / `test_stats.lua` / `test_controls.lua` | Lua 层单元/运行测试 |

---

## C. 播放器启动链（追到实际代码）

```
mpvnet.exe
│
├─ 1. src/player/src/MpvNet.Windows/Program.cs :: Main()
│     ├─ StartupDiagnostics.Begin()                  (prepare_startup.py 注入)
│     ├─ App.Init()                                  → App.cs
│     │    ├─ 读和 exe 同目录的 portable_config/mpvnet.conf（App.ConfPath）
│     │    └─ 把 conf 项映射到 App 属性（process-instance / volume / language …）
│     ├─ Theme.Init()
│     ├─ Mutex(基于 ConfPath 的 MD5) → isFirst
│     └─ 分支判断：Shift / --process-instance=multi / --o= / CommandLine.Parsed.NeedsDedicatedProcess
│        ├─ 需要独立进程 → App.ProcessInstance="multi"，继续后面的 Application.Run
│        └─ single/queue 且非首实例 → 把裸路径/URL 经 WM_COPYDATA 转发给已有窗口后 return
│
├─ 2. Application.Run(new WinForms.MainForm())        src/MpvNet.Windows/WinForms/MainForm.cs
│     └─ Player.Init(hwnd, processCommandLine:true)   src/MpvNet/Player.cs:69
│
├─ 3. Player.Init()  —— 关键顺序
│     ├─ mpv_create()
│     ├─ mpv_request_event / mpv_request_log_messages
│     ├─ SetPropertyString("config-dir", ConfigFolder)      …:115
│     │    └─ ConfigFolder 解析顺序 (Player.cs:246)
│     │         1) --config-dir=<path> 命令行显式
│     │         2) 环境变量 MPVNET_HOME
│     │         3) <exe 所在目录>/portable_config      ← 本发行版命中这一条
│     │         4) %AppData%/mpv.net
│     ├─ config=yes / input-conf=memory://<App.InputConf> / osc=yes / idle=yes
│     ├─ CommandLine.ProcessCommandLineArgsPreInit()   CommandLine.cs:58
│     │    └─ 逐条 SetStartupOption → mpv_set_option_string   ← **mpv_initialize 之前**
│     │    └─ 其中 --playlist / --playlist-start / --shuffle 属于 _preInitProperties
│     ├─ mpv_initialize()                              …:139
│     ├─ mpv_create_client("mpvnet")                   ← 前端独享 client，与主 handle 分离
│     ├─ CommandLine.ProcessCommandLineArgsPostInit()  ← 初始化后重新施加可变属性
│     └─ CommandLine.ProcessCommandLineFiles()         CommandLine.cs:172
│
├─ 4. mpv 引擎读配置
│     portable_config/mpv.conf
│       include="~~/mpv-animejanai.conf"   ← 来自 AnimeJaNai 包（本仓库没有）
│       profile=animejanai
│       osc=no / border=no / prefetch-playlist=no / demuxer-cache-wait=no
│     其中 mpv-animejanai.conf 提供 hwdec=nvdec、gpu-api=vulkan,auto、[subs-gpu] 等
│
├─ 5. Lua 自动加载（portable_config/scripts/）
│     ├─ animejanai_backend.lua   启动即跑：读 backend 决定 hwdec/gpu-api
│     ├─ animejanai_slot.lua      注册 on_load(priority -50) → stamp vf slot
│     ├─ network_playback.lua     注册 on_load(priority -1000) → 网络播放策略
│     ├─ player_ui.lua / player_ui_danmaku.lua / thumbfast.lua / animejanaistats.lua
│     └─ （animejanai_session.lua / animejanai_engine_monitor.lua 为空壳）
│
├─ 6. loadfile
│     ├─ Player.LoadFiles() → CommandV("loadfile", file[, "append-play"|"append"])
│     └─ CommandLine.ProcessCommandLineFiles() → 带文件局部选项的 loadfile（见 §D）
│
├─ 7. video output
│     gpu-api=vulkan（TensorRT 路径）；hwdec=nvdec → CUDA 帧直接进滤镜
│     DirectML 路径（d3d11va + gpu-api=d3d11）代码仍在 animejanai_backend.lua，
│     但**本发行版已把 DirectML 二进制全部删除**（见 §E）
│
└─ 8. AI / 滤镜
      animejanai_slot.lua 往 vf 链插入：
        { name="animejanai", label="aji",
          params={ lib="~~/../animejanai/inference/aji.dll",
                   conf="~~/../animejanai/animejanai.conf",
                   model-dir="~~/../animejanai/onnx",
                   rife-model-dir="~~/../animejanai/rife",
                   trtexec="~~/../animejanai/inference/trtexec.exe",
                   stats="~~/../animejanai/currentanimejanai.<pid>.log",
                   slot=<N> } }
      → mpv.exe 中 vf_animejanai 在运行时 LoadLibrary aji.dll（mpv 本体不链接 TensorRT）
      → aji_trt.dll → nvinfer_11.dll → nvinfer_builder_resource_sm120_11.dll → cudart64_13.dll
      → 首次某模型/分辨率：trtexec 构建引擎，日志出现 "Building TensorRT engine"
        → animejanai_slot.lua 暂停播放并 OSD 提示，构建完成后恢复
```

---

## D. 外部调用链（URL / playlist / subtitle / audio 的真正入口）

**唯一入口：Windows 进程 argv** → `Program.Main` 的 `Environment.GetCommandLineArgs().Skip(1)`。

### D.1 解析层：`src/player/src/MpvNet/ScopedCommandLine.cs`

- 支持 `--{ ... --}` 作用域组、`--opt=value`、裸文件/URL、`--` 字面量终止符。
- **Player UI 握手的核心**：Player UI 会把媒体参数塞进一个**空**的 `--{ ... --}` 组。解析器识别到「组内无文件」时，把选项提升为全局但**保留来源标记**（`PromotedOptions` / `EmptyGroupCount` / `EmptyGroupOptionsPromoted`），并把该次调用判定为 `LegacyScriptHandoff`。
- `NeedsDedicatedProcess` = 有分组 **或** 全局选项里出现：
  `input-ipc-server` / `input-ipc-client` / `input-commands` / `scripts` / `script-opts` / `include` / `config-dir` / `sub-files` / `audio-files` / `external-files` / `force-media-title` / `start` / `http-header-fields` / `referrer` / `user-agent` / **`playlist`** / **`playlist-start`**
  → 命中即使用独立进程（`Program.cs:45-53`），避免旧单实例转发丢参数。
- 值选项表 `ValueOptions` 明确包含 `sub-file(s)` / `audio-file(s)` / `external-file(s)` / `playlist` / `playlist-start` / `http-header-fields` 等。
- `Quote()` 用 **UTF-8 字节长度**（`%N%value`）而不是 UTF-16 字符数——这是中文路径/逗号/等号/签名 URL 不坏掉的原因。
- `FileOptions()` 把每个文件的选项正规化成 mpv 的 key/value 列表，`sub-files`→`sub-add`，多个同名项合并并用 `\;` 转义。

### D.2 施加层：`src/player/src/MpvNet/CommandLine.cs`

| 阶段 | 行为 |
|---|---|
| PreInit（`mpv_initialize` 前） | 非列表项 → `Player.ProcessProperty` / `App.ProcessProperty` / `mpv_set_option_string`。**`playlist`、`playlist-start`、`shuffle` 被跳过给 mpv 原生处理**，避免「先打开首项再切」的竞争 |
| PreInit | `scripts` / `script-opts` 的 add/append/pre/set/clr 被合并成单个列表值后一次设置 |
| PostInit | `-add`/`-set`/`-append`/`-pre`/`-clr`/`-remove`/`-toggle` → `change-list`；`playlist`/`playlist-start`/`shuffle` 再次跳过；其余可变属性重新 `SetPropertyString`（防止保存的前端状态覆盖调用方显式值） |
| Files | 有 `--playlist` → 只用 `loadfile … append -1 <file-options>` 追加条目，**不重建播放列表**；否则 `<1` 个文件直接 `loadfile`，多文件/分组/`playlist-start`/`shuffle` 时逐条 append 再 `playlist-play-index` |

### D.3 其它入口

| 入口 | 位置 |
|---|---|
| JSON IPC | `--input-ipc-server=\\.\pipe\...`（`test_complete.py` 用它对 `vo-presented-frame-count` 取值） |
| 浏览器/资源管理器 | 文件关联注册（`Program.cs:33` `--register-file-associations`）+ `WM_COPYDATA` 单实例转发 |
| 字幕 | `LoadFiles` 里按扩展名分流：字幕扩展名 → `sub-add`；`.iso` → `LoadISO`；`.avs` → AviSynth；`.lnk` → 解析快捷方式 |
| 音频 | `--audio-file(s)` / `Alt+a` → `load-audio` |
| 分集字幕/标题/起播位置 | 由 `--{ … --}` 组内选项经 `ScopedCommandLine.FileOptions()` 作为**该文件局部选项**绑定 |
| 诊断 | `portable_config/startup-diagnostic.json`（含调用方式/播放列表选择方式/加载阶段，**不含地址与令牌**）、`portable_config/playback-diagnostic.json` |

---

## E. AI 链

| 能力 | 是否使用 | 初始化位置 | 调用位置 | 依赖 |
|---|---|---|---|---|
| **超分** | ✅ | `animejanai/animejanai.conf` `[slot_N] chain_N_model_N_name`；模型文件 `animejanai/onnx/*.onnx` | `animejanai_slot.lua` 建 `vf=animejanai`；`mpv.exe` 的 `vf_animejanai` 加载 `animejanai/inference/aji.dll` | aji.dll / aji_trt.dll（`the-database/animejanai-inference`） |
| **补帧 RIFE** | ✅ | 同上 `chain_N_rife=yes`、`chain_N_rife_model=426`、`chain_N_rife_factor_numerator/denominator`、`chain_N_rife_before_upscale`、`chain_N_rife_scene_detect_threshold`、`chain_N_rife_ensemble` | aji 内部，`rife-model-dir=~~/../animejanai/rife` | `rife_vX.Y[_lite][_ensemble].onnx`（`build.py` 会按 conf 中的编码反推文件名并强制存在） |
| **Anime4K** | ❌ **完全没有** | — | — | 全仓库 grep 无任何 Anime4K 引用。去色带用的是 `deband=yes` + `~~/shaders/noise_static_luma.hook` / `noise_static_chroma.hook`（后者来自 AnimeJaNai 包的 `shaders/`，本仓库不含） |
| **TensorRT** | ✅ 唯一后端 | `animejanai.conf` `[global] backend=TensorRT`；`tools/standalone/gpu_target.py` 写 `animejanai/inference/gpu-target.json` | `nvinfer_11.dll` / `nvinfer_plugin_11.dll` / `nvonnxparser_11.dll` / `trtexec.exe` | `nvinfer_builder_resource_sm120_11.dll`（**只保留 SM120**，其他代际内核被 `prune()` 删除；`inspect_payload()` 强制校验 `sm120*` 存在） |
| **CUDA** | ✅ | 由 aji_trt.dll 加载 | `cudart64_13.dll`（CUDA 13.3.29） | NVIDIA 显卡驱动（系统提供，不打包） |
| **DirectML** | ❌ **已被裁剪掉** | `gpu_target.py` 的 `DML_FILES` = `aji_dml.dll`, `aji_harness_dml.exe`, `directml.dll`, `onnxruntime.dll`, `onnxruntime_providers_shared.dll` → 全部 `forbidden` 并删除 | — | `validate()` 会检查所有保留二进制**不允许**导入这些名字，并检查 `animejanai.conf` 的 `backend` 必须是 `tensorrt` |
| **ONNX** | ✅ | 模型放 `animejanai/onnx/` 与 `animejanai/rife/`；引擎由 `trtexec` 在本机首次构建并缓存 | `aji` 读取；`animejanai_slot.lua` 检测 `Building TensorRT engine` 并暂停 | TensorRT 运行时 |
| **VapourSynth** | ❌ 不使用（仅作兼容防御） | — | `animejanai_slot.lua:191` 检测到 `vf` 里存在 `vapoursynth` 滤镜且参数含 `animejanai` 时**主动报错拒绝叠加** | README 明确「无需另装 Python 或 VapourSynth」 |

**AI 状态与控制的唯一拥有者**：`portable_config/scripts/animejanai_slot.lua`
- `mp.register_script_message('aji-slot', request)` 接收 `Ctrl+0..9` 的 `script-message aji-slot N`
- `on_load(-50)` 在起播前 stamp 好 slot，并 `repair_bindings()` 运行时修掉旧 `input.conf` 里 `apply-profile upscale-on; script-message aji-slot N` 的危险组合（**只改内存中的键位，不写用户文件**）
- 引擎构建期间 `hold_pause()` / 完成后 `release_pause()`；仅在「用户本来就暂停 + 主动切档」时做一次 0 秒精确 seek 刷新，正常播放绝不 seek
- 状态日志按进程隔离：`animejanai/currentanimejanai.<pid>.log`

**Ctrl+J 实际 FPS**：`animejanai/` 之外的原生属性 `vo-presented-frame-count`（由 `tools/apply_native_r2.py` 打进 `the-database/mpv` 的 `video/out/vo.c` + `player/command.c`）+ `animejanaistats.lua` 按真实时钟计算。语义是「VO 提交的唯一视频帧」，不是显示器扫描输出。

---

## F. UI 链

### F.1 播放器外壳（窗口/菜单/设置）

| 文件 | 作用 |
|---|---|
| `src/player/src/MpvNet.Windows/WinForms/MainForm.cs` (+ `.Designer.cs`) | 主窗口 |
| `src/player/src/MpvNet.Windows/WPF/ConfWindow.xaml(.cs)` | 设置编辑器 |
| `src/player/src/MpvNet.Windows/WPF/LearnWindow.xaml`、`InputWindow.xaml`、`Views/AboutWindow.xaml` | 快捷键编辑器 / 输入窗 / 关于 |
| `src/player/src/MpvNet.Windows/UI/Theme.cs`、`WPF/Resources.xaml` | 主题 |
| `src/player/src/MpvNet.Windows/WPF/HandyControl/**` | 内嵌的 HandyControl 子集 |
| `src/player/src/NGettext.Wpf/**` | 内嵌的 NGettext.Wpf 本地化 |

来源仓库：`mpvnet-player/mpv.net`，基线 **v7.1.2.0**，许可证 GPL-2.0（`src/player/License.txt`、`THIRD_PARTY_LICENSES/mpv.net-LICENSE.txt`、`MpvNet.Windows.csproj` 的 `FileVersion 7.1.2.0`）。历史 owner 为 `stax76/mpv.net`（`input.conf` 里的帮助链接与 `docs/manual_chs.md` 仍指向它；Transifex 项目也是 `o:stax76:p:mpvnet`）。

### F.2 播放器内控制栏（真正的「播放界面」）

**Player UI 控制栏 = 本项目自研，没有对应上游仓库。**

| 文件 | 作用 |
|---|---|
| `portable_config/scripts/player_ui.lua` | 主控制器：ASS overlay、底部按钮、进度条、音量、标题、网络速度、自动隐藏 |
| `portable_config/scripts/player_ui_danmaku.lua` | 弹幕层 |
| `portable_config/script-modules/player_ui_core.lua` | 纯函数（`layout()` 排版、`ellipsize()`、`time()`、`rate()`、`title()`、`local_media()`、`safe_apply()`） |
| `portable_config/script-modules/player_ui_menu.lua` | 菜单状态机（倍速/音轨/字幕/设置），支持 hover 阻塞、ESC 返回上级 |
| `portable_config/script-modules/player_ui_metrics.lua` | 指标采集 |
| `portable_config/script-opts/player_ui.conf` | `ui_scale=0.70` 等 |
| `portable_config/scripts/animejanaistats.lua` | Ctrl+J 状态面板 |
| `portable_config/scripts/network_playback.lua` | 网络播放策略与诊断 |

「Player UI」这个名字在本仓库里指的是**外部调用方 / 使用场景**（Player UI 把媒体参数放在空 `--{ --}` 组里传进来），控制栏是照着这个使用场景做的，**不是从某个第三方 UI 仓库 fork 的**。文件头注释直接写 `-- Player UI-style controller, rendered with vector icons and system fonts.`，仓库中不存在对应的 LICENSE/来源说明，`docs/RELEASE-r4.md` 也把它当作本项目自制组件描述。

**图标与字体**：用 ASS/矢量绘制（`player_ui_core.lua` 的 `chars()`/`escape()` 自行处理 UTF-8，不依赖 Lua 5.3 utf8 模块），使用系统字体。构建时 `build.py` 的 `FONTS` 过滤器会把任何 `.ttf/.otf/.ttc/.woff*/.fon/.fnt` **从包里删掉并断言不存在**。

**模块内联**：`inline_player_ui_modules.py` 把 `script-modules/*.lua` 包成 `(function() … end)()` 直接内联进 `player_ui.lua` / `player_ui_danmaku.lua`。原因是 LuaJIT 在含非 ASCII 字符的便携目录里 `dofile`/`loadfile` 会失败。`script-modules/` 源文件保留供源码级测试。

### F.3 被移除的第三方 UI

`cyl0/ModernX` **曾**被使用，但已被本项目替换：`tools/standalone/integrate_player_ui.py:46` 会 `unlink` `portable_config/scripts/modernx.lua` 与 `portable_config/script-opts/modernx.conf`，`build.py:133-134` 在 stage 阶段再次强制删除，`publish.py:59-60` 还会在源码树里为这两个文件写入删除条目。**当前发行版里没有 ModernX。**

### F.4 缩略图

`po5/thumbfast`（MPL-2.0，`THIRD_PARTY_LICENSES/thumbfast-LICENSE.txt`）。本仓库打了补丁：

1. `tools/standalone/build.py:135-137` — `mpv_path` 改成 `expand-path ~~/../mpv.exe`，让 thumbfast 用包内 `mpv.exe` 而不是 PATH 里的 mpv。
2. `tools/standalone/prepare_playback.py:41-54` — 增加 `local_file_only()` 守卫：非本地媒体、`demuxer-via-network`、非普通文件路径时直接禁用缩略图。
3. `.conf` 里 `network=no`、`spawn_first=no`、`quit_after_inactivity=15`、`max_height=360`、`max_width=560`、`overlay_id=42`。

---

## G. 构建链

### G.1 先分清哪些 workflow 真的会跑

GitHub Actions **只读仓库根目录的 `.github/workflows/`**。以下两个目录里的 workflow 文件**永远不会被执行**，它们是随上游源码一起进来的历史文件：

- `src/player/.github/__workflows__ currently flawed/build.yml`（目录名已被改成非 `workflows`，上游 mpv.net 的 CI）
- `src/manager/.github/workflows/{release.yml,zh-cn-build.yml}`（上游 Manager 的 CI，分别在嵌套仓库里）

**根目录 `.github/workflows/` 的 11 个**：

| 文件 | 状态 | 作用 |
|---|---|---|
| `standalone.yml` | **主线** | 完整便携包：编译 → 装配 → 测试 → 打包 → 发布 |
| `build-native-counter.yml` | 独立 | 从上游源码编译原生 mpv（含 FPS 计数器补丁）+ libass，产出 artifact |
| `diagnose-native-runtime.yml` | 独立 | 下载上面的 artifact，用 gdb 抓 WASAPI 关闭崩溃栈 |
| `audit-sources.yml` | 独立 | 克隆 8 个上游仓库做来源审计 |
| `network-audit.yml` | 独立 | 打包 tracked 源码快照 |
| `publish-r2.yml` | 历史 | 校验并发布 r2 候选 |
| `verify-release-112.yml` | 历史 | 校验 1.1.2 公开下载 |
| `publish-language-r3.yml` | 历史 | 发布 r3 语言候选 |
| `build-language-r3.yml` | **已禁用** | 只剩 echo 提示 |
| `validate-release-r2.yml` | **已禁用** | 只剩 echo 提示 |
| `build-ui-r2.yml` | 历史 | 用固定 commit 构建 UI r2 |

### G.2 `standalone.yml` 逐步展开

```
runs-on: windows-2022  timeout: 60min  PYTHONUTF8=1
[1] actions/checkout@v4  (persist-credentials: false)
[2] Prepare playback and RTX 5080 Laptop sources
      python tools/standalone/prepare_playback.py       ← 打 Lua/C#/测试补丁
      python tools/standalone/inline_player_ui_modules.py   ← 内联 Player UI 模块
      python tools/standalone/prepare_gpu_target.py     ← 收窄依赖 + Manager TensorRtOnly
      python tools/standalone/prepare_startup.py        ← 启动顺序补丁
      python tests/test_gpu_target.py
[3] python tests/test_no_release_shortcut.py
[4] python tools/standalone/test_runtime_probe.py
[5] actions/setup-dotnet@v4   dotnet-version: 10.x
[6] python tools/standalone/build.py prepare
      ├─ 若无 src/player：下载 ui_source（本项目 zh-CN-3.6.0-r4 的 r4-sources.zip）解到 src/
      ├─ 改 manager 的 MainWindow.axaml（禁用组件勾选框、换成说明文本）
      ├─ 往 manager/player 的 LanguageStrings.json 注入 standaloneComponentsNote
      ├─ 复制 src/player → ./player，src/manager → ./manager
      ├─ 生成 tests-generated/{manager,player}-tests
      └─ 写 complete-evidence/source-inputs.json（逐文件 SHA256）
[7] dotnet run ScopedCommandLine / ManagerTests / PlayerTests  ← 语言与外部参数解析回归
[8] dotnet publish player/src/MpvNet.Windows   → publish-player   (self-contained, single-file, win-x64)
    dotnet publish manager/AnimeJaNaiConfEditor → publish-manager  (同上)
    dotnet publish tools/standalone/Updater.csproj → publish-updater
[9] python tools/standalone/build.py stage
      ├─ 下载 runtime_seed（本项目 standalone-v1.1.5 完整包，SHA256 锁定）→ 解压 → 取 app root → stage/
      │   （fallback：bootstrap_core = the-database/mpv-AnimeJaNai 3.6.0 的
      │    mpv-upscale-2x_animejanai-full-package-3.6.0.7z.001
      │    + native_and_ui_resources = 本项目 zh-CN-3.6.0-r4 的 update.zip
      │    + components = the-database/mpv-AnimeJaNai 3.6.0 的 trt-runtime/trt-sm120/rife）
      ├─ 删 stage 的 portable_config/{scripts,watch_later}
      ├─ 覆盖本仓库的 portable_config/、animejanai.conf、许可证
      ├─ 把 publish-player/-manager/-updater 的 .exe/.dll/.json 盖上去（mpvnet.exe 被本项目版本替换）
      ├─ 复制本机 VS2022 的 VC143 CRT DLL
      ├─ vendor_notices.collect() ← 见 §G.3
      ├─ 删 modernx.lua / modernx.conf
      ├─ 改 thumbfast.lua 的 mpv_path
      ├─ 从 input conf 去掉 "apply-profile upscale-on; "
      ├─ gpu_target.prune() ← 删非 SM120 内核 + 全部 DirectML 文件，写 gpu-target.json
      ├─ 写 manifest.json / 使用说明.md / 准备使用.txt / README-full.txt
      └─ inspect_payload() ← 硬校验必需文件、预设模型、RIFE 文件、NVIDIA 许可证文本、无字体
[10] python tests/test_gpu_target.py stage
     python tests/test_windows_r2.py stage
     python tests/test_script_suite.py stage
     python tests/test_player_ui_windows.py stage
     python tests/test_network_playback.py stage
     python tests/test_startup_playback.py stage
     python tests/test_player_ui_empty_scope.py stage
[11] python tools/standalone/build.py package
      ├─ 校验 language-evidence 三个 PASS 标记 + runtime 测试全通过
      ├─ 7z -t7z -mx=3 -mmt=2 → 校验 → ≥2GB 时切成 1.9GB 分卷
      ├─ 解压回 clean-install，把全部测试**再跑一遍**（空目录验证）
      ├─ 生成 sources.zip（src/tools/tests/portable_config/animejanai/THIRD_PARTY_LICENSES + LICENSE + release.json + docs/standalone.md）
      └─ SHA256SUMS.txt / RELEASE.md / payload-verification.json
[12] python tools/standalone/publish.py   （仅 push 且 commit message 含 [release]，或手动 publish=true）
      ├─ 校验 SHA256SUMS
      ├─ 校验全部 evidence 门禁（fresh-install 5 项、player_ui 2 项、network 非空、gpu-target 通过且 target.id==rtx5080-laptop、startup 7 项、player_ui-handoff 3 项且 wrong_episode_requests==0）
      ├─ 断言 main HEAD == GITHUB_SHA
      ├─ 把 dependencies.json 的 runtime_seed 更新为本次产物（自举闭环）
      ├─ 用 GitHub API 建 blob/tree/commit，创建 draft release 并上传
      ├─ 校验每个 asset 的 digest 与 state
      ├─ fast-forward main，release 转正
      ├─ 逐字节重新下载公开资产复验
      └─ 删除旧 standalone-v* release
[13] actions/upload-artifact@v4  证据 / 未发布时的完整包
```

### G.3 构建期实际访问的外部地址与仓库

| 类型 | 地址 / 仓库 | 用在 |
|---|---|---|
| 源码 checkout | `sunuuc/AnimeJaNai-zh-CN`（自身，含 `source` 分支 commit `23946b4e…`） | `standalone.yml`、`build-ui-r2.yml`、`network-audit.yml` |
| 源码 checkout | `sunuuc/AnimeJaNaiManager` @ `bdcf21af308d9494d23a309055196e7937819afc` | `build-ui-r2.yml` |
| 源码 checkout | `the-database/AnimeJaNaiManager` @ `d69c523e3c21a5097a2a9366faf33516512845a2`（sparse `tests/ProfileRoundTrip`） | `build-ui-r2.yml` |
| 源码 checkout | `the-database/mpv-winbuild` @ `19a2e58e6de47af6711161ed4fc1294a191f40bf` | `build-native-counter.yml` |
| 源码 checkout | `the-database/mpv` @ `d4c06dd3424dc06d90d4ea15b0fa92fa3ceeb62f` | `build-native-counter.yml`、`diagnose-native-runtime.yml`、`tools/apply_native_r2.py` 硬校验 |
| 源码 checkout | `the-database/libass` @ `896614fa263f9f64944f7b8650ff6806d5328c4d` | `build-native-counter.yml` |
| 审计 clone | `sunuuc/AnimeJaNai-zh-CN`(main+source)、`sunuuc/AnimeJaNaiManager`、`the-database/mpv-AnimeJaNai`、`the-database/AnimeJaNaiManager`、`mpvnet-player/mpv.net`、`the-database/animejanai-inference`、`mpv-player/mpv` | `audit-sources.yml` |
| Release 下载（自举） | `github.com/sunuuc/AnimeJaNai-zh-CN/releases/download/standalone-v1.1.5/AnimeJaNai-zh-CN-1.1.5-rtx5080-laptop-win-x64-full.7z`（sha256 `aaa9c7a8…c964f3`） | `build.py::stage` runtime_seed |
| Release 下载（UI 源码） | `…/zh-CN-3.6.0-r4/r4-sources.zip`（sha256 `3fe10b0b…a59077`） | `build.py::prepare` |
| Release 下载（兜底） | `…/standalone-v1.1.5` 之外的 `zh-CN-3.6.0-r4/AnimeJaNai-3.6.0-zh-CN-r4-update.zip`（sha256 `fb38e54c…6d4aed`） | `dependencies.json::native_and_ui_resources` |
| Release 下载（兜底） | `the-database/mpv-AnimeJaNai` 3.6.0 的 `mpv-upscale-2x_animejanai-full-package-3.6.0.7z.001`、`component-trt-runtime.7z`、`component-trt-sm120.7z`、`component-rife.7z`（均带 sha256） | `dependencies.json::bootstrap_core` / `components` |
| Release 下载（旧 overlay 审计） | `…/zh-CN-3.6.0/AnimeJaNai-3.6.0-zh-CN-overlay.zip`（sha256 `9750f9c9…f10732`） | `build-ui-r2.yml` |
| Release 下载（r3 基线） | `…/zh-CN-3.6.0-r2/AnimeJaNai-3.6.0-zh-CN-r2-update.zip` | `tools/language-r3/package.py` |
| NVIDIA 官方下载 | `developer.nvidia.com/downloads/compute/machine-learning/tensorrt/11.1.0/zip/TensorRT-Enterprise-11.1.0.106-Windows-amd64-cuda-13.3-Release-external.zip` | `vendor_notices.py`（仅取许可证文本，并校验与包内 runtime 哈希一致） |
| NVIDIA 官方下载 | `developer.download.nvidia.com/compute/cuda/redist/cuda_cudart/windows-x86_64/cuda_cudart-windows-x86_64-13.3.29-archive.zip`（sha256 `1feb7dd2…b64d9c`） | 同上 |
| NVIDIA 文档 | `docs.nvidia.com/deeplearning/tensorrt/latest/reference/sla.html` | 同上 |
| GitHub Actions | `actions/checkout@v4`、`actions/setup-dotnet@v4`、`actions/upload-artifact@v4`、`actions/download-artifact@v4`、`msys2/setup-msys2@v2` | 全部 workflow |
| msys2 包源 | UCRT64 仓库（gcc/meson/ninja/pkgconf/nasm/ffmpeg/ffnvcodec-headers/libplacebo/freetype/fribidi/harfbuzz/libunibreak/luajit/mujs/libarchive/lcms2/vulkan-headers/gdb…） | `build-native-counter.yml`、`diagnose-native-runtime.yml` |
| NuGet | `CommunityToolkit.Mvvm 8.4.0`、`NGettext 0.6.7`、`Microsoft.Xaml.Behaviors.Wpf 1.1.135`、Avalonia 12.0.4 全套、FluentAvaloniaUI 3.0.0-preview4、ReactiveUI.Avalonia 12.0.3、Salaros.ConfigParser 0.3.8、Material.Icons.Avalonia 3.0.2、HyperText.Avalonia 11.0.0-rc1、System.Management 10.0.0 | `Directory.Packages.props`、各自 `.csproj` |
| 工具 | `gh` CLI、`7-Zip`（`build.py` 里 `shutil.which('7z')` 或 `C:\Program Files\7-Zip\7z.exe`） | publish / package |

### G.4 `build-native-counter.yml`（原生 mpv 构建，未接入主线）

```
checkout the-database/mpv-winbuild@19a2e58e → 工作目录根
checkout 自身 → project/
checkout the-database/mpv@d4c06dd3 → mpv-source/
checkout the-database/libass@896614fa → libass-source/
python project/tools/apply_native_r2.py mpv-source
   ├─ 硬校验 HEAD == d4c06dd3…
   └─ 改 video/out/vo.c、video/out/vo.h、player/command.c
      新增 vo_get_presented_frame_count() 与 mpv 属性 vo-presented-frame-count
msys2/setup-msys2 UCRT64 + 一大串包
meson setup build-ass libass-source -Ddirectwrite=enabled -Dfontconfig=disabled -Dthreads=enabled …
meson setup build-mpv mpv-source -Dlibmpv=true -Dcuda-hwaccel=enabled -Dcuda-interop=enabled
                            -Dlua=luajit -Djavascript=enabled -Dd3d11=enabled -Dvulkan=enabled …
meson compile / install ×2
stage-native.py + prepare-test-runtime.py
meson test + TOOLS/subtest/test_stability.py（字幕稳定性）
记录 msys2-packages.txt / native-r2.patch / mpv-commit.txt / libass-commit.txt
tests/test_native_runtime.py
上传 artifact: native-r2-candidate
```

**关键点**：`standalone.yml` 从不下载这个 artifact。原生 mpv 的产物完全靠 seed 提供。

---

## H. 独立版情况：哪些自带、哪些仍依赖外部

### H.1 已经完全自带（不依赖外部，解压即用）

| 项目 | 证据 |
|---|---|
| `mpvnet.exe` + .NET 运行时 | `standalone.yml` 里 `--self-contained true -p:PublishSingleFile=true`；`test_complete.py` 把 `DOTNET_ROOT` 指向空目录后仍要求启动成功 |
| `AnimeJaNaiManager.exe` + .NET 运行时 | 同上；`test_complete.py::manager()` 要求窗口出现且 `external_dotnet_disabled` |
| `AnimeJaNaiUpdater.exe` | `tools/standalone/Updater.cs`，**纯离线**：`--components` 读包内 `build-info/standalone/components.json`，`--verify` 读 `SHA256.json`；`--check`/`--open-releases` 明确返回 2 且日志里不含 `github.com` |
| 全部播放器配置与 Lua | `portable_config/**` 来自本仓库，stage 时整体覆盖 |
| AI 预设 | `animejanai/animejanai.conf` 来自本仓库 |
| Player UI 控制栏（含模块内联） | `player_ui*.lua` + `inline_player_ui_modules.py` |
| TensorRT 运行库 + SM120 内核 + CUDA 运行库 + trtexec | 已裁剪进包，`gpu_target.py::validate` 逐文件校验 + PE 导入表校验 |
| aji.dll / aji_trt.dll | 随组件进入包 |
| 超分模型 + RIFE 模型 | `inspect_payload()` 按 `animejanai.conf` 反推文件名强制存在 |
| 中文界面 | 内嵌 `LanguageStrings.json` + `Locale/zh-CN/LC_MESSAGES/mpvnet.mo`（在 `required` 列表里） |
| 第三方许可证文本 | `THIRD_PARTY_LICENSES/` + NVIDIA 官方许可证（`vendor_notices.py` 现场抓取并校验哈希） |
| VC143 CRT | stage 时从本机 VS2022 复制 |
| 更新/组件安装 | 改为「从本项目发布页下载完整程序」+ 离线组件自查（`Ctrl+U` 逻辑已被移除，`test_no_release_shortcut.py` 守卫） |

### H.2 仍然依赖外部（**构建期**）

| 项目 | 依赖什么 | 影响 |
|---|---|---|
| **`mpv.exe` / `libmpv-2.dll`** | 本仓库**不编译**。只能来自 `runtime_seed`（本项目 1.1.5 完整包）或 `bootstrap_core`（`the-database/mpv-AnimeJaNai` 3.6.0） | 想在源码层面改原生行为，必须先用 `build-native-counter.yml` 单独构建，再把产物塞进 seed 或改流水线 —— **当前没有自动化通路** |
| `mpv-animejanai.conf` | 本仓库 `portable_config/` 里**没有**这个文件，但 `build.py` 的 `required` 列表硬校验它必须存在 | 它只能来自 seed / AnimeJaNai 包。`animejanai_backend.lua` 依赖它的 `[subs-gpu]` profile |
| `portable_config/shaders/*.hook` | 同上，不在本仓库；但 `input.conf` 的 `b` 键引用 `~~/shaders/noise_static_luma.hook` | 来自 AnimeJaNai 包 |
| `animejanai/inference/**` 二进制与模型 | 来自 seed；首次 bootstrap 时来自 `the-database/mpv-AnimeJaNai` 3.6.0 的组件包 | 已自举 |
| 自举种子 | `standalone-v1.1.5` 完整包（1.10 GB） | **1.1.5 本身派生自 AnimeJaNai 3.6.0**，所以「完全脱离旧 AnimeJaNai」这句话只在 1.1.5 之后成立 |
| NVIDIA 官方 ZIP | `vendor_notices.py` 每次 stage 都抓 TensorRT/CUDA 原厂包（只取许可证） | 网络失败会影响构建；不改运行时二进制 |
| UI 源码兜底 | 若 `src/player` 不存在，会去下载本项目 `zh-CN-3.6.0-r4` 的 `r4-sources.zip` | 仅在仓库被裁剪成最小集时触发 |

### H.3 仍然依赖外部（**运行时**）

| 项目 | 说明 |
|---|---|
| NVIDIA 显卡驱动 | README 明确「显卡驱动由系统安装」 |
| 首次 TensorRT 引擎构建 | 首次使用某个模型/分辨率时在本机生成，不下载，但会**暂停播放**（`animejanai_slot.lua`，最多等 1200 秒） |
| 外部调用方（Player UI 等） | 通过命令行/IPC 传入 URL、播放列表、字幕；不在包内 |

### H.4 只用于 CI / 只用于测试

| 类型 | 项目 |
|---|---|
| 仅 CI | `msys2/setup-msys2`、msys2 UCRT64 包、`the-database/mpv-winbuild`、`the-database/mpv`、`the-database/libass`、`the-database/AnimeJaNaiManager`（仅 sparse `tests/ProfileRoundTrip`）、`audit-sources.yml` 里克隆的 8 个仓库 |
| 仅测试 | `tests/**`、`tools/standalone/{full_smoke.lua,test_complete.py,test_runtime_probe.py}`、`tools/language-r3/*Tests.cs`、`src/player/tests/ScopedCommandLine`、`src/manager/tests/ProfileRoundTrip` |
| 构建时（打进包但只在构建用） | `build-info/**`（provenance.json、SHA256.json、components.json、validation 证据） |

---

## I. 仓库清单

| 仓库 | 用途 | 当前项目实际使用位置 | 运行时需要 | 构建时需要 |
|---|---|---|---|---|
| `sunuuc/AnimeJaNai-zh-CN` | 本项目主体；`main`=装配/补丁/发布，`source`=mpv.net 中文 fork，`fix/playlist-1.1.6`=分支修复 | 全仓库 | ❌ | ✅ |
| `the-database/mpv-AnimeJaNai` | AnimeJaNai 核心发行；提供 mpv.exe / libmpv-2.dll / inference / 模型 / 组件包 | `tools/standalone/dependencies.json`（`bootstrap_core`、`components`）；`.github/workflows/audit-sources.yml` | ❌（已被 seed 取代） | ✅（仅首次 bootstrap） |
| `the-database/AnimeJaNaiManager` | Manager 上游（0.6.0，GPL-3.0） | `build-ui-r2.yml`（clone 取 `tests/ProfileRoundTrip`）；`audit-sources.yml`；`THIRD_PARTY_LICENSES/AnimeJaNaiManager-GPL-3.0.txt` | ❌ | ⚠ 仅 `build-ui-r2.yml`（历史流水线）；`standalone.yml` 用本仓库 `src/manager` |
| `sunuuc/AnimeJaNaiManager` | Manager 中文 fork（19 ahead / 4 behind） | `src/manager/**` 的基座；`build-ui-r2.yml` @ `bdcf21af…` | ❌ | ⚠ 同上（`standalone.yml` 不拉取） |
| `the-database/animejanai-inference` | `libaji` 推理 shim（strict C ABI，`include/aji.h`），产出 aji.dll / aji_trt.dll | 产物在 `animejanai/inference/`；`audit-sources.yml` | ✅（作为 aji.dll 的源码来源） | ❌（本仓库不编译它，只消费二进制） |
| `the-database/mpv` | mpv fork，含 `vf_animejanai`、WASAPI/ASS 修复、`vo-presented-frame-count` | `build-native-counter.yml` @ `d4c06dd3…`；`diagnose-native-runtime.yml`；`tools/apply_native_r2.py` 硬校验 | ✅（mpv.exe 的真源） | ✅ 但**仅独立 workflow**，主流水线不拉取 |
| `the-database/libass` | libass fork（57 ahead / 3 behind） | `build-native-counter.yml` @ `896614fa…` | ✅（打进 mpv.exe 动态依赖） | 同上 |
| `the-database/mpv-winbuild` | Windows 构建系统（fork of `zhongfly/mpv-winbuild` ← `shinchiro/mpv-winbuild-cmake`） | `build-native-counter.yml` @ `19a2e58e…` | ❌ | ✅（仅原生 workflow） |
| `zhongfly/mpv-winbuild` | mpv-winbuild 的直接上游 | 仅出现在 `src/player/.github/__workflows__ currently flawed/build.yml`（**不执行**） | ❌ | ❌ |
| `mpvnet-player/mpv.net` | mpv.net 上游（GPL-2.0，v7.1.2.0） | `src/player/**` 的基线；`audit-sources.yml`；`THIRD_PARTY_LICENSES/mpv.net-LICENSE.txt` | ✅（编译成 mpvnet.exe） | ⚠ 仅 `audit-sources.yml` 克隆；`standalone.yml` 用本仓库 `src/player` |
| `stax76/mpv.net` | mpv.net 历史 owner（Transifex 项目 `stax76/mpvnet`） | `portable_config/input.conf` 帮助链接；`src/player/.tx/config`；`docs/manual_chs.md` | ❌ | ❌ |
| `mpv-player/mpv` | mpv 官方上游 | README「基于的项目」；`audit-sources.yml` | ❌（间接，实际用 the-database/mpv） | ❌ |
| `po5/thumbfast` | 时轴缩略图（MPL-2.0） | `portable_config/scripts/thumbfast.lua` + `script-opts/thumbfast.conf`；`THIRD_PARTY_LICENSES/thumbfast-LICENSE.txt` | ✅ | ❌（源码已入库） |
| `cyl0/ModernX` | 曾经的第三方 OSC | **已被删除**：`tools/standalone/integrate_player_ui.py:46`、`build.py:133-134`、`publish.py:59-60` | ❌ | ❌ |
| `NVIDIA/TensorRT` | TensorRT 运行时与引擎构建 | 二进制在 `animejanai/inference/`；`vendor_notices.py` 抓原厂包取许可证；README「基于的项目」 | ✅ | ✅ |
| NVIDIA CUDA（非 GitHub） | `cudart64_13.dll` | `animejanai/inference/cudart64_13.dll`；`vendor_notices.py` 的 CUDA redist | ✅ | ✅ |
| `microsoft/*` Actions | `checkout@v4` / `setup-dotnet@v4` / `upload-artifact@v4` / `download-artifact@v4` | 全部根 workflow | ❌ | ✅ |
| `msys2/setup-msys2@v2` + msys2 UCRT64 | 原生 mpv 构建工具链 | `build-native-counter.yml`、`diagnose-native-runtime.yml` | ❌ | ✅（仅原生 workflow） |
| NuGet 包（CommunityToolkit.Mvvm / NGettext / Avalonia / ReactiveUI / FluentAvaloniaUI / Salaros.ConfigParser / Material.Icons / HyperText / System.Management / Microsoft.Xaml.Behaviors.Wpf） | C# 依赖 | `Directory.Packages.props`、`MpvNet.csproj`、`MpvNet.Windows.csproj`、`AnimeJaNaiConfEditor.csproj`、`Updater.csproj` | ✅（已内含或自包含发布） | ✅ |
| `mpvnet-player/file-host` | `mpvnet.com` 文件 | 仅 `src/player/.github/__workflows__ currently flawed/build.yml`（**不执行**） | ❌ | ❌ |
| `mediaarea.net` MediaInfo | `MediaInfo.dll` | 仅上述不执行的 build.yml；本包是否含 MediaInfo.dll 取决于 seed | ⚠ | ❌ |

---

## 附：审计过程中发现的来源不明 / 需要继续追查的点

（仅记录事实，不含修复方案）

1. **`mpv-animejanai.conf` 与 `portable_config/shaders/*.hook` 在本仓库不存在**，但被 `mpv.conf` / `input.conf` 引用且被 `build.py` 硬校验。它们的真实来源是 AnimeJaNai 包的 seed，本仓库没有它们的版本历史。
2. **`player_ui*.lua` 系列没有上游仓库、没有 LICENSE 头、没有第三方声明**。它们被当作本项目自制组件处理（`docs/RELEASE-r4.md` 的叙述也如此），但仓库里没有一份明确的「这是自研」声明文件。
3. **`animejanai_backend.lua` / `animejanai_session.lua` / `animejanai_engine_monitor.lua` 的上游 commit 不可追溯**——它们随 AnimeJaNai 包分发，本仓库只保存了（已中文化的）副本，没有 pin 到 `the-database/mpv-AnimeJaNai` 的具体 revision。
4. **`po5/thumbfast` 的具体版本不可追溯**。仓库里只有打过补丁的 `thumbfast.lua`，没有记录它对应上游哪个 commit/tag（上游最近一次相关提交是 2026-06-28）。
5. **`src/manager` 与本仓库的 `sunuuc/AnimeJaNaiManager` 之间的对应关系是间接的**。`build-ui-r2.yml` 从 `sunuuc/AnimeJaNaiManager@bdcf21af` 取源码，而 `standalone.yml` 直接用本仓库 `src/manager`；两者是否逐字节相同没有断言，只有 `audit-sources.yml` 做了 merge-base 对比（且只对 manager）。
6. **`native_and_ui_resources` 指向的 `zh-CN-3.6.0-r4` 资产在 GitHub Releases 页面上已不可见**（当前只剩 `standalone-v1.1.5`），只能通过 `dependencies.json` 里的 sha256 与 `build-ui-r2.yml` 里的旧 overlay 链接间接确认其存在。这属于**兜底路径失效**的风险点，主路径（`runtime_seed`）不受影响。
7. **`build-native-counter.yml` 与主流水线之间没有数据通道**，`diagnose-native-runtime.yml` 还硬编码了 `run-id: 34815785037` 这个一次性 artifact 来源。
8. `src/player/.github/__workflows__ currently flawed/` 与 `src/manager/.github/workflows/` 是随上游源码带进来的非活动 CI，容易在阅读时被误认为生效。
9. **`source` 分支已落后于 `main` 的 `src/player`**：`source@23946b4e`（2026-09-14）缺少 5 个中文界面文件（`InterfaceLanguage.cs` / `LanguageStrings.json` / `UiText.cs` / `StartupDiagnostics.cs` / `PlayerLanguage.cs`），且行尾为 LF 而非 CRLF。而 `build-ui-r2.yml` 恰好 pin 在这个 commit 上。两条链路（`standalone.yml` 用本地 `src/player`，`build-ui-r2.yml` 用 `source@23946b4e`）的播放器源码已经不是同一份。
10. **`fix/playlist-1.1.6` 分支基本等同于 `main`**：实测树内 314 个 blob 路径完全一致，只有 `.github/workflows/network-audit.yml` 一个文件内容不同；该分支停在 `[release] 1.1.6` 提交 `99b58150`，`main` 在其上多一个提交 `7e397bcd`。

---

*本文件为审计产物，未修改任何现有代码，未创建 commit，未创建 Release。*
