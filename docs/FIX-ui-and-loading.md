# 修复记录：控制栏字形发虚 / 加载时黑屏无提示

日期：2026-09-19
现象：底栏控件相对窗口过小、文字发虚；打开视频（尤其网络片源）时整个窗口全黑，无法判断是在加载还是卡死。

---

## 1. 控件过小、字形发虚

### 原因

`player_ui_core.lua` 的排版函数把界面画在一个虚拟坐标系里：

```lua
base  = clamp(ui_scale) * clamp(dpi)
scale = min(base, pw/920, ph/620)
w, h  = pw/scale, ph/scale      -- 这组 w,h 就是 ASS 的 PlayRes
```

`ui.res_x / ui.res_y` 被设为 `layout.w / layout.h`，长度 `L` 最终在屏幕上占 `L * scale` 像素。
所以 **`scale` 就是屏幕上的放大倍率**。而 `script-opts/player_ui.conf` 里写的是：

```
ui_scale=0.70
```

再乘上 `display-hidpi-scale`（这台机器实测 **1.25**），实际倍率只有 `0.70 × 1.25 = 0.875`，
标题 40 → 35 px，时间 21 → 18 px。0.70 是仓库里刻意加的（`prepare_playback.py` 会把它写进脚本默认值），
所以旧的测试还专门断言「真实前端里 scale 必须 < 1」。

### 修改

| 文件 | 改动 |
|---|---|
| `portable_config/script-opts/player_ui.conf` | `ui_scale=0.70` → `1.00` |
| `portable_config/scripts/player_ui.lua` | 选项默认值 `ui_scale=0.70` → `1.00`，clamp 默认值同步 |
| `portable_config/script-modules/player_ui_core.lua` | `M.layout` 的 `or .70` → `or 1.00` |
| `tools/standalone/prepare_playback.py` | 两处 `edit()` 的目标字面量同步为 `1.00`，否则构建期会因上下文不匹配报错 |
| `tests/test_network_playback.py` | 原断言 `scale < 1`（旧设计意图）替换为 `0.5 ≤ scale ≤ 1.5` 且所有控件 `x1*scale ≤ width`，改为校验「可读且不溢出」 |

实际倍率从 **0.875 → 1.25**（+43%）。

---

## 1.5 去掉文字阴影，改用细描边

`player_ui.lua` 的 `text()` 是**全播放器唯一**带阴影的地方（`\bord0\shad1`），
其余元素（图标、矩形、弹幕、mpv 自己的 OSD）都是 `\shad0`。
1px 阴影叠在 21–40px 的文字上会产生错位重影，这正是「看得眼花」的来源。

改成 `\shad0` 后立刻暴露出另一个问题：底栏的渐变是**上浅下深**——
标题/详情所在的位置几乎透出原视频，亮画面上白字和浅灰字直接失去对比度
（实测亮灰测试片上 `640 × 360 · 24 fps` 一行几乎不可见）。

所以参照本项目已有的约定补回对比度：mpv 自己的 OSD 是
`osd-border-size=1.65 / osd-shadow-offset=0`，弹幕是 `\bord1.2\shad0` ——
**细描边、无阴影**。描边是均匀轮廓，不会产生阴影那种位移重影。

新增可调项 `text_outline`（默认 1，范围 0–4），写在 `text()` 的 `\bord%d`：

```lua
line(string.format('{\\rDefault\\an%d\\pos(%.2f,%.2f)\\fn%s\\fs%d\\b%d\\bord%d\\shad0\\1c&H%s&…',
    align or 7,x,y,o.font,size,bold and 1 or 0,core.clamp(tonumber(o.text_outline) or 1,0,4),…))
```

`portable_config/script-opts/player_ui.conf` 增加 `text_outline=1`。设为 `0` 即完全无描边。

> 插曲：中途我曾把几处底衬的透明度参数「加强」，结果把 ASS 的 alpha 语义搞反了——
> `\1a` 里 **00 是不透明、FF 是全透明**，所以 `PANEL,20` 本来就是近乎实心的底板、
> `WHITE,226` 是淡淡的悬停光晕。已全部回退，原值保持不变。

