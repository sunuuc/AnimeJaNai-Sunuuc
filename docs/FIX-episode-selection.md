# 修复记录：Player UI 传多个播放列表导致的选集错误

## 0. 最终根因（2026-09-19 21:35 由真实 `argv_shape` 定案）

真实调用（`mpvapp` 的 `startup-diagnostic.json`）：

```json
"argv_shape": ["--script=<path>",
  "--{", "--playlist=<url:562dc329>", "--sub-file=<url:9e50e021>",
         "--force-media-title=<text:36>", "--start=<num>", "--aid=<num>", "--sid=<num>", "--}",
  "--{", "--playlist=<url:b8ad28e1>", "--sub-file=<url:2d76f425>",
         "--force-media-title=<text:25>", "--}",
  "--force-window=<text:9>"]
```

**这不是「一个列表选一集」，而是两组各自独立的播放项**：每组有自己的列表、字幕、标题；
组 1 还带 `--start`（续播位置）→ 组 1 是正在看的那一集，组 2 是排队的下一集。

空参数组的选项被**全部提升成全局**，于是两个 `--force-media-title` **后者胜**：
画面放组 1 的片子，标题和字幕却是**组 2 的** —— 这就是用户说的「集数不对应」。

### 修复

1. `ScopedCommandLine`：新增 `EmptyGroupOptions`，按组保留每个空组的选项（原先只有扁平化后的
   `PromotedOptions`，丢失了分组归属）。
2. `CommandLine.ScopedPlaylistGroups()`：取出「带 playlist 的空组」，按顺序返回
   `(列表, 该组选项)`；**没有空组时回落到全局 `--playlist`**（否则全局写法会被完全忽略）。
3. `CommandLine.BuildArguments()`：当这样的组 ≥2 个时，把它们的**每项选项**
   （`sub-file / force-media-title / start / sid / aid / …`）从全局参数里**摘掉**，不再污染会话。
4. `CommandLine.ProcessCommandLineFiles()`：≥2 组时逐组处理 ——
   `loadlist` 载入该组列表 → 读出刚加入的那一条 `playlist/N/filename` →
   `playlist-remove` 摘掉 → 再用 **`loadfile <条目URL> append -1 "<该组选项>"`** 挂回去。

   这一步是必需的：实验证明 **playlist URL 无法携带 file-local 选项**
   （`loadfile <m3u> append -1 "force-media-title=X"` 会把列表展开成 2 条，但 `media-title`
   仍是文件名而不是 X）。先 loadlist 再单独重挂，选项才真正绑到条目上。

### 验证

合成复现（两组、两个标题、两个字幕）：

| | 结果 |
|---|---|
| 修复前 | 只请求 B 列表；标题 = 组 2 的 |
| 修复后 | `requests: ['/A.m3u','/B.m3u','/a1.y4m','/s1.srt']`、`count=2`、`pos=0`、**`media_title='TITLE_A'`**、字幕 `s1.srt` 已选中、`option_error=null` |

门槛：`test_player_ui_logic.lua` 6907 断言 PASS；`test_player_ui_empty_scope.py` 3/3 PASS
（`wrong_episode_requests: 0`）；`test_network_playback.py` 22/22 PASS；
`AnimeJaNaiUpdater --verify` 388 文件全过。

> 两次环境噪声已识别：① 某轮网络门槛 5 个用例全 `phase: failed`，是紧接着跑合成探针留下的
> 进程/端口干扰，隔 4 秒单独重跑即 22/22；② `idle-and-ipc` 曾因 OSD 比宿主窗口先就绪而失败，
> 已在 `tests/capture_window.py` 加有界重试修掉。

---

日期：2026-09-19
现象：从 Player UI 打开某一集，播放的不是那一集。

---

## 1. 之前的两次判断都错了

| 曾经以为 | 实际情况 |
|---|---|
| 1.1.5 打开播放列表首项 → 升级到 1.1.6 即可 | 升级后仍错误 |
| Player UI 用 `--playlist-start` 指定集数，可能 0/1 基不一致 | **Player UI 根本不传 `--playlist-start`** |

真实数据来自 `portable_config/startup-diagnostic.json`：

```json
"argument_count": 15,
"empty_scope_count": 2,
"empty_scope_options_promoted": 9,
"promoted_option_names": ["aid","force-media-title","playlist","sid","start","sub-file"],
"playlist_option_count": 2,          ← --playlist 传了两次
"playlist_start_option_count": 0,    ← 完全没有 --playlist-start
"playlist_start_kind": "none",
"playlist_count": 1,                 ← 只有最后一个列表被加载
"playlist_current_pos": 0
```

Player UI 的调用形状是：

```
mpvnet.exe --script=<启动脚本> \
  --{ --playlist=<列表A> --start=<续播秒> --force-media-title=<标题> \
      --sid=… --aid=… --sub-file=… --} \
  --{ --playlist=<列表B> --}
```

两个空 `--{ … --}` 组、两个 `--playlist`。

---

## 2. 根因

`playlist` 在 mpv 里是 **String** 类型（实测 `option-info/playlist/type = String`），
不是列表型。所以无论是 mpv 自己处理、还是原来的实现，**重复传入只有最后一个生效**：

