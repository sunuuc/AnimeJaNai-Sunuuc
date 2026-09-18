# AnimeJaNai-zh-CN 1.1.4

Windows x64 视频播放器，面向 NVIDIA GeForce RTX 5080 Laptop GPU，支持动漫 AI 超分和 RIFE 补帧。

## 使用

解压 `AnimeJaNai-zh-CN-1.1.4-rtx5080-laptop-win-x64-full.7z`，运行 `mpvnet.exe`。配置管理器为 `AnimeJaNaiManager.exe`。

包内包含 TensorRT 运行库、SM120 内核、超分与补帧模型。显卡驱动由系统安装，首次使用模型时在本机生成引擎缓存。

支持通过视频地址、播放列表、启动脚本或 IPC 接收外部播放请求。启动脚本和脚本参数在播放器初始化前加载。

## 播放界面

底栏提供播放、进度、音量、倍速、音轨、字幕、弹幕、设置和全屏。设置中可选择超分与补帧预设，查看统计信息及性能。主字幕与第二字幕可以分别选择。

网络视频显示当前读取速度，不生成进度缩略图、不预读下一项。外部播放列表直接打开指定项目。

诊断文件位于 `portable_config`：`startup-diagnostic.json` 记录调用方式和加载阶段，`playback-diagnostic.json` 记录播放状态；均不记录媒体地址或认证参数。

## 快捷键

| 按键 | 功能 |
|---|---|
| 上 / 下 | 音量 +5 / −5 |
| 左 / 右 | 后退 / 前进 5 秒 |
| 空格 | 播放 / 暂停 |
| Esc | 返回上级菜单、关闭菜单或退出全屏 |
| Ctrl+1～Ctrl+9 | 切换 AI 预设 |
| Ctrl+0 | 关闭 AI |
| Ctrl+J | AnimeJaNai 状态与实际 FPS |
| Ctrl+E | 配置管理器 |

## 文件

- `AnimeJaNai-zh-CN-1.1.4-rtx5080-laptop-win-x64-full.7z`：完整程序
- `AnimeJaNai-zh-CN-1.1.4-sources.zip`：源码
- `SHA256SUMS.txt`：校验值

## 许可证

AnimeJaNai、mpv、mpv.net、AnimeJaNaiManager、thumbfast、TensorRT 及其他组件按各自许可证分发。第三方声明随程序包提供。