---

## 2. 加载时全黑无提示

### 原因

底栏在 `start-file` 时确实会 `show()`，但：

- `idle-active` 时标题被清空（`if bool('idle-active',true) then title='' end`）；
- 唯一的加载线索是详情行里的 `正在缓冲…`，字号 23、且只在 `paused-for-cache` 为真时出现；
- 底栏 2.5 秒后自动隐藏，隐藏后**屏幕上什么都不剩**；
- 「正在打开」这个阶段（文件已开始打开、demuxer 还没解析出轨道）没有任何表示，
  此时 `video-params` 为空、`track-list` 为空，画面就是纯黑。

### 修改（`portable_config/scripts/player_ui.lua`）

新增 `loading_state()`：

```lua
loading_state=function()
    if bool('idle-active',true) or bool('pause') then return nil end
    if bool('paused-for-cache') then return '正在缓冲…' end
    if num('vo-presented-frame-count',0)>0 then return nil end
    local tracks=prop('track-list',{}) or {}
    if #tracks==0 then return '正在加载…' end            -- 还在打开，尚未解析出轨道
    for _,t in ipairs(tracks) do
        if t.type=='video' and not t.albumart and t.selected~=false then return '正在加载…' end
    end
end
```

渲染时**画在底栏可见性判断之外**，所以底栏自动隐藏后提示依然存在：

- 画面正中一块半透明底 + `正在加载… / 正在缓冲…`
- 下方显示正在打开的标题（取自 `media-title`，Player UI 会传 `--force-media-title`）
- 再下方三个小圆点轮转高亮，让人能看出程序还活着

配套改动：
- 加载中不再重复显示底栏左下角的标题（避免同一标题出现两次）；
- `sync_timers()` 的刷新条件加入 `loading_state()~=nil`，否则底栏隐藏后周期性重绘会停掉，动画会僵住；
- 详情行里原来的 `正在缓冲…` 移除（该信息已由居中提示统一承担）。

---

## 3. 验证

### 视觉验证（原生分辨率截取窗口客户区）

用本地 HTTP 服务造一个「发完响应头就不发 body」的地址，强制停在打开阶段；
播放态用**亮灰测试片**（最坏对比度情况）验证：

| 截图 | 结果 |
|---|---|
| 加载态 | 黑屏正中 `正在加载…` + 标题 `slow.y4m` + 三个轮转圆点；底栏尺寸明显大于修复前 |
| 播放态（去阴影、加 1px 描边后） | `fast.y4m`、`640 × 360 · 24 fps`、`00:01`/`00:06`、`0.0 KB/s`、窗口按钮在亮灰画面上全部清晰可读；无阴影、无重影 |

（去掉阴影但未加描边的中间版本里，`640 × 360 · 24 fps` 一行几乎不可见 —— 这就是必须补描边的原因。）

亮像素计数可作客观旁证：2932（无加载提示）→ 8252（有提示）。

### 项目自带测试

| 测试 | 结果 |
|---|---|
| `tests/test_player_ui_logic.lua` | **exit 0**（它不带 `ui_scale` 调用 `core.layout`，即直接验证新默认值 1.00 下的边界与不重叠） |
| `tests/test_network_playback.py` | **22/22 检查、6/6 用例全部 PASS**，含 `player_ui controls sized in a readable range: 1.25`、`controls fit the client area`、`start at selected episode without opening first`、`playlist option starts only selected item` |
| `tests/test_player_ui_empty_scope.py` | 3/3 PASS（见 `FIX-player_ui-playlist-deadlock.md`） |
| `AnimeJaNaiUpdater.exe --verify` | `{"ok":true,"failed":[]}`（355 个文件） |

> 首次运行 `test_network_playback.py` 时 `idle-and-ipc` 报过 `No visible client window for test process`。
> 单独实测：空载启动 3 秒后进程确实有 `visible=True, 1086x611, title='mpv.net'` 的窗口，
> 重跑即全部通过 —— 该失败是首次运行的时序偶发，与本次改动无关。

