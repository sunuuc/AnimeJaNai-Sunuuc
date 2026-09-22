# 修复记录：Player UI 传入 playlist 时播放器死锁（选集错误）

日期：2026-09-19
现象：Player UI 通过外部播放器打开某一集时，播放的不是所点的那一集（1.1.5），或播放器完全卡住不启动（1.1.6）。

---

## 1. 实际调用链（实测，非推测）

外部播放器由 Player UI 的 `shared_preferences.json` 决定：

```
C:\Users\howev\AppData\Local\Packages\Mountains.PlayerUI_jja6j3cje9wfy\
  LocalCache\Roaming\com.mountains\Player UI\shared_preferences.json
    flutter.appConfig.externalMpvPath     = "D:\Apps\mpv-AnimeJaNai\mpvnet.exe"
    flutter.appConfig.enableExternalMpv   = true
    flutter.appConfig.externalPlayerEpisodeCount = 5
```

Player UI 传给播放器的形状（来自 `startup-diagnostic.json` 与项目自带的
`tests/test_player_ui_empty_scope.py`）：

```
mpvnet.exe --script=<Player UI 保存的启动脚本> --{
    --playlist=<剧集播放列表>
    --playlist-start=<所选集索引>
    --force-media-title=<标题>
    …（同组内共十余个选项：字幕、起播位置、认证头等）
--}
```

即：**参数放在一个空的 `--{ ... --}` 参数组里**。

---

## 2. 两个独立的问题

### 2.1 已安装的播放器是半更新状态

| 文件 | 1.1.5 | 1.1.6 | 用户安装目录实际是 |
|---|---|---|---|
| `portable_config/scripts/player_ui.lua` | 29,167 B | 58,199 B | **58,199（1.1.6）** |
| `portable_config/scripts/player_ui_danmaku.lua` | 8,089 B | 15,336 B | **15,336（1.1.6）** |
| `mpvnet.exe` | `…-1.1.5+69d8b1ce` | `…-1.1.6+7e397bcd` | **`…-1.1.5+69d8b1ce`** |

Lua 已是新版，二进制仍是 1.1.5。界面看着是新的，起播逻辑还是旧的。

### 2.2 1.1.6 的做法会让 libmpv 死锁（真正要修的地方）

`src/player/src/MpvNet/CommandLine.cs` 在 1.1.6 把 `playlist`、`playlist-start`、`shuffle`
放进 `_preInitProperties`，并在 `mpv_initialize()` **之前**调用
`mpv_set_option_string(handle, "playlist", url)`。

**`playlist` 不是 libmpv 可以设置的启动选项。** 实测结果是：`mpv_initialize()` 永不返回，
进程不产生任何输出，也**从不发出播放列表的 HTTP 请求**（`native_initialized == false`、
`playlist_count == 0`、日志 0 字节），直到被外部超时杀掉。

隔离实验结果（同一个 `--{ --playlist=… --playlist-start=1 --}` 形状）：

| 用例 | 结果 |
|---|---|
| `--{ --force-media-title=X --}`（无 playlist） | 正常 |
| `--{ --playlist-start=1 --}`（无 playlist） | 正常 |
| `--{ --playlist=URL --}` | **卡死** |
| `--{ --playlist=URL --playlist-start=1 --}` | **卡死** |
| `--playlist=URL --playlist-start=1`（不带参数组） | **卡死** |
| 1.1.5 播放器 + 同一形状 | 正常（`playlist_count=5`，选中第 1 项） |

结论：只要 `playlist` 作为启动选项被设置就会死锁，与是否使用 `--{ --}` 无关。

---

## 3. 修复

`src/player/src/MpvNet/CommandLine.cs`：

1. `ProcessCommandLineArgsPreInit()` —— **跳过 `playlist`**，绝不再把它交给
   `mpv_set_option_string`。
2. `ProcessCommandLineFiles()` —— 在初始化**之后**用 `loadlist … append` 载入播放列表，
   再用 `playlist-play-index <n>` 命令选中目标集（而不是设置 `playlist-pos` 属性，
   后者正是「先打开首项」的来源）。

