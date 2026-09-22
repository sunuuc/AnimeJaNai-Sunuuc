# 剧集名/网速的定位：两次改错后的最终定案

## 最终行为（当前状态）

**剧集名和网速都属于底栏，只有底栏在屏幕上时才画。** 底栏一收起，画面上什么都不留。

| 状态 | 剧集名 | 网速 |
| --- | --- | --- |
| **底栏可见** | `layout.title_y = h-186*want` | `layout.detail_y = h-142*want`，**名字正下方** |
| **底栏隐藏** | 不画 | 不画 |

底栏内的纵向顺序（`want = ui_scale × dpi`）：

```
剧集名      title_y  = h-186w   ← 在进度条上方
网速        detail_y = h-142w   ← 名字正下方
───────进度条──────── seek    = h-118w … h-92w
控件行
```

```lua
local title=core.title(mp.get_property('media-title',''),mp.get_property('path',''))
if bool('idle-active',true) then title='' end
if title~='' and state.visible then
    text(layout.margin,layout.title_y,30*u,title,7,WHITE,false,layout.w-2*layout.margin,0.6)
    if net then text(layout.margin,layout.detail_y,16*u,core.rate(state.rate),7,MUTED,false,nil,0.6) end
end
```

关键是 **`and state.visible`**：底栏收起后名字和网速都不画，否则会在画面底部留下一条
常驻字幕条 —— 用户的原话是"挂在这儿遮挡视线吗"。

## 需求本意（回看）

用户要的只有一句：**「网速放在名字下面」**。

- ✅ 网速在名字正下方 —— 在底栏内达成
- ✅ 名字不常驻屏幕下方
- ✅ 名字不在进度条下面
- ✅ 不遮挡画面

## ⚠ 两次改错，都已回退

### 第一次：把名字钉到底部 + 底栏整体上移

误读成"把名字钉在下面"，于是把 `name_y` 改成常量 `layout.h-76*u`，并把底栏上移 84u
给它让位。**结果名字跑到进度条下面。**

> 我让你把网速放在名字下面，我他妈又没说让你把这个名字常驻在下面，
> 我也没让你把这名字放在进度条下面

已逐字节回退（`player_ui.lua` sha 回到 `144a2319e6c7`）。

### 第二次：只回退，名字仍在底栏隐藏时画在左下角

回退后恢复原逻辑（隐藏时落 `h-76u`），名字**仍然常驻在画面底部**：

> 怎么你妈的还在这儿呢……在这儿给谁看呢，挂在这儿遮挡视线吗

### 教训

- **要动的是网速，不是名字。** 「A 放到 B 下面」＝移动 A。
- **改的幅度不要超出用户说的那句话** —— 他说动网速，就别顺手动名字，
  更别连带改底栏布局、弹出菜单锚点、tooltip。
- 回退到"原样"不等于"对"。原样本身也可能就是用户不想要的；
  用户反对的是**现象**（名字挂在画面下方），不是我的改法。

## 顺带查清的两件事

- **画面上方那条标题不是 Player UI 画的**，是 mpv 自己的 `osd-playing-msg`
  （值 `${media-title}`，**不在本项目任何配置文件里**，来自播放器默认），
  只在文件载入时短暂出现，会自己消失 —— **没有动它**。
- **另一个独立问题**：`hide()` 里有 `if ... or bool('pause') then return end`，
  **暂停时底栏永不收起**。用户跳过了这个问题，**没有动**。

## 验证

`tools/capture_player_ui_overlay.py`（1631×917，u=1.5）：

| 截图 | 内容 |
| --- | --- |
| 底栏可见 | 名字 `y≈442`、网速 `y≈477`、进度条 `y≈503` ⇒ 名字在进度条上方 ✓ |
| 底栏隐藏 | **只剩左上角时钟**，画面无任何文字 ✓ |

门禁：

| 套件 | 结果 |
| --- | --- |
| player_ui-logic | **6388 断言 PASS** |
| player_ui-windows-ui | PASS |
| test_network_playback.py | 6/6 PASS |

## 另一件真正该修的（上一轮）

开始菜单快捷方式 `mpv-AnimeJaNai` 指向 `D:\Apps\mpv-AnimeJaNai\mpvnet.exe`，
那份是 **9-19 旧版** `player_ui.lua`：**没有左上角时钟**，名字**永远**画在 `title_y`。
**判定方法**：看截图左上角有没有时钟。已同步新版过去（备份
`player_ui.lua.bak-20260922-163935`）。

## 可复用工具

| 工具 | 用途 |
| --- | --- |
| `tools/run_player_ui_logic.py` | 不开窗口跑逻辑套件，秒级；`--patch-before/--patch-code` 注入调试行 |
| `tools/capture_player_ui_overlay.py` | 真实播放截图，底栏两态 + 弹出菜单，用来"看"结果 |
