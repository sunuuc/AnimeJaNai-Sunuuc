# 修复：提交内存异常偏高

## 现象

播放网络视频一段时间后，`mpvnet.exe` 的**提交内存（commit / private bytes）**
涨到 3942 MB，继续播放会一路爬到 4968 MB 且不回落，而实际工作集（working set）
只有约 500 MB。

```
任务管理器「内存」列 ≈ 工作集 500 MB
但「提交大小」≈ 3.9 - 5.0 GB   ← 用户看到的就是这个数
```

## 测量方法

`tools/memprobe.py` 通过 `GetProcessMemoryInfo` 读取真实计数器，避免把工作集
误当成提交量：

```
pid 47368: commit=3942.0MB (peak 3949.7)  private=3942.0MB  ws=509.1MB
```

## 根因

`portable_config/scripts/network_playback.lua` 在 `on_load` 钩子里用
**file-local options** 覆盖了缓存策略，取值远超实际需要：

| 选项 | 本构建默认值 | 修复前 | 实际需要 |
| --- | --- | --- | --- |
| `demuxer-max-bytes` | 150 MiB | **2 GiB** | 768 MiB |
| `demuxer-max-back-bytes` | 50 MiB | **1 GiB** | 384 MiB |
| `vd-queue-max-bytes` | 512 MiB | （未改） | 256 MiB |

默认值来自随附的 mpv 二进制本身，不是推测：

```
--demuxer-max-bytes          ByteSize (default: 150.000 MiB)
--demuxer-max-back-bytes     ByteSize (default: 50.000 MiB)
--vd-queue-max-bytes         ByteSize (default: 512.000 MiB)
```

### 为什么 2 GiB 是纯浪费

按码率把「三分钟超前缓存」换算成实际字节：

| 画质 | 码率 | 3 分钟所需 |
| --- | --- | --- |
| 1080p AV1 | ~5 Mbps | 107 MiB |
| 1080p HEVC | ~8 Mbps | 172 MiB |
| 1080p H.264 | ~12 Mbps | 258 MiB |
| 4K HEVC | ~25 Mbps | 536 MiB |

即使 4K 也只需约 536 MiB。768 MiB 是**最坏情况的 1.4 倍**，已经完全够用；
2 GiB 多出来的一千多兆只是被提交、从未真正用到。

另外 `mpv-animejanai.conf` 里的托管值本来是 `768M / 384M`，Lua 又把它顶成
2 GiB —— 属于同一策略被写了两次，且 Lua 那次赢。

## 修复

`portable_config/scripts/network_playback.lua`：

```lua
['demuxer-readahead-secs']='180',['cache-secs']='180',
['demuxer-max-bytes']='768M',['demuxer-max-back-bytes']='384M',
['vd-queue-max-bytes']='256M',['ad-queue-max-bytes']='512K',
['network-timeout']='20'
```

**保留了用户要求的两点**：缓存仍然在内存里（`cache-on-disk` 保持 `no`），
三分钟超前缓存不变（`demuxer-readahead-secs=180`）。

## 运行期验证

`tools/verify_cache_memory.py` 用 IPC 把播放器**实际解析出的**选项读回来，
确保没有被静默忽略：

```
demuxer-max-bytes          = 805306368      (768 MiB)  ✅
demuxer-max-back-bytes     = 402653184      (384 MiB)  ✅
demuxer-readahead-secs     = 180.0          (3 分钟)   ✅
cache-secs                 = 180.0                     ✅
vd-queue-max-bytes         = 268435456      (256 MiB)  ✅
ad-queue-max-bytes         = 524288         (512 KiB)  ✅
cache-on-disk              = False          (内存)     ✅
```

提交内存采样：

```
   t  commit_MB    ws_MB  cached_MB
   0        495      420        5.6
   2        527      461       30.3
   6        231      326       30.3
  12        232      329       28.3
  22        231      329       23.2

commit: start=495MB  peak=527MB  end=231MB
```

**修复前** 3942 → 4968 MB 持续上涨；**修复后** 稳定在 231 MB。

缓存相关预算合计从 2560 MiB 降到 1024 MiB（少 60%）。

## 顺带修正的过期测试

早前一轮把「性能统计」并入「统计信息」、并移除整个播放列表 UI，但
`tests/test_player_ui_runtime.lua` 没有同步跟进，导致运行时 UI 测试失败：

- 设置菜单里要的行从 `performance` 改成 `stats`；
- 播放列表那一步原先断言抽屉存在，改为断言抽屉**不存在**
  （播放列表本身仍正常加载，只是不再有 UI）；
- 新增 `has_row()` 辅助函数，用于断言某行**不**存在（原来的 `row()` 找不到时会
  直接 `error`，无法用来判断缺失）。

`tests/test_network_playback.py` 里菜单列表同样去掉了 `playlist` / `performance`。

## 一个被否定的假设

`startup-diagnostic.json` 里 `empty_scope_count=5` 一度让人以为 5 集播放列表被
重复加载。实测否定了这一点：

```
group playlist count   = 5
final playlist entries = 5
duplicates in entries  = 0
```

5 个空 `--{ }` 组是 Player UI 的**传输单位**（队列里每集一个组），每组贡献且仅贡献
一个条目，没有重复。诊断里的两次 `media-opening / media-loaded` 是用户切集，
属正常行为。**未做任何改动。**

## 需要重启生效

缓存选项在播放开始时读取。改动只对**新启动**的播放器生效；已经在跑的实例仍按
旧配置持有内存，需退出后重开。
