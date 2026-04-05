---
title: "Known Issues Handoff — QA Round 2"
status: active
date: 2026-04-05
---

# Known Issues Handoff — QA Round 2

## 已修复并在真机验证通过

| Issue | 修复内容 | 验证状态 |
|-------|---------|---------|
| Nav ornament 分离 | `contentAlignment: .trailing` | 已验证通过 (Image #16) |
| 详情页元数据首次打开不完整 | poll 等待 mpv profile 检测最多 2s，合并 runtime metadata | 已验证通过 |
| 文件卡片播放时泄漏 | tab content `opacity(0)` + `allowsHitTesting(false)` | 待验证 |
| preparePlayback race condition | `loadPaused()` + `isPrepareOnlyLoad` flag | 待验证 |
| Scene selector 无退出按钮 | 加了 NavigationStack + toolbar Close | 待验证 |
| WebDAV/SMB 无限重连 | `disconnectAndResetToLocal()` + Remove 按钮 | 待验证 |
| FilterPillsView 移除 | 从 FileBrowserView 删除 | 已隐式验证（Image #16 无 filter pills） |
| 安全边界 (Recent/Settings) | `.contentMargins(.top, 20)` | 待验证 |

## 未解决 — 需要下一轮修复

### P0: 播放控件布局不匹配 HTML 设计

**现象：** 播放控件的按钮排布没有对齐 `docs/designs/file-browser-redesign-2026-04-05/player.html` 中的设计。

**根因：** 上一轮重写了 PlayerControlsView 的结构（三层），但仍然使用系统 `Menu` 作为弹出菜单、系统 `.buttonStyle(.automatic)` 或 `.buttonStyle(.plain)` 作为按钮样式。HTML 设计中的按钮是：
- **圆形按钮** (`ctrl-btn`): 48×48 圆形，透明背景，hover 时抬升 -4px
- **播放按钮** (`play-btn`): 64×64 圆形，渐变填充背景 (`linear-gradient(135deg, #c6c6c7, #909191)`)
- **控制栏容器**: pill 形 (`border-radius: 9999px`)，glass-control 材质，`px-6 py-3`，`gap-2` (8px)

**HTML 设计的精确布局 (player.html line 476-710)：**
```
[控制栏 pill 容器, glass-control, 圆角9999px]
  Menu按钮(48×48圆) | 快退10s(48×48圆) | 播放/暂停(64×64圆,渐变bg) | 快进10s(48×48圆) | Settings按钮(48×48圆)
```

**Seek bar (player.html line 454-473):**
```
[独立行, max-w-4xl, px-12, gap-5]
  时间标签(11px, monospace, 右对齐) | 进度条(4px高, hover 6px, 白色渐变进度) | 剩余时间标签
```

**需要做的：**
1. 按钮尺寸统一为 48×48（普通）和 64×64（播放）
2. 控制栏容器使用 `.enchronGlassControl()` (capsule 形)
3. 按钮间距为 8px (`gap-2`)
4. Seek bar 是独立一行，在控制栏上方
5. Menu 和 Settings 继续使用系统 `Menu` — 这在 visionOS 上是正确的选择

**相关文件：**
- `XrPlayer/PlayerUI/Views/PlayerControlsView.swift`
- 参考: `docs/designs/file-browser-redesign-2026-04-05/player.html` lines 450-710

---

### P1: Hover 形状不匹配按钮形状

**现象：** 注视按钮时，hover 高亮显示为圆形，即使按钮是圆角矩形。

**已尝试：** `.hoverEffect(.highlight)` — 在真机上未生效。

**需要调查：**
1. 使用 `mcp__apple-docs__search_apple_docs` 查询 `hoverEffect` API 在 visionOS 上的正确用法
2. 使用 `mcp__XcodeBuildMCP__snapshot_ui` 或 `mcp__XcodeBuildMCP__screenshot` 在模拟器中验证
3. 检查是否需要 `.contentShape(RoundedRectangle(...))` 配合 `.hoverEffect(.highlight)` 才能让 shape 传递给 hover effect
4. 检查 `.hoverEffect(.lift)` vs `.hoverEffect(.highlight)` 在 visionOS 上的具体行为差异
5. 查阅 Apple HIG 关于 visionOS hover effect 的规范

**相关文件：**
- `XrPlayer/PlayerUI/Views/PlayerControlSurface.swift` — 主要修改点
- `XrPlayer/SpatialScene/Views/SceneSelectorView.swift`

---

### P1: 播放控件出现动画仍是突变/位移，不是纯渐显

**现象：** 控件出现时有一个从左下角往上的位移动画，而不是纯 opacity 渐显。

**已尝试：** 
- `.transition(.opacity)` + `.animation(.easeInOut(duration: 0.4))` — 在真机上仍是位移动画

**需要调查：**
1. visionOS `.ornament()` 内部是否有自己的默认 insertion/removal 动画，覆盖了我们设置的 `.transition()`？
2. 使用 `mcp__apple-docs__search_apple_docs` 查询 `ornament` modifier 的 transition/animation 行为
3. 可能需要用 `withAnimation(.easeInOut(duration: 0.4)) { appModel.showControls = true/false }` 在所有 call site 显式包裹，而不是依赖 `.animation()` modifier
4. 检查 `MainView.swift` 中所有修改 `appModel.showControls` 的地方是否都用了 `withAnimation`

**相关文件：**
- `XrPlayer/MainView.swift` lines 125-143 — ornament 定义
- `XrPlayer/MainView.swift` — 所有 `showControls = true/false` 的 call site

---

### P2: 视频画布不跟随窗口缩放

**现象：** 拖拽 visionOS 窗口边缘缩放时，视频画布尺寸不更新。

**已尝试：**
- `autoresizingMask = [.flexibleWidth, .flexibleHeight]` — 未生效
- `setNeedsLayout()` in `updateUIView` — 未生效

**需要调查：**
1. 使用 `mcp__XcodeBuildMCP__start_sim_log_cap` 捕获日志，在 `layoutSubviews()` 中添加 print 看窗口缩放时是否被调用
2. 使用 `mcp__apple-docs__search_apple_docs` 查询 UIViewRepresentable 在 visionOS 窗口 resize 时的生命周期
3. 可能需要 `GeometryReader` 包裹 `WindowVideoView`，将 size 传入作为参数，触发 `updateUIView`
4. 检查 mpv 的 `vo-configured` 事件和 `video-out-params` 属性——mpv 可能缓存了输出分辨率
5. `MPVNativeMetalLayerView.layoutSubviews()` 中的 MoltenVK 1×1 workaround 是否在过滤合法的 resize

**相关文件：**
- `XrPlayer/WindowVideoView.swift`
- `XrPlayer/Shared/MPVNativeMetalLayerView.swift`

---

### P2: NLE 二级时间轴问题

**现象：** 二级时间轴（NLE timeline）容器透明、按钮溢出、拖动逻辑有问题。

**相关文件：**
- `XrPlayer/PlayerUI/Views/NLETimelineView.swift`
- `XrPlayer/PlayerUI/Views/TimelineRulerView.swift`
- `XrPlayer/PlayerUI/Components/ThumbStripView.swift`

---

## 代码变更摘要 (本轮所有 commits)

```
12bdc55 fix(ui): Phase 1 — fix MainView layering and preparePlayback race condition
ffb31c7 fix(ui): Units 6,10,11 — controls fade, detail sheet size, video canvas resize
53d466e fix(ui): Units 3,4,5 — nav ornament gap, safe area boundaries, remove filter pills
7dc5e01 fix(ui): Units 7,8,9 — hover shape, scene selector dismiss, reconnect loop
9e416bb test: add loadPaused stub to MockPlaybackController
f234be8 fix(ui): controls pure opacity fade + detail view metadata loading
1433c7f fix(ui): rewrite PlayerControlsView per HTML design + fix ornament alignment
```

## 下一轮执行建议

1. **先用 MCP 工具调查 API 行为**：用 `mcp__apple-docs` 查 hoverEffect、ornament animation、UIViewRepresentable resize。用 `mcp__XcodeBuildMCP` 在模拟器中验证视觉效果
2. **播放控件布局对齐 HTML**：不需要自定义组件，只需要正确的尺寸、间距、按钮样式
3. **每个修复都在模拟器中截图验证**，不要盲改
