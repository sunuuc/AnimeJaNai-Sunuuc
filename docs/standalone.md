# AnimeJaNai-zh-CN 1.0.1

Windows x64 版本。

## 使用

1. 解压 `AnimeJaNai-zh-CN-1.0.1-win-x64-full.7z`。
2. 运行 `mpvnet.exe` 播放视频。
3. 需要调整 AI 配置时运行 `AnimeJaNaiManager.exe`。

播放器、AI 模型和运行库均包含在压缩包内，不需要另外安装 .NET、Python 或 VapourSynth。NVIDIA 显卡驱动由系统安装。

首次使用某个模型或分辨率时，TensorRT 可能需要生成一次引擎缓存，之后会直接复用。

## 包含内容

- mpv / mpv.net 播放器
- AnimeJaNai 配置管理器
- 简体中文、English、跟随系统三种界面语言
- ModernX 控制栏和 thumbfast 缩略图
- 2K / 4K AI 超分与 RIFE 补帧预设
- TensorRT 11.1 运行库
- RTX 20 / 30 / 40 / 50 系列构建内核与 PTX 后备内核
- DirectML / ONNX Runtime

## 快捷键

| 快捷键 | 功能 |
|---|---|
| `Ctrl+1` | 补帧 2× |
| `Ctrl+2` | 补帧 3× |
| `Ctrl+3` | 2K 超分｜极速 |
| `Ctrl+4` | 2K 超分｜高质量 |
| `Ctrl+5` | 4K 超分｜高质量 |
| `Ctrl+6` | 2×补帧 + 2K｜极速 |
| `Ctrl+7` | 2×补帧 + 2K｜高质量 |
| `Ctrl+8` | 2×补帧 + 4K｜极速 |
| `Ctrl+9` | 3×补帧 + 2K｜极速 |
| `Ctrl+0` | 关闭 AI |
| `Ctrl+J` | 显示 / 隐藏 AnimeJaNai 状态 |
| `Ctrl+E` | 打开 AnimeJaNai 管理器 |

## Ctrl+J

状态栏显示实际视频输出 FPS 与目标 FPS，例如：

```text
当前实际 FPS: 47.82 / 目标 47.95
```

## 文件

- `AnimeJaNai-zh-CN-1.0.1-win-x64-full.7z`：Windows x64 完整包
- `AnimeJaNai-zh-CN-1.0.1-sources.zip`：对应源码
- `SHA256SUMS.txt`：文件校验值

## 许可证

AnimeJaNai、mpv、mpv.net、AnimeJaNaiManager、ModernX、thumbfast、TensorRT 及其他组件按各自许可证分发。许可证和第三方声明随程序包提供。
