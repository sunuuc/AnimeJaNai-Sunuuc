# 安全发布说明

## 2026-10-01 发布暂停

360 云查杀报告 `Trojan.Generic`；用户提供的 360 静态分析报告给出的规则为 `Win64/Heur.Generic.H8oAbrkA`。

受影响文件为 `animejanai/danmaku/DanmakuFactory.exe`，524.50 KiB：

- SHA-256：`db3734fb45118ba08c4929214d4aef000875c2e80ac04130651bc482e5d9b58f`
- MD5：`bbbfb71e4f670c9d9fec22dcbeb40f4f`

已将正式版 1.1.9 改为草稿，暂停公开下载。原副本维持隔离。不会将改名、加壳、修改无关字节或要求用户关闭杀毒作为解决办法。

该文件由固定来源的 DanmakuFactory 源码和固定哈希的工具链构建，未进行 Authenticode 签名。源码审计未发现新增联网、进程注入或自启动代码。ClamAV 1.5.4 独立扫描发布副本和本地重建副本均未检出，但单一引擎扫描通过不能推翻 360 的报告。重建副本未逐字节复现发布副本，不能将其用作原副本安全的证明。

尚未确认真阳性或误报，也未取得 360 官方复核结论。此前功能测试没有覆盖杀毒检测。

## 重新发布条件

1. 完成源码、构建来源和发布文件身份核查。
2. 弹幕转换器取得针对最终文件 SHA-256 的 360 官方复核结果。仅有截图中的机器扫描结果或其他引擎未检出不算官方复核通过。
3. 在 `tools/standalone/security-policy.json` 记录复核供应商、文件路径、最终 SHA-256、`clean` 结论和官方复核编号。对本次已报告哈希的阻断，仅能依据正式复核结论进行代码审查后调整。
4. 对最终发布的可执行文件、原生库和脚本运行固定来源的 ClamAV，使用新下载的官方数据库；规则过期、扫描不完整、检出或扫描器失败都阻断发布。
5. 打包、重新解压及正式发布前重新核对扫描清单。文件变更、策略变更或扫描记录超过 24 小时均需要重新检查。

代码签名用于确认发行者身份和文件完整性，需要合法可信的签名证书及私钥，不能伪造发行者或使用自签名证书冒充可信签名。若配置代码签名，应先完成签名，再对最终字节扫描及提交复核；签名本身不保证杀毒软件永远不会报警。

## 执行

```powershell
python tools/standalone/test_security_verify.py
python tools/standalone/security_verify.py preflight
python tools/standalone/security_verify.py scan stage complete-evidence/security
```

扫描工具只存在于构建缓存，不随应用分发；检查不会修改用户的杀毒设置，不会执行待扫描程序。当前策略存在待复核项，安全检查必须失败，直到取得并审核真实的官方结论。

官方说明：[360 软件复核入口](https://open.soft.360.cn/report.php)、[ClamAV 扫描说明](https://docs.clamav.net/manual/Usage/Scanning.html)、[Microsoft SignTool](https://learn.microsoft.com/en-us/windows/win32/seccrypto/signtool)。
