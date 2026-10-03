# mpv-AnimeVE 使用说明

## 程序与文件

| 文件 | 用途 |
| --- | --- |
| `mpv-AnimeVE-1.2.3-win-x64.7z` | 播放器便携包 |
| `mpv-AnimeVE-1.2.3-sources.zip` | 对应版本源码 |
| `SHA256SUMS.txt` | 下载校验值 |
| `AnimeVE.exe` | 播放器 |
| `AnimeVEManager.exe` | 配置与组件管理器 |
| `app/AnimeVEUpdater.exe` | 组件管理命令行工具 |

解压播放器包后运行 `AnimeVE.exe`。模型和显卡组件在管理器“组件”页下载。

## 目录

- `AnimeVE.exe`：播放器。
- `AnimeVEManager.exe`：管理器。
- `app`：运行库、语言资源和组件工具。
- `portable_config`：播放器配置。
- `animejanai`：AI 配置、模型和缓存。
- `docs`：文档与许可证。

## 配置

| 位置 | 内容 |
| --- | --- |
| `portable_config/mpv.conf` | mpv 播放选项 |
| `portable_config/AnimeVE.conf` | 播放器前端选项 |
| `portable_config/input.conf` | 快捷键 |
| `portable_config/script-opts/player_ui.conf` | 底栏、时钟及界面设置 |
| `portable_config/script-opts/player_ui_danmaku.conf` | 弹幕脚本选项 |
| `animejanai/animejanai.conf` | AI 后端和处理方案 |

界面语言在管理器全局设置中选择，重启播放器和管理器后生效。自定义方案可设置为默认，也可使用 Ctrl+1–9 切换；Ctrl+0 关闭 AI 处理。

## 弹幕线路与匹配

在“设置 → 弹幕设置 → 弹幕线路”中添加地址，使用上移／下移调整优先级。

自动匹配会并行请求各线路，先使用成功匹配的结果；该集没有弹幕时，再按线路顺序尝试其他来源与平台。每轮自动搜索每条线路只请求一次。手动搜索中可按线路、季度和平台筛选，再选择集数。

线路保存在 `%LOCALAPPDATA%\AnimeVE-danmaku.conf`；字号、速度、显示区域及屏蔽设置保存在 `%LOCALAPPDATA%\AnimeVE-DanmakuFactory.json`。发布包不包含个人弹幕线路，首次使用需自行添加。

弹幕菜单提供“导入本地弹幕”，字幕菜单提供“导入本地字幕”。与视频同名的 XML 弹幕可自动加载。

## 问题反馈

提交 [Issue](https://github.com/sunuuc/mpv-AnimeVE/issues) 时附上版本、显卡型号、启用的处理方案和复现步骤。

启动与播放诊断位于 `portable_config/startup-diagnostic.json`、`portable_config/playback-diagnostic.json`，可用于排查播放列表、加载和缓冲问题。
