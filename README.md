# mpv-AnimeVE

简体中文 | [English](README.en.md)

Windows 动漫播放器，支持 AI 超分、RIFE 补帧和在线／本地弹幕。

[下载](https://github.com/sunuuc/mpv-AnimeVE/releases/latest) · [更新日志](CHANGELOG.md) · [使用说明](docs/standalone.md) · [问题反馈](https://github.com/sunuuc/mpv-AnimeVE/issues)

## 功能

- **AI 超分与补帧**：多模型处理链、RIFE 补帧、可调倍率，以及按分辨率和帧率启用的自定义方案。
- **按需下载模型**：可自行选择选择模型和显卡组件。安装包不内置模型。
- **弹幕**：多线路搜索、自动切换来源；支持本地 XML。
更多功能等你来探索

## 安装

需要 Windows 64 位系统。

1. 在 [Releases](https://github.com/sunuuc/mpv-AnimeVE/releases/latest) 下载 `mpv-AnimeVE-*-win-x64.7z` 并解压。
2. 运行 `AnimeVE.exe`，打开链接或拖入视频。
3. 需要超分／补帧时，打开 `AnimeVEManager.exe`，在“组件”页选择下载相应模型，再到“配置方案”中启用。


## 使用

### 超分与补帧

在管理器“组件”页选择推荐项或手动勾选，点击“应用”下载。NVIDIA 显卡可选择 TensorRT，AMD / Intel 显卡可使用 DirectML；后端和处理方案在管理器中设置。

在“配置方案”中选择超分模型、补帧倍率和启用条件，然后设为默认方案。首次使用 TensorRT 模型需要生成引擎缓存。

### 弹幕

在播放器“设置 → 弹幕设置 → 弹幕线路”中添加线路并排序；播放时自动匹配，也可在底栏弹幕菜单中搜索和选集。字号、速度、显示区域及屏蔽选项在“弹幕设置”中调整。

本地弹幕使用“导入本地弹幕”；同目录与视频同名的 XML 文件可自动加载。本地字幕使用字幕菜单中的“导入本地字幕”。

### 常用快捷键

| 按键 | 功能 |
| --- | --- |
| 空格 | 播放／暂停 |
| 左／右 | 后退／前进 5 秒 |
| 上／下 | 调整音量 |
| 双击 | 切换全屏 |
| Esc | 返回菜单或退出全屏 |
| Tab | 显示／隐藏 mpv 完整统计 |
| Ctrl+E | 打开配置管理器 |
| Ctrl+J | AI 状态与实际 FPS |
| Ctrl+1–9 | 切换自定义方案 |
| Ctrl+0 | 关闭 AI 处理 |

## 文档与来源

[配置说明](docs/standalone.md) · [构建](docs/build.md) · [弹幕渲染](docs/danmaku-renderer.md) · [来源与第三方许可](docs/open-source-notices.md)

基于 [mpv-AnimeJaNai](https://github.com/the-database/mpv-AnimeJaNai)、[mpv.net](https://github.com/mpvnet-player/mpv.net) 和 [mpv](https://github.com/mpv-player/mpv)。
