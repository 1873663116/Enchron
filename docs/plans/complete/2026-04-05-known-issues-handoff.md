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

### P0: 三级UI布局均未准确参考HTML复刻

App首页的整体风格漂移，没有完全参考variant-AB-combined.html
播放前信息二级页面排布和UI同意没有完全参考designs/file-browser-redesign-2026-04-05/布局实现，大部分相关按钮也都不可选
播放页面则几乎完全独立实现，根本没有参考player.html

我们需要的只是用liquid grass和apple的自带容器等内容来取代HTML的UI容器和按钮等，但是没有说， Agent 可以自由调整布局。Agent 应该严格按照设计中的布局来进行排布。

**相关文件：**
- 参考: `docsdesigns/file-browser-redesign-2026-04-05/`

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

### P1: 播放模式切换缺少层级约束

**现象：** 播放普通 2D 视频时，可以点击切换到沉浸播放或全景播放模式，导致视频仍在正常播放但空间场景错误切换。

**期望行为：** 播放模式有能力层级，由视频内容本身决定：
- **2D 视频（基础层）**: 只能窗口播放，沉浸/全景模式按钮应禁用
- **3D 视频（中间层）**: 可沉浸播放 + 可降格到窗口 2D，但不可升级到全景
- **全景视频（最高层）**: 可全景/沉浸/窗口，全部是降格或同级

核心原则：**不可以从下级跃上上级，但可以从上级降级到下级**

**相关文件：**
- `XrPlayer/PlayerUI/Views/PlayerControlsView.swift` — 模式切换 UI 入口
- `XrPlayer/SpatialScene/Views/SceneSelectorView.swift` — 场景选择器
- `XrPlayer/PlaybackCore/` — MediaProfile / ProjectionType 定义
- 参考 ARCHITECTURE.md: "PlayerUI 具备播放模式决策入口"

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
2. **播放控件按钮和布局完全对齐 HTML**：不需要自定义组件，只需要正确的尺寸、布局、间距、按钮样式多级菜单的展开容器所容纳的按钮，一比一复刻布局
3. **每个修复都在模拟器中截图验证**，不要盲改
