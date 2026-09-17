# AnimeJaNai-zh-CN 1.1.1

Windows x64 视频播放器，支持 AI 超分、RIFE 补帧和中文配置管理。

## 使用

解压 `AnimeJaNai-zh-CN-1.1.1-win-x64-full.7z`，运行 `mpvnet.exe`。调整 AI 配置时打开 `AnimeJaNaiManager.exe`。

播放器、模型和运行库均包含在包内。首次使用某个模型或分辨率时，需要等待 TensorRT 生成引擎缓存。显卡驱动由系统安装。

## 播放界面

底栏提供播放、进度、音量、倍速、音轨、字幕、弹幕、设置和全屏。网络视频的读取速度显示在右上角。

倍速采用窄幅菜单；字幕菜单可以分别选择主字幕和第二字幕。弹幕菜单显示已加载文件与条数，支持导入本地 XML。

设置菜单包含缩放模式、超分与补帧、字幕设置、弹幕设置、统计信息和性能统计。子菜单向侧边展开，长列表支持滚轮和拖动滚动条。

播放列表从右侧展开，按传入的标题和顺序选播。有多个视频时才显示播放列表按钮。

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

## 文件

- `AnimeJaNai-zh-CN-1.1.1-win-x64-full.7z`：完整程序
- `AnimeJaNai-zh-CN-1.1.1-sources.zip`：源码
- `SHA256SUMS.txt`：校验值

## 许可证

AnimeJaNai、mpv、mpv.net、AnimeJaNaiManager、thumbfast、TensorRT 及其他组件按各自许可证分发。第三方声明随程序包提供。
