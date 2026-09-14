# AnimeJaNai 中文汉化 + 个人调优

> **当前更新：r3 中文恢复与语言设置。** [下载 r3 累计修复包](https://github.com/sunuuc/AnimeJaNai-zh-CN/releases/tag/zh-CN-3.6.0-r3)。播放器设置窗口与管理器顶部均可选简体中文、English、跟随系统，默认简体中文，重启后生效。已包含 r2 修复，无须另装 r2；保留个人配置、模型和缓存。[详细说明](docs/RELEASE-r3.md)。下方 r2 链接和说明保留作历史参考。


个人使用，因为有人有需求我就分享了出来。

本仓库基于上游 [the-database/mpv-AnimeJaNai](https://github.com/the-database/mpv-AnimeJaNai) 继续整合，并不是上游官方发布版。

> **仓库只保留源码、配置、文档和许可证；编译后的 EXE / DLL 及覆盖包只放在 Releases。**

## 下载

直接使用请到 [Releases](https://github.com/sunuuc/AnimeJaNai-zh-CN/releases) 下载覆盖包。

**已有 3.6.0 中文版：安装 r2 增量修复包。全新安装：先安装原 3.6.0 中文覆盖包，再覆盖 r2。**

- [3.6.0 中文修复包 r2](https://github.com/sunuuc/AnimeJaNai-zh-CN/releases/tag/zh-CN-3.6.0-r2)
- [r2 更新说明与验证范围](docs/RELEASE-r2.md)

原始 3.6.0 中文覆盖包（保留用于基础安装、回退）：

- [AnimeJaNai 3.6.0 中文汉化覆盖包](https://github.com/sunuuc/AnimeJaNai-zh-CN/releases/tag/zh-CN-3.6.0)

使用方法：完全退出播放器和配置管理器，备份原安装目录，将 ZIP 内容解压到播放器根目录并覆盖同名文件。r2 不覆盖个人 mpv.conf、input.conf、animejanai.conf、模型和引擎缓存；请完整覆盖包内文件，不要只替换一个 DLL。

## 主要修改

- **AnimeJaNai Manager 简体中文化**：界面、按钮、提示、导入导出、组件管理、性能测试等可见内容中文化。
- **RTX 5080 Laptop 专用预设**：按 16GB 显存、2560×1600 屏幕和原有性能记录安排快捷预设。
- **Sharp1 高清模型配置**：Performance / Balanced 高清档切换到对应 Sharp1 模型。
- **外部播放参数兼容**：保留 `--{` / `--}` 每集独立的字幕、标题与播放参数；避免旧单实例转发丢失参数。已用实际 mpvnet 进程测试多集、多字幕和两次独立调用；未验证用户 Player UI 账户、服务器或其实际传出的 URL。
- **ModernX + thumbfast**：整合现代播放控制界面和进度条缩略图。
- **Ctrl+J 实时状态**：用新增原生 VO 计数器计算真实时间内提交的新视频帧数，面板只显示实际 FPS / 目标 FPS。丢帧行和“跑满”标签已删除；不再使用目标减丢帧或时间戳回调的旧算法。

## 预设

| 快捷键 | 预设 | 1080p / 24帧 | 720p / 24帧 |
|---|---|---|---|
| `Ctrl+1` | 补帧 2× | 1080p 24帧 → 1080p 48帧 | 720p 24帧 → 720p 48帧 |
| `Ctrl+2` | 补帧 3× | 1080p 24帧 → 1080p 72帧 | 720p 24帧 → 720p 72帧 |
| `Ctrl+3` | **2K 超分｜极速** | 1080p 24帧 → 720p 24帧 → 1440p 24帧 | 720p 24帧 → 1440p 24帧 |
| `Ctrl+4` | **2K 超分｜高质量** | 1080p 24帧 → 720p 24帧 → 1440p 24帧 | 720p 24帧 → 1440p 24帧 |
| `Ctrl+5` | **4K 超分｜高质量** | 1080p 24帧 → 2160p 24帧 | 720p 24帧 → 1440p 24帧 |
| `Ctrl+6` | **2×补帧 + 2K｜极速** | 1080p 24帧 → 720p 24帧 → 720p 48帧 → 1440p 48帧 | 720p 24帧 → 720p 48帧 → 1440p 48帧 |
| `Ctrl+7` | **2×补帧 + 2K｜高质量** | 1080p 24帧 → 720p 24帧 → 720p 48帧 → 1440p 48帧 | 720p 24帧 → 720p 48帧 → 1440p 48帧 |
| `Ctrl+8` | **2×补帧 + 4K｜极速** | 1080p 24帧 → 1080p 48帧 → 2160p 48帧 | 720p 24帧 → 720p 48帧 → 1440p 48帧 |
| `Ctrl+9` | **3×补帧 + 2K｜极速** | 1080p 24帧 → 720p 24帧 → 720p 72帧 → 1440p 72帧 | 720p 24帧 → 720p 72帧 → 1440p 72帧 |
| `Ctrl+0` | 关闭 AI | 原样播放 | 原样播放 |

本页中 **2K = 1440p（2560×1440）**，**4K = 2160p（3840×2160）**。

- **极速 = Performance**
- **高质量 = Balanced**

## Ctrl+J 实时状态

播放时按 `Ctrl+J` 显示 / 隐藏 AnimeJaNai 状态，底部只有一行：

```text
当前实际 FPS: 47.82 / 目标 47.95
```

实际 FPS = 原生 `vo-presented-frame-count` 的增量 / 同一窗口的真实耗时；重复屏幕刷新和 OSD 重绘不计新视频帧。目标 FPS 使用 `estimated-vf-fps × speed`，绝不把它冒充实际输出。这个指标是播放器的视频输出提交速率，不是显示器的物理扫描测量。

面板打开时每 0.25 秒采样一次，以约 2 秒窗口平滑；关闭面板即停止采样。AI 日志最多每 2 秒读一次。暂停为 0，刚打开、跳转、滤镜改变后短暂显示 `--`；旧版原生库没有此计数器时也显示 `--`，不编造数值。引擎构建监控是独立功能，只在活动的 AI 播放期间运行，结束即停止。

`Ctrl+U` 打开本中文仓库发布页，不执行会覆盖汉化和自定义原生计数器的官方整包更新；组件管理仍保留。不同播放器进程分别使用带 PID 的 AI 状态日志。

## RTX 5080 Laptop 历史参考

以下为仓库原有的性能参考记录，**不是 r2 本次的 GPU 回归结果，也不能保证每段视频都达到同样帧率**。原记录环境：AnimeJaNai 3.6.0、TensorRT、RTX 5080 Laptop 16GB。

| 输入分辨率 | Balanced 实测 | Performance 实测 |
|---|---:|---:|
| 1280×720 | 132.9 fps | 250.1 fps |
| 1920×1080 | 54.5 fps | 97.6 fps |

原 `Ctrl+8` 预设因此选择 Performance；r2 不改变已保存的预设。

## 源码位置

本仓库 `main` 保留配置、Lua、原生补丁、测试、构建与发布流程；二进制在 Releases 分发。每个 r2 包的 `build-info` 记录实际来源提交、测试结果和逐文件 SHA-256。

| 内容 | 源码位置 |
|---|---|
| AnimeJaNai 配置 / Lua 脚本 | 本仓库 `main` |
| AnimeJaNai Manager 中文修改 | [sunuuc/AnimeJaNaiManager@bdcf21a](https://github.com/sunuuc/AnimeJaNaiManager/tree/bdcf21af308d9494d23a309055196e7937819afc)，叠加 `build-ui-r2.yml` 固定的 RIFE 保存补丁 |
| mpv.net Player UI 兼容修改 | [`source` 分支](https://github.com/sunuuc/AnimeJaNai-zh-CN/tree/source) |
| mpv.net 上游基线 | [mpvnet-player/mpv.net v7.1.2.0](https://github.com/mpvnet-player/mpv.net/tree/v7.1.2.0) |

## r2 构建与验证

`build-native-counter.yml` 构建原生播放器与依赖，`build-ui-r2.yml` 构建中文前端和管理器；`validate-release-r2.yml` 按明确的构建产物 ID / SHA-256 组装并测试，只有全部通过才产出 ZIP；`publish-r2.yml` 再次核对精确候选包后发布，不把不同源码版本的构建产物混用。

Actions 临时产物有保留期限。到期后重建应先运行原生与 UI 构建，再同步更新 `tools/stage_r2.py` 中的 ID 和哈希，不能把旧 ID 换成“随便最新一次”。发布包、构建来源和校验记录在 Releases 保留；历史版本可回退。

本次验证包括 14 组 Windows 原生 / 实际前端回归、15 项更新器生产方法回归、控制脚本状态机和整组 Lua 的真实运行检查。没有 RTX5080 硬件或用户 Player UI 实际服务器，发布仍标记为预发布，不能宣称所有 GPU 场景或上游客户端行为都已验证。

已选择合入 Manager 0.6.0 的 RIFE Ensemble 保存修复、更新器组件版本选择与快捷键原子迁移修复、两个 D3D11 shader 初始化修复；没有单独混装新的 inference / TensorRT 大版本，保留已安装 3.6.0 的配套 AI 组件。

## 使用 / 基于的项目

| 项目 | 用途 |
|---|---|
| [the-database/mpv-AnimeJaNai](https://github.com/the-database/mpv-AnimeJaNai) | AnimeJaNai 核心播放、配置与组件体系 |
| [the-database/AnimeJaNaiManager](https://github.com/the-database/AnimeJaNaiManager) | 图形配置管理器 |
| [the-database/animejanai-inference](https://github.com/the-database/animejanai-inference) | TensorRT / DirectML 推理、RIFE 与超分处理链 |
| [mpv-player/mpv](https://github.com/mpv-player/mpv) | 底层播放器 |
| [mpvnet-player/mpv.net](https://github.com/mpvnet-player/mpv.net) | Windows 播放器外壳 |
| [zydezu/ModernX](https://github.com/zydezu/ModernX) | 播放控制界面 |
| [po5/thumbfast](https://github.com/po5/thumbfast) | 进度条视频缩略图 |
| [NVIDIA TensorRT](https://github.com/NVIDIA/TensorRT) | NVIDIA GPU AI 推理后端 |

## 许可证与源码

本仓库中基于 **mpv-AnimeJaNai** 修改的内容继续按照上游 **CC BY-NC-SA 4.0** 条款分享，完整文本见根目录 [`LICENSE`](./LICENSE)。

第三方组件继续按各自许可证处理：

- **AnimeJaNaiManager**：GPL-3.0，对应许可证位于 `THIRD_PARTY_LICENSES/AnimeJaNaiManager-GPL-3.0.txt`，修改源码见上方链接。
- **mpv.net**：GPL-2.0，对应许可证位于 `THIRD_PARTY_LICENSES/mpv.net-LICENSE.txt`，本次 Player UI 修改完整源码位于 `source` 分支。
- **thumbfast**：MPL-2.0，对应许可证位于 `THIRD_PARTY_LICENSES/thumbfast-LICENSE.txt`，Lua 源码随本仓库保留。
- **ModernX**：保留原作者、项目地址和源文件头信息；其上游许可情况沿用原仓库说明，不额外赋予许可。

感谢 AnimeJaNai、AnimeJaNai Manager、mpv、mpv.net、ModernX、thumbfast、TensorRT 及相关项目开发者。
