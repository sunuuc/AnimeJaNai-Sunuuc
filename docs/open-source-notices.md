# mpv-NekoAnimeVE：来源、修改与第三方许可

## 当前项目

源码、完整修改历史和问题反馈：<https://github.com/sunuuc/mpv-NekoAnimeVE>，维护者 sunuuc。
本项目是修改版发行，并非下列上游项目的官方发行。
修改范围包括品牌与中文界面、播放控制、弹幕搜索与渲染、原生弹幕转换器与 libass 扩展，以及按需组件管理。
源码发行包包含本项目修改过的管理器、播放器、DanmakuFactory 和 libass 源码，以及构建脚本与固定依赖记录。
对应版本请以发行页标签和 `build-info/standalone/provenance.json` 为准。

## 原始项目与核心组件

| 项目 / 作者 | 来源 | 许可证 / 声明位置 |
| --- | --- | --- |
| mpv-AnimeJaNai / the-database | <https://github.com/the-database/mpv-AnimeJaNai> | 根目录 `LICENSE`，CC BY-NC-SA 4.0 |
| AnimeJaNaiManager / the-database | <https://github.com/the-database/AnimeJaNaiManager> | `THIRD_PARTY_LICENSES/AnimeJaNaiManager-GPL-3.0.txt` |
| mpv / mpv contributors | <https://github.com/mpv-player/mpv> | `THIRD_PARTY_LICENSES/mpv-source/`；具体构建包含 GPL/LGPL 组件，保留原声明 |
| mpv.net / stax76 及贡献者 | <https://github.com/mpvnet-player/mpvnet> | `THIRD_PARTY_LICENSES/mpv.net-LICENSE.txt` |
| DanmakuFactory / hihkm 及贡献者 | <https://github.com/hihkm/DanmakuFactory> | MIT，`THIRD_PARTY_LICENSES/DanmakuFactory-MIT.txt`；修改源码在 `third_party/danmaku-factory` |
| libass / libass contributors | <https://github.com/libass/libass> | ISC，`THIRD_PARTY_LICENSES/libass-ISC.txt`；修改源码在 `third_party/libass` |
| thumbfast / po5 | <https://github.com/po5/thumbfast> | `THIRD_PARTY_LICENSES/thumbfast-LICENSE.txt` |
| PCRE2 / Philip Hazel 及贡献者 | <https://github.com/PCRE2Project/pcre2> | BSD，`THIRD_PARTY_LICENSES/PCRE2-BSD.txt` |

组件管理的 NVML 检测、组件包和流式下载来自 mpv-AnimeJaNai 的 `AnimeJaNaiUpdater` 与 `Downloader`。
保留了原有组件管理入口，删除应用自动更新和旧数据迁移代码；增加离线目录、固定散列、解压验证、事务回滚和用户选择。
准确源版本记录在 `build-info/standalone/updater-upstream.json`，构建来源记录在源码包 `tools/standalone/`。

## 模型、界面框架与运行库

- AnimeJaNai 超分模型与项目采用 **CC BY-NC-SA 4.0**。需要署名、限非商业使用、修改后按相同方式共享；完整条件以 `LICENSE` 为准。
- RIFE 来源：<https://github.com/hzwer/ECCV2022-RIFE>，原项目 MIT 原文为 `THIRD_PARTY_LICENSES/RIFE-MIT.txt`；模型由固定版本的上游 AnimeJaNai 组件包提供。保留模型来源，不宣称本项目训练了模型。
- Real-ESRGAN 来源：<https://github.com/xinntao/Real-ESRGAN>；模型使用的架构名称和上游模型文件名保留不变，原项目 BSD 3-Clause 原文为 `THIRD_PARTY_LICENSES/Real-ESRGAN-BSD.txt`。
- .NET 与 Windows Desktop 运行库：MIT，完整原文及 .NET 第三方声明在 `THIRD_PARTY_LICENSES/Microsoft/`。
- SkiaSharp、HarfBuzzSharp：随包保留 NuGet 组件的 MIT 原文于 `THIRD_PARTY_LICENSES/NuGet/`；Inter 字体：SIL OFL 1.1，原文为 `THIRD_PARTY_LICENSES/Inter-OFL-1.1.txt`。
- Avalonia（MIT）：<https://github.com/AvaloniaUI/Avalonia>；FluentAvalonia（MIT）：<https://github.com/amwx/FluentAvalonia>；ReactiveUI（MIT）：<https://github.com/reactiveui/ReactiveUI>。各自的 MIT 原文保留在 `THIRD_PARTY_LICENSES/`。
- TensorRT / CUDA：NVIDIA 厂商许可，**不是开源许可证**；固定运行库版本为 TensorRT 11.1 / CUDA 13.3。原许可与附带第三方声明在 `THIRD_PARTY_LICENSES/NVIDIA/`。
- DirectML（Microsoft 软件许可）：<https://github.com/microsoft/DirectML>；ONNX Runtime（MIT）：<https://github.com/microsoft/onnxruntime>；原声明在 `animejanai/inference/THIRD_PARTY_NOTICES.txt`，许可原文为 `THIRD_PARTY_LICENSES/DirectML.txt` 与 `THIRD_PARTY_LICENSES/ONNX-Runtime-MIT.txt`。
- mpv 所使用的 FFmpeg、MSYS2 及其他依赖的逐项原许可保留在 `THIRD_PARTY_LICENSES/MSYS2/` 与原包 `licenses/`（如附带），不能用本项目的一份许可证替代。新增许可文件的来源与 SHA-256 在 `THIRD_PARTY_LICENSES/sources.json`。

播放器包不内置模型或 TensorRT 显卡组件。可选模型下载地址、版本、字节数和 SHA-256 写入本地目录；只在用户点击安装后下载。
基础播放器的开源许可、模型的非商业条款和厂商运行库条款分别适用；本项目名称和“关于”页不改变这些条件。

## 再分发

再分发时保留本文件、版权声明、许可证原文，以及所分发二进制对应的修改源码和构建说明。
不能将本修改版冒称为上游官方产品；不能将 CC BY-NC-SA 或 NVIDIA 厂商条款概括成允许任意商业使用的开源许可。
各依赖的完整许可原文优先于这里的简短介绍。
