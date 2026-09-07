# AnimeJaNai 中文汉化+个人调优

个人使用，因为有人有需求我就分享了出来。

本分支基于上游 AnimeJaNai 项目继续整合，并不是上游官方发布版。需要原版说明、模型介绍和通用硬件支持时，请优先参考上游项目。

> `main` 只保留实际覆盖替换文件、主页说明和分发所需的许可证文件。需要源码的组件在下方提供对应源码仓库或独立源码分支。

## 主要做了什么

- **AnimeJaNai Manager 简体中文化**：界面、按钮、提示、导入导出、组件管理、性能测试等可见内容均做了中文处理。
- **内置 RTX 5080 Laptop 专用预设**：按 16GB 显存、2560×1600 屏幕和实际性能测试重新安排 9 个快捷预设。
- **Player UI 兼容**：使用 mpv.net 作为外部播放器时，修复 Player UI 传入 `--{` / `--}` 导致 mpv.net 误解析的问题。
- **ModernX + thumbfast**：提供更现代的播放控制界面和进度条缩略图。
- **更新器兼容预发布版本**：组件安装按本地 `package_version` 对应的 release tag 获取，避免 3.6.0 预发布版错误匹配稳定版组件。

## 预设说明

| 快捷键 | 预设 | 1080p / 24帧 | 720p / 24帧 |
|---|---|---|---|
| `Ctrl+1` | 补帧 2× | 1080p 24帧 → 1080p 48帧 | 720p 24帧 → 720p 48帧 |
| `Ctrl+2` | 补帧 3× | 1080p 24帧 → 1080p 72帧 | 720p 24帧 → 720p 72帧 |
| `Ctrl+3` | **2K 超分｜极速** | 1080p 24帧 → 720p 24帧 → 1440p（2K）24帧 | 720p 24帧 → 1440p（2K）24帧 |
| `Ctrl+4` | **2K 超分｜高质量** | 1080p 24帧 → 720p 24帧 → 1440p（2K）24帧 | 720p 24帧 → 1440p（2K）24帧 |
| `Ctrl+5` | **4K 超分｜高质量** | 1080p 24帧 → 2160p（4K）24帧 | 720p 24帧 → 1440p（2K）24帧 |
| `Ctrl+6` | **2×补帧 + 2K｜极速** | 1080p 24帧 → 720p 24帧 → 720p 48帧 → 1440p（2K）48帧 | 720p 24帧 → 720p 48帧 → 1440p（2K）48帧 |
| `Ctrl+7` | **2×补帧 + 2K｜高质量** | 1080p 24帧 → 720p 24帧 → 720p 48帧 → 1440p（2K）48帧 | 720p 24帧 → 720p 48帧 → 1440p（2K）48帧 |
| `Ctrl+8` | **2×补帧 + 4K｜极速** | 1080p 24帧 → 1080p 48帧 → 2160p（4K）48帧 | 720p 24帧 → 720p 48帧 → 1440p（2K）48帧 |
| `Ctrl+9` | **3×补帧 + 2K｜极速** | 1080p 24帧 → 720p 24帧 → 720p 72帧 → 1440p（2K）72帧 | 720p 24帧 → 720p 72帧 → 1440p（2K）72帧 |
| `Ctrl+0` | 关闭 AI | 1080p 24帧原样播放 | 720p 24帧原样播放 |

### “极速”和“高质量”是什么意思

- **极速 = Performance**：更轻、更快，适合补帧 + 超分同时开启。
- **高质量 = Balanced**：模型更重，换取更好的超分细节。
- 本整合版的高清 Performance / Balanced 都切换到了对应的 **Sharp1** 版本。

## 高质量与极速的区别

两者用途不同：

- **Ctrl+5：4K 超分｜高质量**  
  1080p 24帧直接使用 Sharp1 Balanced 超到 4K，帧率仍为 24帧。适合只追求超分画质。

- **Ctrl+8：2×补帧 + 4K｜极速**  
  1080p 24帧先补到 48帧，再使用 Sharp1 Performance 超到 4K 48帧。它同时做补帧和 4K 超分，因此使用更快的 Performance，避免 Balanced 负载过高。

## RTX 5080 Laptop 实测参考

本机测试环境：AnimeJaNai 3.6.0、TensorRT、RTX 5080 Laptop 16GB。

| 输入分辨率 | Balanced 实测 | Performance 实测 |
|---|---:|---:|
| 1280×720 | 132.9 fps | 250.1 fps |
| 1920×1080 | 54.5 fps | 97.6 fps |

这组数值来自 AnimeJaNai 的播放性能测试，用来判断不同性能档在这台机器上的实时余量。它也是 4K 补帧档选择 Performance 的主要依据：1080p 先补到 48帧后，再做 4K 超分，需要明显高于 48 fps 的超分余量。

## 使用方式