`tools/standalone/prepare_startup.py`：同步更新构建期的契约校验——
现在要求 `CommandLine.cs` 里必须存在 `loadlist`、`playlist-play-index` 与
`pair.Name == "playlist"`，并且**显式拒绝**任何重新引入「初始化前交给 mpv」写法的改动：

```python
if 'mpv must receive --playlist' in command:
    raise RuntimeError('Unsafe pre-init --playlist handoff was reintroduced')
```

`docs/standalone.md`：1.1.6 发行说明里描述旧做法的那一句已改写，避免继续误导。

---

## 4. 验证

### 4.1 真实配置下的对照

| 播放器 | 请求序列 | 结果 |
|---|---|---|
| 1.1.5（`mpvnet.exe.1.1.5.bak`） | `/ep.m3u` → `/ep2.y4m` | `playlist_pos=1`、`playlist_count=5`、`title=EP2` |
| 1.1.6（修复前） | — | **卡死，无任何请求** |
| 1.1.6（修复后） | `/ep.m3u` → `/ep2.y4m` | `playlist_pos=1`、`playlist_count=5`、`title=EP2` |

三次都使用同一份生产 `portable_config`，`/ep1.y4m`（错误的那一集）从未被请求。

### 4.2 项目自带的发布门槛测试

```
python tests/test_player_ui_empty_scope.py <mpvapp> <out>
→ PASS player_ui-legacy-script-opt
→ PASS player_ui-base-script-opts
→ PASS player_ui-playlist-selected
```

`player_ui-playlist-selected` 的关键断言全部满足：

```
wrong_episode_requests: 0        selected_episode_requests: 1
playlist_requests: 1             first_playback_seconds: 1.308
```

请求序列只有 `/player_ui/episodes.m3u` 与 `/media/selected-episode.y4m`。

v3 启动诊断：

```json
{ "playlist_option_count": 1, "playlist_start_option_count": 1,
  "playlist_start_kind": "index", "playlist_start_index": 1,
  "playlist_count": 2, "playlist_current_pos": 1,
  "native_initialized": true, "file_loaded": true, "option_error": null }
```

### 4.3 产物自校验

`AnimeJaNaiUpdater.exe --verify` → `{"ok":true,"failed":[]}`（321 个文件）。
修复后的 `mpvnet.exe` SHA-256 前缀 `A2881B1384B2D6E9`。

---

## 5. 已部署的位置

| 位置 | 状态 |
|---|---|
| `D:\CODE\AnimeJaNai-zh-CN\mpvapp\mpvnet.exe` | 修复版（`A2881B13…`） |
| `D:\Apps\mpv-AnimeJaNai\mpvnet.exe`（Player UI 实际调用） | 修复版（`A2881B13…`） |
| `D:\Apps\mpv-AnimeJaNai\mpvnet.exe.1.1.5.bak` | 原 1.1.5 备份（174,631,818 B） |

仓库改动（未提交）：`src/player/src/MpvNet/CommandLine.cs`、
`tools/standalone/prepare_startup.py`、`docs/standalone.md`。

---

## 6. 尚未确定的一点

Player UI 的 `--playlist-start` **语义**还没有在真实调用上确认过：

- 如果它是「Player UI 生成的播放列表内的索引」，当前位置逻辑正确。
- 如果它传的是**Absolute 剧集号**（例如第 22 集 → `22`），而播放列表只有 5 项，
  那么 `Math.Clamp(start, 0, count-1)` 会把它夹到最后一项 → 仍会播错。

要判定这一点，只需要在修复后的播放器上从 Player UI 实际打开一集，然后读
`D:\Apps\mpv-AnimeJaNai\portable_config\startup-diagnostic.json` 里的
`playlist_start_index` 与 `playlist_count`：
若 `playlist_start_index` 落在 `[0, playlist_count-1]` 内即为前者。
