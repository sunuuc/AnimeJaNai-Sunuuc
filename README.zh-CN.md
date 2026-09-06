# mpv-AnimeJaNai 简体中文个人版

这是 `sunuuc/mpv-AnimeJaNai` 的个人简体中文分支，基于上游 `the-database/mpv-AnimeJaNai`。

## Windows 使用

在本仓库 Releases 下载：

`mpv-AnimeJaNai-zh-CN-<版本>-win-x64.7z`

解压后即可使用。Player UI PC 中将“外部 mpv 播放器位置”指向解压目录里的 `mpv.exe`。

常用操作：

- `Ctrl+E`：打开中文 AnimeJaNai 管理器。
- `Ctrl+J`：显示/隐藏 AnimeJaNai 状态。
- `Ctrl+U`：检查并安装本简体中文版更新。
- `Shift+1 / Shift+2 / Shift+3`：官方画质 / 均衡 / 性能预设（键位以当前上游实际配置为准）。
- `Ctrl+0`：关闭 AnimeJaNai 超分。

## RTX 50 系列

在“组件”页优先安装软件为当前 GPU 标记的推荐组件，包括 TensorRT 运行库、对应 Blackwell 的 TensorRT 内核包；需要实时补帧时再安装 RIFE 模型。

## 汉化范围

- AnimeJaNai Manager 主界面、帮助说明、组件管理、常见动态状态与弹窗。
- mpv/mpv.net 右键菜单。
- AnimeJaNai 配置切换 OSD。
- TensorRT 首次构建与成功/失败提示。
- 缺少 TensorRT/RIFE 组件时的提示。
- 在线更新提示。

mpv.net 自身生成、且不受本项目配置控制的极少数底层窗口/调试信息可能仍为英文。

## 更新方式

中文版更新器指向 `sunuuc/mpv-AnimeJaNai` 的 Release，不会直接安装官方英文 Release。

仓库每 3 小时检查一次上游公开 Release。发现新版本后会尝试把对应上游代码合入中文版并重新构建。如果上游修改与汉化产生代码冲突，自动发布会停止，而不是把旧代码伪装成新版本。

- `main`：尽量保留上游 Fork 状态，方便比较和同步。
- `zh-CN`：个人简体中文版。

原项目版权、许可证及第三方组件许可证保持不变。
