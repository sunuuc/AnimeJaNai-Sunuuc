# AnimeJaNai-zh-CN 1.1.6

Windows x64 视频播放器，面向 NVIDIA GeForce RTX 5080 Laptop GPU，支持动漫 AI 超分和 RIFE 补帧。

## 使用

解压 `AnimeJaNai-zh-CN-1.1.6-rtx5080-laptop-win-x64-full.7z`，运行 `mpvnet.exe`。配置管理器为 `AnimeJaNaiManager.exe`。

包内包含 TensorRT 运行库、SM120 内核、超分与补帧模型。显卡驱动由系统安装，首次使用模型时在本机生成引擎缓存。

支持通过视频地址、播放列表、启动脚本或 IPC 接收外部播放请求。兼容 Player UI 把媒体参数放在空 `--{ ... --}` 参数组中的调用方式。

1.1.6 将 Player UI 传入的 `playlist` 与 `playlist-start` 在播放器初始化前交给 mpv 原生处理，不再先打开播放列表首项、再手动切换。所选集数、续播位置、标题、字幕和认证参数按同一次启动调用生效。

Player UI 控制栏运行模块已并入脚本，完整包解压到含中文字符的目录时也不需要再通过 Lua `dofile` 打开模块文件。

## 播放界面

底栏提供播放、进度、音量、倍速、音轨、字幕、弹幕、设置和全屏。设置中可选择超分与补帧预设，查看统计信息及性能。主字幕与第二字幕可以分别选择。

网络视频显示当前读取速度，不生成进度缩略图、不预读下一项。外部播放列表由 mpv 在起播前确定目标项目。

诊断文件位于 `portable_config`：`startup-diagnostic.json` 记录调用方式、播放列表选择方式和加载阶段，`playback-diagnostic.json` 记录播放状态；均不记录媒体地址、标题、认证头或令牌。

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

- `AnimeJaNai-zh-CN-1.1.6-rtx5080-laptop-win-x64-full.7z`：完整程序
- `AnimeJaNai-zh-CN-1.1.6-sources.zip`：源码
- `SHA256SUMS.txt`：校验值

## 许可证

AnimeJaNai、mpv、mpv.net、AnimeJaNaiManager、thumbfast、TensorRT 及其他组件按各自许可证分发。第三方声明随程序包提供。
