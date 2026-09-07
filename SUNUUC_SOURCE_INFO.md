# mpv.net Player UI 兼容修改源码

本分支对应 main 中分发的 mpvnet.exe。

- 上游项目：https://github.com/mpvnet-player/mpv.net
- 基础版本：v7.1.2.0
- 上游许可证：GPL-2.0
- 修改内容：在 src/MpvNet/CommandLine.cs 中忽略 Player UI 外部播放器调用可能传入的 `--{` 与 `--}` 两个参数，避免被 mpv.net 当作属性解析。
- 构建命令：

```powershell
dotnet publish src/MpvNet.Windows/MpvNet.Windows.csproj -c Release -r win-x64 --self-contained false -o mpvnet-publish
```

除上述兼容修改外，源码基线保持 mpv.net v7.1.2.0。
