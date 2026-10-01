# 弹幕实现

使用 [DanmakuFactory](https://github.com/hihkm/DanmakuFactory) 的 CLI 转换弹幕，并在转换器源码中增加播放倍速参数，mpv/libass 原生第二字幕轨负责播放 ASS 动画和屏幕坐标映射。源码固定在 `third_party/danmaku-factory/UPSTREAM.json` 指定的提交，安装文件按 SHA-256 验证。

弹幕读取完成后异步转换一次。滚动位置、防碰撞、类型屏蔽由 DanmakuFactory 排布；暂停、变速、跳转、窗口大小变化由 mpv 原生字幕处理。没有 Lua 逐帧轮询、OSD 字符串重建、模拟播放时钟或自定义刷新率。原视频字幕保留在主字幕轨，弹幕使用第二字幕轨。

弹幕设置只提供显示区域、不透明度、弹幕字号、速度、固定/滚动/彩色类型屏蔽和屏蔽词。显示区域与不透明度用百分比显示；速度用倍率显示，数值越大越快。1× 对应滚动 12 秒、固定 5 秒，2× 对应 6 秒和 2.5 秒。显示区域统一限制所有普通弹幕，不再另设滚动区域。

配置保存于 `%LOCALAPPDATA%/AnimeJaNai-DanmakuFactory.json`，按上游参数写入。屏蔽词保存在 `%LOCALAPPDATA%/AnimeJaNai-danmaku-blocklist.txt`，每行一个词，采用普通文本包含匹配，保存后重新转换当前弹幕。编辑窗口使用 mpv.net 的 WPF 文本框、主题和播放器窗口归属关系。弹幕线路管理位于“设置 → 弹幕设置 → 弹幕线路”，已有 API 配置保留。

原有逐帧引擎的 `AnimeJaNai-danmaku-display.conf` 已弃用，不读取旧值。用户的弹幕 API 线路配置继续保留。

ASS 的运动帧率受 mpv 实际视频呈现节奏限制。高刷新率屏幕不等于弹幕自动达到该刷新率，不再显示用 Lua 提交次数计算的“弹幕 FPS”。

自动搜索对每条线路并行发送一次作品查询，不进行自动重试。首个返回季集匹配的线路立即尝试获取弹幕，无需等全部搜索结束。若该集为空，按保存列表从上到下继续检查其他线路和平台；上移/下移修改此优先级。加载到非空弹幕后停止本次匹配。“当前线路”不再是配置选项。手动点击搜索可重新发起查询。

## 播放布局与速度

弹幕使用完整播放器区域，包括上下或左右黑边。播放配置在托管配置之后设置 `blend-subtitles=no`，字幕按屏幕坐标合成。转换器仅生成固定 ASS 逻辑坐标；libass 在当前渲染帧内映射到整个窗口，字形保持等比缩放。改变窗口大小或切换全屏不重新转换或替换弹幕轨道。视频倍速只改变弹幕出现的媒体时间；滚动及固定弹幕的实际持续时间由弹幕速度设置决定。切换视频倍速时按已播放的时间和倍速记录保持当前位置。倍速或跳转变化只触发一次异步转换；没有逐帧查询或重画弹幕。

构建：`python tools/standalone/build_danmaku_factory.py --output publish-danmaku/DanmakuFactory.exe`。构建工具固定校验 Zig 0.14.1 和 PCRE2 10.46 的 SHA-256，直接编译 vendored C 源码；发布时不再使用上游预编译文件。

完整窗口的裁剪由同一版本的 libass 源码处理，固定提交见 `third_party/libass/UPSTREAM.json`。仅带 `RenderInMargins: yes` 的弹幕 ASS 使用完整窗口边界，普通字幕保持视频边界。原生 SIMD、DirectWrite 和多线程保留。构建：`python tools/standalone/build_libass.py --output publish-native/libass-9.dll`；需要 Python 3.14，MSYS2 UCRT64 构建依赖版本和 SHA-256 固定在 `tools/standalone/libass-build-packages.json`。
