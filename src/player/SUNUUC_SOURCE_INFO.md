# mpv.net Player UI 外部调用修复 r2

基线：mpvnet-player/mpv.net v7.1.2.0，GPL-2.0。本分支保留完整修改源码。

此前跳过 `--{`/`--}` 的补丁会把分集字幕、标题和起播位置混成全局参数。
现保留分组，通过 `loadfile URL mode -1 options` 绑定文件局部选项。
带分组、独立 IPC 或显式字幕的调用使用独立进程，避免旧单实例转发丢失参数。
UTF-8 字节长度引用保护中文、逗号、等号及签名 URL；重复的外部字幕不被覆盖。
普通本地打开保留旧单实例行为，不修改服务器媒体或字幕名称，不输出完整带令牌启动命令。

测试：`dotnet run --project tests/ScopedCommandLine -c Release`
构建：`dotnet publish src/MpvNet.Windows/MpvNet.Windows.csproj -c Release -r win-x64 --self-contained false -o publish`

这里支持明确测试过的命令行形式，不宣称完整重新实现 mpv 的全部命令行语法。原生播放器底层构建、Lua 脚本和发布验证在 main 分支。