---

## 4. 部署位置

| 文件 | 仓库 | `mpvapp` | `D:\Apps\mpv-AnimeJaNai`（Player UI 实际调用） |
|---|---|---|---|
| `portable_config/scripts/player_ui.lua` | 已改 | 已同步 | 已同步 |
| `portable_config/script-modules/player_ui_core.lua` | 已改 | 已同步 | 已同步 |
| `portable_config/script-opts/player_ui.conf` | 已改 | 已同步 | 已同步 |

**用户可以自己调**（都在 `portable_config/script-opts/player_ui.conf`，重启播放器生效）：
- `ui_scale`：控件整体尺寸，0.45–1.5，默认 1.00
- `text_outline`：文字描边粗细，0–4，默认 1；设 0 即完全无描边

---

## 5. 真正的根因：PlayRes 被缩小了（1:1 重构）

写完 `text_outline` 之后对照 Player UI 内置播放器截图，才发现「字发虚」的**根本原因**一直不是字号：

```
ui.res_x = pw / scale        -- scale = min(ui_scale*dpi, pw/920, ph/620)
```

`ui_scale=1.00`、`display-hidpi-scale=1.25` 时 `scale=1.25`，PlayRes 变成窗口的 **0.8 倍**，
ASS 被**上采样 1.25 倍** —— 字越大越糊。也就是说把 `ui_scale` 从 0.70 提到 1.00 的方向是反的：
0.70 时 PlayRes 是窗口的 1.14 倍（下采样，清晰但小），1.00 时变成上采样（大而糊）。

**修正：ASS PlayRes 恒等于窗口（1:1），永不重采样**；`ui_scale × dpi` 只用来放大
字号、图标和间距。这样「大」和「清晰」不再互斥。

`M.layout` 重写要点：
- `w, h = pw, ph`，返回 `scale=1`、`ui=want`
- 控制行、边距、进度条、渐变高度全部乘 `want`
- 当窗口太窄放不下控制行时，按 0.86 逐步收缩 `want` 并**成对检查重叠与越界**，
  最多 12 次（300×160 的极端用例也能收敛）

渲染端所有字号、图标尺寸、渐变高度、圆点半径改为乘 `layout.ui`；
`icon()` 通过模块级 `icon_u` 取值；缩略图定位改用 `layout.ui`。

对齐 Player UI 内置播放器（实测窗口 1268×711）的视觉：

| 元素 | Player UI 参照 | 修正后 |
|---|---|---|
| 标题 | 白、不加粗、~31px | 白、不加粗、30×ui |
| 集数信息 | ~17px 浅灰 | 17×ui 浅灰 |
| 时间 | ~14px，进度条两端 | 14×ui，两端 |
| 进度条 | 全宽贴边 | `22*ui` 到 `w-22*ui` |
| 图标 | ~21px、细 | 60 缩放系数 ×ui |
| 渐变 | 很淡 | 190×ui 高、上限 140 |

`player_ui_menu.lua` 的菜单几何保持原布局单位，随 1:1 映射整体放大约 14%，未逐一缩放。

---

## 6. 说明

- `script-modules/player_ui_core.lua` 与 `player_ui.lua` 里内联的副本是两份代码，
  排版函数必须同步改，否则源码级测试与实际运行会不一致。
- 本文件与 `FIX-player_ui-playlist-deadlock.md` 的改动都**未提交**，工作树里对应的受控文件为：
  `src/player/src/MpvNet/CommandLine.cs`、`tools/standalone/prepare_startup.py`、
  `tools/standalone/prepare_playback.py`、`tests/test_network_playback.py`、
  `portable_config/{scripts/player_ui.lua,script-modules/player_ui_core.lua,script-opts/player_ui.conf}`、
  `docs/standalone.md`。
- 验证时的两组实测数据：`display-hidpi-scale = 1.25`（这台机器）；
  `test_player_ui_logic.lua` 6907 条断言覆盖 6 种窗口尺寸 × 4 种 DPI × 4 种播放列表长度。