适配 [AnimeJaNai](https://github.com/the-database/mpv-AnimeJaNai/releases/tag/3.6.0) 3.6 版本。

1. 以完整 AnimeJaNai 安装目录为基础，把本分支的文件下载后覆盖到安装目录。
2. 使用外部播放器打开视频时，指向根目录的 **`mpvnet.exe`**。
3. 第一次运行某个 TensorRT 超分模型时，需要生成 TensorRT Engine，首次可能等待一段时间；生成后会缓存。
4. 播放时用 `Ctrl+1` ～ `Ctrl+9` 切换预设，`Ctrl+0` 关闭。
5. `Esc` 只退出全屏。

## 本整合版使用 / 基于的项目

本仓库不是从零实现播放器和 AI 推理，而是在下列项目基础上进行中文化、配置和兼容性整合：

| 项目 | 用途 / 本仓库对应内容 |
|---|---|
| [the-database/mpv-AnimeJaNai](https://github.com/the-database/mpv-AnimeJaNai) | 核心 AnimeJaNai 播放、模型、配置和更新体系；本仓库由其 fork 修改而来 |
| [the-database/AnimeJaNaiManager](https://github.com/the-database/AnimeJaNaiManager) | AnimeJaNai 图形配置管理器；本版进行了简体中文化 |
| [sunuuc/AnimeJaNaiManager](https://github.com/sunuuc/AnimeJaNaiManager/tree/bdcf21af308d9494d23a309055196e7937819afc) | 本仓库分发的中文 Manager 对应修改源码，基于 GPL-3.0 |
| [the-database/animejanai-inference](https://github.com/the-database/animejanai-inference) | AnimeJaNai 原生 TensorRT / DirectML 推理与 RIFE / 超分处理链 |
| [mpv-player/mpv](https://github.com/mpv-player/mpv) | 底层视频播放器 |
| [mpvnet-player/mpv.net](https://github.com/mpvnet-player/mpv.net/tree/v7.1.2.0) | Windows 播放器外壳；本版基于 v7.1.2.0 做 Player UI 参数兼容修复 |
| [mpv.net Player UI 修改源码](https://github.com/sunuuc/mpv-AnimeJaNai/tree/mpvnet-player_ui-source) | main 中 `mpvnet.exe` 的完整对应源码与构建说明，GPL-2.0 |
| [zydezu/ModernX](https://github.com/zydezu/ModernX) | 播放控制界面 |
| [po5/thumbfast](https://github.com/po5/thumbfast) | 进度条视频缩略图，MPL-2.0 |
| [NVIDIA TensorRT](https://github.com/NVIDIA/TensorRT) | NVIDIA GPU AI 推理后端 |

RIFE 补帧模型和 AnimeJaNai 的超分模型由 AnimeJaNai 的组件体系提供。第三方组件的版权和许可证仍归各自项目及作者所有。

## 与上游的关系

这个仓库是个人定制 fork，重点是：

- 简体中文界面；
- RTX 5080 Laptop / 2560×1600 的专用预设；
- Sharp1 高清模型；
- Player UI + mpv.net 兼容；
- ModernX / thumbfast 播放体验整合。

通用安装说明、模型原理、AMD / Intel 支持、官方基准和上游更新，请查看：

- [mpv-AnimeJaNai 官方仓库](https://github.com/the-database/mpv-AnimeJaNai)
- [AnimeJaNai Manager 官方仓库](https://github.com/the-database/AnimeJaNaiManager)

## 许可证、源码与致谢

本仓库中基于 **mpv-AnimeJaNai** 修改的内容继续按照上游的 **Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International（CC BY-NC-SA 4.0）** 条款分享。根目录保留上游完整 [`LICENSE`](./LICENSE)。这意味着再分发时需要保留署名与来源、注明修改、仅限非商业用途，并对相应衍生内容采用相同方式共享。

本仓库是修改版而不是官方发布版。主要修改包括简体中文化、RTX 5080 Laptop 预设、Sharp1 模型配置、更新器的预发布版本兼容、Player UI / mpv.net 参数兼容，以及播放器配置整合。

第三方组件按各自许可证处理：

- **AnimeJaNaiManager.exe**：GPL-3.0。完整许可证位于 [`THIRD_PARTY_LICENSES/AnimeJaNaiManager-GPL-3.0.txt`](./THIRD_PARTY_LICENSES/AnimeJaNaiManager-GPL-3.0.txt)，本次中文修改对应源码位于 [`sunuuc/AnimeJaNaiManager@bdcf21a`](https://github.com/sunuuc/AnimeJaNaiManager/tree/bdcf21af308d9494d23a309055196e7937819afc)。
- **mpvnet.exe**：GPL-2.0。许可证位于 [`THIRD_PARTY_LICENSES/mpv.net-LICENSE.txt`](./THIRD_PARTY_LICENSES/mpv.net-LICENSE.txt)，本次 Player UI 兼容修改的完整对应源码位于 [`mpvnet-player_ui-source`](https://github.com/sunuuc/mpv-AnimeJaNai/tree/mpvnet-player_ui-source)。
- **thumbfast**：MPL-2.0。许可证位于 [`THIRD_PARTY_LICENSES/thumbfast-LICENSE.txt`](./THIRD_PARTY_LICENSES/thumbfast-LICENSE.txt)，Lua 源码直接随覆盖文件分发。
- **ModernX**：本仓库保留其原作者、项目地址和源文件头部署名。其上游仓库当前没有单独的 `LICENSE` 文件，因此本仓库不对 ModernX 另行授予或变更许可证；如需进一步再分发或用于其他项目，请以 ModernX 上游作者给出的许可为准。
- 其他运行时、模型及组件继续遵循各自上游许可证与使用条款，本仓库的 CC BY-NC-SA 4.0 不会替代第三方组件自身许可证。

感谢 AnimeJaNai、AnimeJaNai Manager、mpv、mpv.net、ModernX、thumbfast、TensorRT 及相关项目的开发者。

