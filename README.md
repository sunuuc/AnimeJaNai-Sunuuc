# AnimeJaNai 中文汉化包
个人使用，因为有人有需求我就分享了出来
本分支基于上游 AnimeJaNai 项目继续整合，并不是上游官方发布版。需要原版说明、模型介绍和通用硬件支持时，请优先参考上游项目。
适配3.6 直接覆盖安装目录
## 这版主要做了什么

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

## 为什么 Ctrl+5 和 Ctrl+8 都是 4K

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

1. 以完整 AnimeJaNai 安装目录为基础，把本分支构建出的覆盖包解压到安装目录并覆盖。
2. Player UI 使用外部播放器时，指向根目录的 **`mpvnet.exe`**。
3. 第一次运行某个 TensorRT 超分模型时，需要生成 TensorRT Engine，首次可能等待一段时间；生成后会缓存。
4. 播放时用 `Ctrl+1` ～ `Ctrl+9` 切换预设，`Ctrl+0` 关闭 AI。
5. `Esc` 只退出全屏。

## 本整合版使用 / 基于的项目

本仓库不是从零实现播放器和 AI 推理，而是在下列开源项目基础上进行中文化、配置和兼容性整合：

| 项目 | 用途 |
|---|---|
| [the-database/mpv-AnimeJaNai](https://github.com/the-database/mpv-AnimeJaNai) | 核心 AnimeJaNai 播放、模型、配置和更新体系 |
| [the-database/AnimeJaNaiManager](https://github.com/the-database/AnimeJaNaiManager) | AnimeJaNai 图形配置管理器；本分支进行了简体中文化 |
| [the-database/animejanai-inference](https://github.com/the-database/animejanai-inference) | AnimeJaNai 原生 TensorRT / DirectML 推理与 RIFE / 超分处理链 |
| [mpv-player/mpv](https://github.com/mpv-player/mpv) | 底层视频播放器 |
| [mpvnet-player/mpv.net](https://github.com/mpvnet-player/mpv.net) | Windows 播放器外壳；本整合版基于 v7.1.2.0 做 Player UI 参数兼容修复 |
| [zydezu/ModernX](https://github.com/zydezu/ModernX) | 播放控制界面 |
| [po5/thumbfast](https://github.com/po5/thumbfast) | 进度条视频缩略图 |
| [NVIDIA TensorRT](https://github.com/NVIDIA/TensorRT) | NVIDIA GPU AI 推理后端 |

RIFE 补帧模型和 AnimeJaNai 的超分模型由 AnimeJaNai 的组件体系提供。第三方组件的版权和许可证仍归各自项目所有；构建包中保留相应第三方许可证文件。

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

## 许可证与致谢

感谢 AnimeJaNai、mpv、mpv.net、ModernX、thumbfast、TensorRT 及相关开源项目的开发者。  
本分支仅对现有项目进行中文化、配置预设和兼容性整合；各上游项目继续遵循其原有许可证。

都是gpt改的，如有问题请联系https://openai.com/ 
