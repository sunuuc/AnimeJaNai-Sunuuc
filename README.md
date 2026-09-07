# AnimeJaNai 中文汉化 + 个人调优

个人使用，因为有人有需求我就分享了出来。

本仓库基于上游 [the-database/mpv-AnimeJaNai](https://github.com/the-database/mpv-AnimeJaNai) 继续整合，并不是上游官方发布版。

> **仓库只保留源码、配置、文档和许可证；编译后的 EXE / DLL / 字体及完整覆盖包只放在 Releases。**

## 下载

直接使用请到 [Releases](https://github.com/sunuuc/AnimeJaNai-zh-CN/releases) 下载完整覆盖包，不要直接下载仓库源码当安装包使用。

当前 3.6.0 中文覆盖包：

- [AnimeJaNai 3.6.0 中文汉化覆盖包](https://github.com/sunuuc/AnimeJaNai-zh-CN/releases/tag/zh-CN-3.6.0)

使用方法：以完整 AnimeJaNai 3.6.0 目录为基础，将 Release 中的 ZIP 解压后覆盖原目录。

## 主要修改

- **AnimeJaNai Manager 简体中文化**：界面、按钮、提示、导入导出、组件管理、性能测试等可见内容中文化。
- **RTX 5080 Laptop 专用预设**：按 16GB 显存、2560×1600 屏幕和实际性能测试重新安排快捷预设。
- **Sharp1 高清模型配置**：Performance / Balanced 高清档切换到对应 Sharp1 模型。
- **Player UI 兼容**：修复 Player UI 调用 mpv.net 时传入 `--{` / `--}` 导致的参数误解析。
- **ModernX + thumbfast**：整合现代播放控制界面和进度条缩略图。

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

## RTX 5080 Laptop 实测参考

测试环境：AnimeJaNai 3.6.0、TensorRT、RTX 5080 Laptop 16GB。

| 输入分辨率 | Balanced 实测 | Performance 实测 |
|---|---:|---:|
| 1280×720 | 132.9 fps | 250.1 fps |
| 1920×1080 | 54.5 fps | 97.6 fps |

因此 1080p 先补到 48帧再做 4K 超分的 `Ctrl+8` 使用 Performance，以保留更充足的实时性能余量。

## 源码位置

本仓库 `main` 仅保留可直接审阅的配置、Lua 脚本、README 和许可证；二进制只在 Releases 分发。

| 内容 | 源码位置 |
|---|---|
| AnimeJaNai 配置 / Lua 脚本 | 本仓库 `main` |
| AnimeJaNai Manager 中文修改 | [sunuuc/AnimeJaNaiManager@bdcf21a](https://github.com/sunuuc/AnimeJaNaiManager/tree/bdcf21af308d9494d23a309055196e7937819afc) |
| mpv.net Player UI 兼容修改 | [`source` 分支](https://github.com/sunuuc/AnimeJaNai-zh-CN/tree/source) |
| mpv.net 上游基线 | [mpvnet-player/mpv.net v7.1.2.0](https://github.com/mpvnet-player/mpv.net/tree/v7.1.2.0) |

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
- **ModernX**：保留原作者、项目地址和源文件头信息；其上游仓库当前没有单独 LICENSE 文件，本仓库不另行改变其许可条件。

感谢 AnimeJaNai、AnimeJaNai Manager、mpv、mpv.net、ModernX、thumbfast、TensorRT 及相关项目开发者。
