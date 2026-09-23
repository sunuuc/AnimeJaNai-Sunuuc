# AnimeJaNai-Sunuuc

Windows 视频播放器，支持动漫 AI 超分、RIFE 补帧和中文配置管理。

## 下载与使用

[下载](https://github.com/sunuuc/AnimeJaNai-zh-CN/releases)

Windows x64，面向 **NVIDIA GeForce RTX 5080 Laptop GPU**。安装包使用 TensorRT 和 SM120 内核，不包含其他代际显卡的内核、PTX 后备内核或 DirectML 后端。

解压完整包，运行 `mpvnet.exe`。调整 AI 配置时打开 `AnimeJaNaiManager.exe`。

包内包含播放器、模型和运行库，无需另装 .NET、Python 或 VapourSynth。首次使用某个模型或分辨率时，TensorRT 需要生成引擎缓存；之后可以复用。显卡驱动由系统安装。

## 播放界面

Player UI 风格控制栏提供标题、进度与缓冲、播放、音量、倍速、音轨、字幕、弹幕、设置和全屏。鼠标移开后自动隐藏，网络视频在右上角显示当前读取速度。

倍速、音轨和字幕菜单在对应按钮上方展开。字幕菜单可分别选择主字幕和第二字幕；设置菜单中可以调整缩放模式、超分补帧预设、字幕和弹幕，并查看媒体信息与性能统计。

外部程序传入多项播放列表时，右侧列表按实际标题与顺序选播。网络视频不生成进度缩略图、不预读下一项。弹幕支持本地 XML，与字幕独立显示。视频旁的同名 XML 可自动加载。

## 快捷键

| 按键 | 功能 |
|---|---|
| 上 / 下 | 音量 +5 / −5 |
| 左 / 右 | 后退 / 前进 5 秒 |
| 空格 | 播放 / 暂停 |
| Esc | 返回上级菜单、关闭菜单或退出全屏 |
| Ctrl+1 / Ctrl+2 | 2× / 3× 补帧 |
| Ctrl+3 / Ctrl+4 | 2K 超分：极速 / 高质量 |
| Ctrl+5 | 4K 超分：高质量 |
| Ctrl+6 / Ctrl+7 | 2×补帧 + 2K：极速 / 高质量 |
| Ctrl+8 | 2×补帧 + 4K：极速 |
| Ctrl+9 | 3×补帧 + 2K：极速 |
| Ctrl+0 | 关闭 AI |
| Ctrl+J | AnimeJaNai 状态与实际 FPS |
| Ctrl+E | 配置管理器 |

2K 为 2560×1440，4K 为 3840×2160。

实际 FPS 根据原生 `vo-presented-frame-count` 和真实经过时间计算，重复刷新不计为新视频帧。性能面板中的 GPU 时间是渲染耗时，不是整张显卡的占用率。

## 配置

管理器的全局设置中可以切换界面语言，重启播放器和管理器后生效。AI 预设保存在 `animejanai/animejanai.conf`，播放器配置和脚本位于 `portable_config`。

## 构建

`src/player` 和 `src/manager` 为播放器和配置管理器源码，`tools/standalone` 为完整包构建工具。GitHub Actions 编译 Windows 程序，并运行配置、分集字幕、FPS、控制脚本和界面交互测试，最后检查压缩包解压后的启动情况。

GPU 组件按 RTX 5080 Laptop 目标裁剪，打包前后检查 SM120 内核、运行库依赖、模型和预设。界面测试使用 Windows 软件渲染；实际 GPU 推理性能需要在对应设备上测试。

## 基于的项目

| 项目 | 用途 |
|---|---|
| [mpv-AnimeJaNai](https://github.com/the-database/mpv-AnimeJaNai) | AnimeJaNai 核心体系 |
| [AnimeJaNaiManager](https://github.com/the-database/AnimeJaNaiManager) | 配置管理器 |
| [animejanai-inference](https://github.com/the-database/animejanai-inference) | AI 推理 |
| [mpv](https://github.com/mpv-player/mpv) | 播放器核心 |
| [mpv.net](https://github.com/mpvnet-player/mpv.net) | Windows 播放器界面 |
| [thumbfast](https://github.com/po5/thumbfast) | 本地视频进度缩略图 |
| [TensorRT](https://github.com/NVIDIA/TensorRT) | NVIDIA GPU 推理后端 |

## 许可证

各组件使用各自的许可证。许可证和第三方声明随程序包保留。
