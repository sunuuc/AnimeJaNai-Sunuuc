# AnimeJaNai-zh-CN

AnimeJaNai 的中文整合与独立完整便携发行版。

> **当前唯一支持版本：1.0.0 完整独立便携版。**
>
> 旧的 3.6.0、r2、r3、r4 覆盖包已经停止分发，不要继续下载或安装。它们存在已知问题，也不再提供支持。

## 下载

- **[下载 AnimeJaNai-zh-CN 1.0.0 完整版](https://github.com/sunuuc/AnimeJaNai-zh-CN/releases/tag/standalone-v1.0.0)**
- **[直接下载 Windows x64 完整包](https://github.com/sunuuc/AnimeJaNai-zh-CN/releases/download/standalone-v1.0.0/AnimeJaNai-zh-CN-1.0.0-win-x64-full.7z)**
- [完整说明与验证范围](docs/standalone.md)

完整包约 1.59 GiB。SHA-256：

```text
9f90139201edbd61ca0aa7840bef21e8e3e4010e31d80cbab644acecde1e3352
```

## 安装

这是**完整独立版**，不是覆盖补丁。

1. 新建一个空目录。
2. 将 `AnimeJaNai-zh-CN-1.0.0-win-x64-full.7z` 完整解压进去。
3. 运行 `mpvnet.exe` 播放视频。
4. 运行 `AnimeJaNaiManager.exe` 修改 AnimeJaNai 配置。

**不要解压到旧 r2/r3/r4 目录，也不要从旧版复制 scripts、DLL 或更新器过来。**需要迁移个人配置时，优先使用管理器的导出 / 导入功能。

不需要预先安装原版 AnimeJaNai，也不需要另外安装 Python、VapourSynth 或 .NET。NVIDIA 显卡驱动仍需要由 Windows 正常安装。

## 完整包包含

- mpv / mpv.net 播放器及本项目修改
- AnimeJaNai 中文配置管理器
- 简体中文 / English / 跟随系统语言资源
- ModernX 播放控制界面与 thumbfast 缩略图
- 默认快捷键和 Sharp1 / 2K / 4K 预设
- 超分模型与 RIFE 模型
- TensorRT 11.1 运行库
- RTX 20 / 30 / 40 / 50 系列构建内核及 PTX 后备内核
- DirectML / ONNX Runtime
- 本项目自己的更新渠道、完整组件状态与许可证文件

首次使用新的模型 / 分辨率时，TensorRT 仍可能在本机生成对应引擎缓存。这是正常初始化，不代表完整包缺文件。

## 主要修改

- **完整独立发行**：不再要求先下载上游项目再覆盖。
- **中文界面**：管理器和播放器设置均提供中文，语言选择位于管理器的全局设置中。
- **快捷键与起播稳定性**：AI 档位由单一控制器管理，避免多个脚本互相重建滤镜；快速连续切换以最后一次为准。
- **外部播放兼容**：保留每集独立的字幕、标题和播放参数，修复外部播放器连续分集时的参数串集问题。
- **真实 FPS 显示**：`Ctrl+J` 使用播放器原生视频输出计数器计算当前实际 FPS，不再把目标 FPS 当成实际 FPS。
- **独立更新渠道**：`Ctrl+U` 指向本仓库发布页，不会再安装上游整包覆盖本项目。

## 快捷预设

| 快捷键 | 预设 | 1080p / 24fps 示例 |
|---|---|---|
| `Ctrl+1` | 补帧 2× | 1080p 24 → 48fps |
| `Ctrl+2` | 补帧 3× | 1080p 24 → 72fps |
| `Ctrl+3` | 2K 超分｜极速 | → 1440p |
| `Ctrl+4` | 2K 超分｜高质量 | → 1440p |
| `Ctrl+5` | 4K 超分｜高质量 | → 2160p |
| `Ctrl+6` | 2×补帧 + 2K｜极速 | → 1440p 48fps |
| `Ctrl+7` | 2×补帧 + 2K｜高质量 | → 1440p 48fps |
| `Ctrl+8` | 2×补帧 + 4K｜极速 | → 2160p 48fps |
| `Ctrl+9` | 3×补帧 + 2K｜极速 | → 1440p 72fps |
| `Ctrl+0` | 关闭 AI | 原样播放 |

本页中 **2K = 2560×1440**，**4K = 3840×2160**。

## Ctrl+J 实际 FPS

播放时按 `Ctrl+J` 显示 / 隐藏 AnimeJaNai 状态，底部显示：

```text
当前实际 FPS: 47.82 / 目标 47.95
```

“实际 FPS”来自原生 `vo-presented-frame-count` 的帧数增量除以真实经过时间；重复屏幕刷新和 OSD 重绘不会被算成新视频帧。这个数字代表播放器的视频输出提交速率，不是显示器物理扫描频率。

## 语言

管理器 **全局设置 → 界面语言** 可选择：

- 简体中文
- English
- 跟随系统

默认简体中文。修改后完全退出播放器和管理器，再重新打开即可生效。

## 验证

完整包的 CI 会执行：

- 中英文界面与配置读写测试
- 外部播放列表 / 多字幕 / 分集参数测试
- 24 / 48 FPS、半速、慢滤镜等播放器回归
- Lua 控制脚本回归
- 完整组件、模型、配置引用和许可证校验
- 自包含 .NET 验证
- 最终压缩包解压到**空目录**后再次启动播放器、管理器和本地视频

CI 没有用户实际的 NVIDIA GPU 和 Player UI 服务器，因此 **GPU 超分 / 补帧性能以及实际 Player UI 在线播放不属于自动化实机验证范围**。1.0.0 目前标记为预发布。

## 源码与构建

本仓库维护自己的完整发行流程，不再以“下载上游完整包然后让用户覆盖”为发布方式。

- `src/player`：本项目当前播放器源码
- `src/manager`：本项目当前配置管理器源码
- `portable_config`：播放器配置与 Lua 脚本
- `animejanai`：默认配置等项目文件
- `tools/standalone`：完整包组装、校验和发布工具
- `.github/workflows/standalone.yml`：完整独立版 CI / Release 流程

项目仍基于并使用多个开源项目及第三方运行库，并不声称这些底层组件均由本项目从零开发。

## 使用 / 基于的项目

| 项目 | 用途 |
|---|---|
| [the-database/mpv-AnimeJaNai](https://github.com/the-database/mpv-AnimeJaNai) | AnimeJaNai 核心体系与原始实现 |
| [the-database/AnimeJaNaiManager](https://github.com/the-database/AnimeJaNaiManager) | 配置管理器基础 |
| [the-database/animejanai-inference](https://github.com/the-database/animejanai-inference) | TensorRT / DirectML 推理、RIFE 与超分 |
| [mpv-player/mpv](https://github.com/mpv-player/mpv) | 底层播放器 |
| [mpvnet-player/mpv.net](https://github.com/mpvnet-player/mpv.net) | Windows 播放器外壳 |
| [zydezu/ModernX](https://github.com/zydezu/ModernX) | 播放控制界面 |
| [po5/thumbfast](https://github.com/po5/thumbfast) | 进度条视频缩略图 |
| [NVIDIA TensorRT](https://github.com/NVIDIA/TensorRT) | NVIDIA GPU AI 推理后端 |

## 许可证

不同部分继续遵守各自许可证，不能用单一许可证概括整个完整包。对应许可证、来源与构建记录随发布包保留，并在仓库中提供相关源码与说明。

本项目不是 AnimeJaNai 上游官方发布版。感谢 AnimeJaNai、AnimeJaNai Manager、mpv、mpv.net、ModernX、thumbfast、TensorRT 及相关项目开发者。
