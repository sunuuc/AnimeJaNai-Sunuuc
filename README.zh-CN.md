# mpv-AnimeVE

[English](README.md) | 简体中文

面向动漫观看的 Windows 视频播放器，支持弹幕、可选 AI 超分与补帧。基于 [mpv-AnimeJaNai](https://github.com/the-database/mpv-AnimeJaNai)、[mpv.net](https://github.com/mpvnet-player/mpv.net) 和 [mpv](https://github.com/mpv-player/mpv)。

[下载](https://github.com/sunuuc/mpv-AnimeVE/releases/latest) · [问题反馈](https://github.com/sunuuc/mpv-AnimeVE/issues)

## 功能

- 播放本地文件、网络视频及外部播放列表。
- 播放控制、章节标记、音轨选择和双字幕。
- 在线与本地弹幕、线路并行搜索、类型屏蔽和屏蔽词。
- 可选 AI 超分与 RIFE 补帧，模型和显卡组件单独下载。
- 中英文配置管理器，提供硬件推荐和组件下载，使用 SHA-256 校验下载文件。

## 开始使用

1. 从 Releases 下载 `mpv-AnimeVE-*-win-x64.7z`，解压到本地目录。
2. 运行 `AnimeVE.exe`，打开视频。
3. 需要 AI 处理时，打开 `AnimeVEManager.exe`，在“组件”页下载所需模型与显卡组件，再配置处理方案。

需要 Windows x64。便携包包含应用运行库，无需另装 .NET、Python 或 VapourSynth。默认普通播放；AI 性能取决于模型与显卡。

NVIDIA 显卡使用对应代际的 TensorRT 组件，AMD / Intel 显卡可使用内置 DirectML 后端。显卡驱动需自行安装。

在线弹幕需在“设置 → 弹幕设置”中添加线路；发布包不含个人线路与密钥。也可在弹幕菜单中导入本地 XML。

## 快捷键

| 按键 | 功能 |
| --- | --- |
| 空格 | 播放 / 暂停 |
| 左 / 右 | 后退 / 前进 5 秒 |
| 上 / 下 | 调整音量 |
| 双击 | 切换全屏 |
| Esc | 返回 / 关闭菜单 / 退出全屏 |
| Tab | 显示 / 隐藏 mpv 完整统计 |
| Ctrl+J | AI 状态与实际 FPS |
| Ctrl+E | 打开配置管理器 |
| Ctrl+1–9 | 选择对应 AI 配置方案 |
| Ctrl+0 | 关闭 AI 处理 |

## 配置

播放器设置位于 `portable_config`，AI 配置方案位于 `animejanai/animejanai.conf`。在管理器全局设置中切换界面语言，重启播放器和管理器后生效。

[详细使用说明](docs/standalone.md) · [弹幕渲染说明](docs/danmaku-renderer.md)

## 构建

播放器和管理器源码位于 `src/player`、`src/manager`，便携包构建工具位于 `tools/standalone`。[Windows 构建流程](.github/workflows/standalone.yml) 使用固定依赖完成编译、测试、扫描和打包。

## 来源与许可

由 [sunuuc](https://github.com/sunuuc) 维护。上游作者与组件许可见[来源及第三方声明](docs/open-source-notices.md)，完整许可原文保留在 [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES)。
