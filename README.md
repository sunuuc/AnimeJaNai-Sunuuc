# AnimeJaNai-zh-CN

AnimeJaNai 的 Windows 中文整合版，包含播放器、配置管理器、AI 模型、运行库和常用预设。

## 下载

- [Release 页面](https://github.com/sunuuc/AnimeJaNai-zh-CN/releases/tag/standalone-v1.0.1)
- [Windows x64 完整包](https://github.com/sunuuc/AnimeJaNai-zh-CN/releases/download/standalone-v1.0.1/AnimeJaNai-zh-CN-1.0.1-win-x64-full.7z)

完整包约 1.59 GiB。

SHA-256：

```text
f18b66a21af9a526f1d1d0491b1aee2b62f24b51b2c5d210e8ba6be4586873fb
```

## 使用

1. 将压缩包解压到一个新目录。
2. 运行 `mpvnet.exe` 播放视频。
3. 运行 `AnimeJaNaiManager.exe` 调整 AnimeJaNai 配置。

包内已经包含所需的播放器、模型和运行库，不需要另外安装 AnimeJaNai、Python、VapourSynth 或 .NET。NVIDIA 显卡驱动仍由系统安装。

首次使用某个模型或分辨率时，TensorRT 可能需要生成一次引擎缓存，之后会直接复用。

## 包含内容

- mpv / mpv.net 播放器
- AnimeJaNai 配置管理器
- 简体中文、English、跟随系统三种界面语言
- ModernX 控制栏和 thumbfast 缩略图
- 默认快捷键与 Sharp1 / 2K / 4K 预设
- 超分模型和 RIFE 模型
- TensorRT 11.1 运行库
- RTX 20 / 30 / 40 / 50 系列构建内核与 PTX 后备内核
- DirectML / ONNX Runtime

## 主要修改

- 管理器和播放器设置中文化，语言选择放在管理器的全局设置中。
- AI 档位切换由单一控制器处理，减少重复重建滤镜和连续按键不生效的问题。
- 调整起播初始化流程，避免加载后再次套用默认档位。
- 修复外部播放器连续分集时字幕、标题和播放参数串集的问题。
- `Ctrl+J` 显示实际视频输出 FPS 与目标 FPS。

## 快捷预设

| 快捷键 | 预设 | 1080p / 24fps 示例 |
|---|---|---|
| `Ctrl+1` | 补帧 2× | 1080p 24 → 48fps |
| `Ctrl+2` | 补帧 3× | 1080p 24 → 72fps |
| `Ctrl+3` | 2K 超分｜极速 | → 1440p |
| `Ctrl+4` | 2K 超分｜高质量 | → 1440p |
| `Ctrl+5` | 4K 超分｜高质量 | → 2160p |
| `Ctrl+6` | 2×补帧 + 2K｜极速 | → 1440p 48fps |
| `Ctrl+7` | 2×补帧 + 2K｜高质量 | → 1440p 48fps |
| `Ctrl+8` | 2×补帧 + 4K｜极速 | → 2160p 48fps |
| `Ctrl+9` | 3×补帧 + 2K｜极速 | → 1440p 72fps |
| `Ctrl+0` | 关闭 AI | 原样播放 |

2K = 2560×1440，4K = 3840×2160。

## Ctrl+J

播放时按 `Ctrl+J` 显示 AnimeJaNai 状态和帧率：

```text
当前实际 FPS: 47.82 / 目标 47.95
```

实际 FPS 根据 `vo-presented-frame-count` 的变化量和真实经过时间计算。重复刷新和 OSD 重绘不会作为新视频帧计入。

## 语言

在管理器中打开 **全局设置 → 界面语言**，可以选择：

- 简体中文
- English
- 跟随系统

修改后重启播放器和管理器生效。

## 构建与测试

GitHub Actions 会重新编译 Windows 播放器和管理器，并检查：

- 中英文界面与配置读写
- 外部播放列表、多字幕和分集参数
- 24 / 48 FPS、半速和慢滤镜播放
- Lua 控制脚本
- 模型、运行库、配置引用和许可证
- 自包含 .NET 运行
- 完整压缩包解压后的播放器和管理器启动

CI 环境没有 NVIDIA GPU 和实际 Player UI 服务，因此 GPU 推理性能和 Player UI 在线播放需要在真实设备上测试。

## 源码目录

- `src/player`：播放器源码
- `src/manager`：配置管理器源码
- `portable_config`：mpv 配置和 Lua 脚本
- `animejanai`：AnimeJaNai 默认配置
- `tools/standalone`：完整包构建、校验和发布脚本
- `.github/workflows/standalone.yml`：Windows 构建与发布流程

## 上游项目

| 项目 | 用途 |
|---|---|
| [the-database/mpv-AnimeJaNai](https://github.com/the-database/mpv-AnimeJaNai) | AnimeJaNai 核心体系 |
| [the-database/AnimeJaNaiManager](https://github.com/the-database/AnimeJaNaiManager) | 配置管理器 |
| [the-database/animejanai-inference](https://github.com/the-database/animejanai-inference) | TensorRT / DirectML 推理、RIFE 与超分 |
| [mpv-player/mpv](https://github.com/mpv-player/mpv) | 播放器核心 |
| [mpvnet-player/mpv.net](https://github.com/mpvnet-player/mpv.net) | Windows 播放器界面 |
| [zydezu/ModernX](https://github.com/zydezu/ModernX) | 播放控制界面 |
| [po5/thumbfast](https://github.com/po5/thumbfast) | 进度条缩略图 |
| [NVIDIA TensorRT](https://github.com/NVIDIA/TensorRT) | NVIDIA GPU 推理后端 |

## 许可证

各组件继续使用各自的许可证。许可证、来源和构建记录随发布包保留。