```csharp
string playlist = GetValue("playlist");   // GetValue 从后往前找 → 只拿到最后一个
Player.CommandV("loadlist", playlist, "append");
```

于是 **列表 A 被静默丢弃**，播放器只用列表 B 建立播放列表。
`GetValue` 的「取最后一个」正好与 mpv 自身的语义一致 —— 但这正是问题所在：
**调用方传两个列表，就是要两个都生效。**

合成复现（两个列表：A 是 5 集，B 是 1 集）：

| | 请求的 URL | playlist_count |
|---|---|---|
| 修复前 | `/single.m3u`, `/s1.y4m` | 1 |
| 修复后 | `/window.m3u`, `/single.m3u`, `/w1.y4m` | 6 |

修复后播放的是**列表 A 的第 0 项**，也就是调用方选中的那一集。

---

## 3. 修改

### `src/player/src/MpvNet/CommandLine.cs` — `ProcessCommandLineFiles()`

按参数顺序加载**每一个** `--playlist`：

```csharp
List<string> playlists = Arguments.Where(p => p.Name == "playlist")
    .Select(p => p.Value).Where(v => v.Length > 0).ToList();
...
foreach (string list in playlists)
    Player.CommandV("loadlist", MainPlayer.ConvertFilePath(list), "append");
```

其余逻辑（`loadlist` 之后用 `playlist-play-index` 选中目标项，而不是设置
`playlist-pos` 属性）保持不变 —— 它保证了不会先打开列表首项再跳。

### `src/player/src/MpvNet/StartupDiagnostics.cs` — 让诊断能定位这类问题

`startup-diagnostic.json` 此前只记录选项**名字**，看不到结构，所以前两轮都在猜。新增：

- `argv_shape`：**逐条**记录参数形状 —— 选项名 + 值类型 + 8 位 SHA-1 哈希，
  形如 `["--{", "--playlist=<url:7e1508c5>", "--start=<num>", "…", "--}"]`，
  顺序、分组、每个选项出现几次都看得见
- `playlist_hashes`：每个 `--playlist` 值的 8 位哈希（能判断两个列表是否相同）
- `playlist_entry_hashes`：播放列表每一条的 8 位哈希（取 URL 去掉查询串后的部分）

**不记录**任何地址、标题、令牌 —— 只记录名字、类型和不可逆的短哈希。

### `tools/standalone/prepare_playback.py` — 同步过期的补丁

`M.layout` 与选项行被我改写后，脚本里两处 `edit()` 的字面量对不上，会让官方构建流水线
`RuntimeError` 中断。现改为：

- 选项行补丁更新为 `volume_step=5,ui_scale=1.00,text_outline=1,font=`
- 排版补丁换成**契约校验**：要求 `local want=…`、`local w,h=pw,ph`、`return built or` 存在，
  并显式拒绝任何重新引入 `pw/scale`、`pw/920`、`ph/620` 的改动（即不许再重采样 PlayRes）

### `tests/capture_window.py` — 消除一个真实的时序缺陷

`capture_client` 只枚举一次窗口。mpv 的 OSD 可以在宿主窗口显示出来之前就报告就绪，
于是 `idle-ipc` 用例会随机失败（我实测空载 2s/4s/8s 时窗口都是可见的 1086×611，
说明窗口本身没问题，是采样过早）。改为**有界重试**（最多 5 秒，每 100ms 一次）：
窗口出现即返回，始终不出现仍照常报错。

---

## 4. 验证

| 测试 | 结果 |
|---|---|
| 合成复现（两个列表） | 修复前只请求 B；修复后按序请求 A、B，播放 A 的第 0 项，`playlist_count=6` |
| `tests/test_player_ui_logic.lua` | **PASS，6907 条断言** |
| `tests/test_player_ui_empty_scope.py` | **3/3 PASS**（含 `wrong_episode_requests: 0`） |
| `tests/test_network_playback.py` | **22/22 PASS，exit 0**（含 `start at selected episode without opening first`、`playlist option starts only selected item`） |
| `AnimeJaNaiUpdater.exe --verify` | `{"ok":true,"failed":[]}`（355 个文件） |
| 四个预处理脚本 | 全部 exit 0 |

---

## 5. 部署

| 位置 | 状态 |
|---|---|
| `D:\CODE\AnimeJaNai-zh-CN\mpvapp\mpvnet.exe` | 已更新（`F5B517FC…`） |
| `D:\Apps\mpv-AnimeJaNai\mpvnet.exe`（Player UI 实际调用） | 已更新，哈希一致 |
| `portable_config/{scripts/player_ui.lua, script-modules/player_ui_core.lua, script-opts/player_ui.conf}` | 三处哈希一致 |

---

## 6. 下一步

请在 Player UI 里再开一集。如果**还是**不对，`startup-diagnostic.json` 里的
`argv_shape` 与 `playlist_*` 现在能直接指出问题在哪，不必再猜：

- `playlist_option_count` 是几、`playlist_hashes` 有几个不同值
- `playlist_count` 与 `playlist_current_pos`（播的是第几项）
- `playlist_entry_hashes` 的顺序
- `argv_shape` 的完整顺序与分组结构

我照着这几个字段就能判断是「列表顺序不对」还是「该跳的项没跳」。
