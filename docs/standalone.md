# AnimeJaNai-zh-CN 1.1.2

Windows x64 视频播放器，支持 AI 超分、RIFE 补帧和中文配置管理。

## 使用

解压 `AnimeJaNai-zh-CN-1.1.2-win-x64-full.7z`，运行 `mpvnet.exe`。配置管理器为 `AnimeJaNaiManager.exe`。

模型和运行库已包含在包内。首次使用某个模型或分辨率时，需要等待 TensorRT 生成引擎缓存。

## 播放界面

底栏提供播放、进度、音量、倍速、音轨、字幕、弹幕、设置和全屏。设置中可以选择超分与补帧预设，查看统计信息及性能。主字幕与第二字幕可以分别选择。

界面采用较小的默认尺寸。网络视频显示当前读取速度，不生成进度缩略图、不预读下一项。外部播放列表直接打开指定项目。

播放失败时显示错误；不含地址和认证参数的诊断记录保存在 `portable_config/playback-diagnostic.json`。

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

- `AnimeJaNai-zh-CN-1.1.2-win-x64-full.7z`：完整程序
- `AnimeJaNai-zh-CN-1.1.2-sources.zip`：源码
- `SHA256SUMS.txt`：校验值

## 许可证

AnimeJaNai、mpv、mpv.net、AnimeJaNaiManager、thumbfast、TensorRT 及其他组件按各自许可证分发。第三方声明随程序包提供。
