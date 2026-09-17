# AnimeJaNai-zh-CN 1.1.0

Windows x64 视频播放器，支持 AI 超分、RIFE 补帧和中文配置管理。

## 使用

解压完整包，运行 `mpvnet.exe`。配置管理器为 `AnimeJaNaiManager.exe`。

播放器、模型和运行库已包含在包内。首次使用某个模型或分辨率时，需要等待 TensorRT 生成引擎缓存。显卡驱动由系统安装。

## 播放界面

底部控制栏提供播放、进度、音量、倍速、音轨、字幕、弹幕、AI 预设、统计信息和性能面板。鼠标移开后自动隐藏；右上角显示当前网络视频的读取速度。

播放列表按钮仅在传入多个视频时出现，按实际标题与顺序选播。单个视频的前后按钮用于跳转 10 秒。

弹幕支持导入本地 Bilibili XML 格式文件，也可自动加载视频旁的同名 XML。弹幕与字幕独立显示，支持开关、透明度及显示区域调整。

## 快捷键

| 按键 | 功能 |
|---|---|
| 上 / 下 | 音量 +5 / −5 |
| 左 / 右 | 后退 / 前进 5 秒 |
| 空格 | 播放 / 暂停 |
| Esc | 关闭控制菜单；没有菜单时退出全屏 |
| Ctrl+1 / Ctrl+2 | 2× / 3× 补帧 |
| Ctrl+3 / Ctrl+4 | 2K 超分：极速 / 高质量 |
| Ctrl+5 | 4K 超分：高质量 |
| Ctrl+6 / Ctrl+7 | 2×补帧 + 2K：极速 / 高质量 |
| Ctrl+8 | 2×补帧 + 4K：极速 |
| Ctrl+9 | 3×补帧 + 2K：极速 |
| Ctrl+0 | 关闭 AI |
| Ctrl+J | AnimeJaNai 状态与实际 FPS |
| Ctrl+E | 配置管理器 |

## 文件

- `AnimeJaNai-zh-CN-1.1.0-win-x64-full.7z`：完整程序
- `AnimeJaNai-zh-CN-1.1.0-sources.zip`：源码
- `SHA256SUMS.txt`：校验值

## 许可证

AnimeJaNai、mpv、mpv.net、AnimeJaNaiManager、thumbfast、TensorRT 及其他组件按各自许可证分发。第三方声明随程序包提供。
