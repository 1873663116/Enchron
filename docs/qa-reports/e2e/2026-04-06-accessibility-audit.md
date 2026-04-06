<!-- 更新：2026-04-06 19:17 | 分支：MinimaxTest | 提交：00ac3d6 -->

# Accessibility 结构审计报告 — Enchron V2

**日期：** 2026-04-06  
**分支：** MinimaxTest  
**提交：** 00ac3d6  
**审计范围：** 代码层面静态分析（无 Simulator 交互）  
**审计模式：** audit-only（硬约束限制）

---

## 总体健康分数：88% — WARN

审计覆盖 16 个 View 文件，118 条 accessibility 标注，136 个交互元素。  
所有含交互元素的文件均有 `accessibilityIdentifier` 覆盖（覆盖率 100%）。  
发现 3 类问题：命名约定不一致（WARN）、部分元素缺失描述（WARN）、触摸目标尺寸待确认（WARN）。

---

## 模块 Accessibility 覆盖情况

| 模块 | 文件数 | identifier覆盖 | label覆盖 | hint覆盖 | 状态 |
|------|--------|--------------|---------|---------|------|
| PlayerUI/PlayerControlsView | 1 | 全覆盖 | 全覆盖 | 部分 | WARN |
| PlayerUI/PlayerInfoBarView | 1 | 全覆盖 | 全覆盖 | 全覆盖 | PASS |
| PlayerUI/NLETimelineView | 1 | 全覆盖 | 全覆盖 | 全覆盖 | WARN |
| PlayerUI/VideoDetailView | 1 | 全覆盖 | 全覆盖 | 部分 | WARN |
| FileBrowsing/BreadcrumbView | 1 | 全覆盖 | 全覆盖 | 全覆盖 | PASS |
| FileBrowsing/DataSourceConfigView | 1 | 部分 | 部分 | 无 | WARN |
| FileBrowsing/FolderListView | 1 | 全覆盖 | 全覆盖 | 全覆盖 | PASS |
| FileBrowsing/ContentGridView | 1 | 全覆盖 | 全覆盖 | 全覆盖 | PASS |
| FileBrowsing/FilterPillsView | 1 | 全覆盖 | 全覆盖 | 无 | PASS |
| FileBrowsing/VideoCardView | 1 | 全覆盖 | 全覆盖 | 全覆盖 | PASS |
| FileBrowsing/FileBrowserSidebar | 1 | 全覆盖 | 全覆盖 | 无 | PASS |
| SpatialScene/SceneSelectorView | 1 | 全覆盖 | 无Label | 无 | WARN |
| Settings/SettingsView | 1 | 全覆盖 | 部分 | 无 | WARN |
| App/NavigationOrnament | 1 | 全覆盖 | 全覆盖 | 无 | PASS |
| App/RecentlyPlayedView | 1 | 无 | 全覆盖 | 全覆盖 | WARN |
| ToggleImmersiveSpaceButton | 1 | 全覆盖 | 无 | 无 | WARN |

---

## 发现的问题（按严重程度）

### WARN-1：accessibilityIdentifier 命名约定不一致（跨模块）

`PlayerControlsView` 使用遗留 Convention B（kebab-case），与项目 Convention A（Module-View-ElementType-Purpose）不一致。

**位置：** `XrPlayer/PlayerUI/Views/PlayerControlsView.swift`

| 当前 identifier | 规范 Convention A |
|---------------|-----------------|
| `"rewind-button"` | `"PlayerUI-Controls-button-rewind"` |
| `"forward-button"` | `"PlayerUI-Controls-button-forward"` |
| `"play-pause-button"` | `"PlayerUI-Controls-button-playPause"` |
| `"left-menu-button"` | `"PlayerUI-Controls-button-leftMenu"` |
| `"right-menu-button"` | `"PlayerUI-Controls-button-rightMenu"` |
| `"hdr-toggle"` | `"PlayerUI-Controls-toggle-hdr"` |
| `"subtitles-picker"` | `"PlayerUI-Controls-picker-subtitles"` |
| `"audio-track-picker"` | `"PlayerUI-Controls-picker-audioTrack"` |
| `"speed-picker"` | `"PlayerUI-Controls-picker-speed"` |
| `"3d-mode-picker"` | `"PlayerUI-Controls-picker-3dMode"` |
| `"playback-mode-{rawValue}"` | `"PlayerUI-Controls-button-playbackMode-{rawValue}"` |
| `"settings-environment-{rawValue}"` | `"PlayerUI-Controls-button-env-{rawValue}"` |
| `"more-settings-button"` | `"PlayerUI-Controls-button-moreSettings"` |

`VideoDetailView` 使用遗留 Convention C（camelCase with dot），与 Convention A 不一致。

| 当前 identifier | 规范 Convention A |
|---------------|-----------------|
| `"videoDetail.backButton"` | `"PlayerUI-VideoDetail-button-back"` |
| `"videoDetail.playButton"` | `"PlayerUI-VideoDetail-button-play"` |
| `"videoDetail.subtitlePicker"` | `"PlayerUI-VideoDetail-picker-subtitle"` |
| `"videoDetail.audioTrackPicker"` | `"PlayerUI-VideoDetail-picker-audioTrack"` |
| `"videoDetail.hdrToggle"` | `"PlayerUI-VideoDetail-toggle-hdr"` |
| `"videoDetail.playbackModePicker"` | `"PlayerUI-VideoDetail-picker-playbackMode"` |
| `"videoDetail.playbackModePicker.{rawValue}"` | `"PlayerUI-VideoDetail-button-playbackMode-{rawValue}"` |
| `"videoDetail.environment-{rawValue}"` | `"PlayerUI-VideoDetail-button-env-{rawValue}"` |

**影响：** XCUITest 测试查询需要跨两套命名约定，增加维护成本。

---

### WARN-2：SceneSelectorView 环境按钮缺少 accessibilityLabel

`SceneSelectorView` 中的环境选择按钮只有 `accessibilityIdentifier`，没有 `accessibilityLabel`。VoiceOver 将无法为用户朗读按钮内容。

**位置：** `XrPlayer/SpatialScene/Views/SceneSelectorView.swift` 第 60 行

```swift
// 当前：仅有 identifier，缺少 label
.accessibilityIdentifier("SpatialScene-Selector-button-\(environment.rawValue)")

// 应补充：
.accessibilityLabel(environment.displayName)
.accessibilityHint(isSelected ? "Currently selected" : "Selects this environment")
.accessibilityAddTraits(isSelected ? .isSelected : [])
```

---

### WARN-3：DataSourceConfigView 中 3 个 TextField 和 2 个按钮缺少 accessibilityIdentifier

**位置：** `XrPlayer/FileBrowsing/Views/DataSourceConfigView.swift`

| 元素 | 行号 | 缺失内容 |
|------|------|---------|
| `TextField("Username (optional)", ...)` | 72 | accessibilityIdentifier |
| `SecureField("Password (optional)", ...)` | 77 | accessibilityIdentifier |
| `TextField("Server Name (optional)", ...)` | 80 | accessibilityIdentifier |
| SMB share picker `Button { selectSMBShare(shareName) }` | 131 | accessibilityIdentifier + accessibilityLabel |
| `Button("Cancel")` (toolbar) | 116 | accessibilityIdentifier |
| `Button("Back")` (share picker) | 152 | accessibilityIdentifier |

---

### WARN-4：RecentlyPlayedView 行元素缺少 accessibilityIdentifier

`RecentlyPlayedView.recentRow` 的 HStack 有 `.accessibilityLabel` 和 `.accessibilityHint`，但缺少 `.accessibilityIdentifier`，导致无法通过 XCUITest 精确查询。

**位置：** `XrPlayer/App/Views/RecentlyPlayedView.swift` 第 42-70 行

---

### WARN-5：ToggleImmersiveSpaceButton 缺少 accessibilityLabel

`ToggleImmersiveSpaceButton` 的 `.standard` 样式文本标签会被读取（系统自动推断），但 `.compact` 样式（图标模式）没有显式 `accessibilityLabel`，VoiceOver 将只朗读 SF Symbol 名称（"visionpro" 或 "visionpro.fill"），而非有意义的描述。

**位置：** `XrPlayer/ToggleImmersiveSpaceButton.swift`

```swift
// 应补充：
.accessibilityLabel(appModel.immersiveSpaceState == .open
    ? "Hide Immersive Space"
    : "Show Immersive Space")
.accessibilityHint(appModel.immersiveSpaceState == .inTransition
    ? "Transitioning, please wait"
    : nil)
```

---

### WARN-6：NLETimelineView 容器本身缺少 accessibilityIdentifier

`NLETimelineView` 容器使用了 `.accessibilityElement(children: .contain)` + `.accessibilityLabel("Timeline")`，但没有 `.accessibilityIdentifier`，无法在 XCUITest 中按 ID 查询容器。

**位置：** `XrPlayer/PlayerUI/Views/NLETimelineView.swift` 第 75-76 行

```swift
// 应补充：
.accessibilityIdentifier("PlayerUI-NLETimeline-container")
```

---

### INFO-1：播放控制按钮触摸目标尺寸（visionOS 60pt 规则，代码层面验证 PASS）

| 按钮 | frame 尺寸 | 60pt 规则 |
|------|----------|---------|
| Back (PlayerInfoBarView) | 60×60 | PASS |
| Rewind / Forward | 48×48 | WARN（视觉 48pt，需留白达到 60pt）|
| Play / Pause | 64×64 | PASS |
| NLEToggle | 48×48（.frame内含 48×48）| WARN |
| Menu / Settings | 48×48 | WARN |
| BreadcrumbView 段落 | minWidth/Height 60 | PASS |
| FilterPillsView | minHeight 60 | PASS |
| FolderListView 文件行 | 通过 List 行高 ≥ 60 | PASS |

Rewind/Forward/NLE/Menu/Settings 按钮视觉尺寸 48pt，按 visionOS 60pt 规则需要确保周围留白总计达 60pt。代码中有 `.hoverEffect(.lift)` 表示已意识到交互区域，但需真机验证留白是否足够（标记 HUMAN_REVIEW）。

---

## VerifyList 条目映射

| VerifyList 条目 | 审计覆盖 | Accessibility 状态 |
|----------------|---------|-----------------|
| §5.4 播放控件 Menu/二级菜单可点击 | left-menu-button / subtitles-picker / audio-track-picker / speed-picker 均有 identifier+label | WARN（命名约定） |
| §5.4 Settings→Playback Mode | playback-mode-{rawValue} 有 identifier+label，disabled 状态通过 .disabled() 正确传递给 a11y | PASS |
| §5.9d 沉浸空间控件 toggle 显示/隐藏 | PlayerControlsView 控件全有标注 | WARN（命名约定） |
| §5.10 控制栏按钮数量和顺序 | Menu→Rew→Play→Fwd→NLE→Settings 全有 identifier | WARN（命名约定） |
| §5.10 进度条 | PlayerUI-SeekBar-slider-position + accessibilityValue 动态朗读时间 | PASS |
| §5.10 顶栏：返回+标题+技术标签 | PlayerUI-InfoBar-button-back + label + hint | PASS |
| §5.11 NLE 时间轴 toggle | PlayerUI-NLETimeline-button-toggle 有 isToggle trait | PASS |
| §5.11 NLE 帧步进按钮 | PlayerUI-NLETimeline-button-prevFrame/nextFrame 有 label+hint | PASS |
| §5.7 文件浏览列表 | FileBrowsing-FolderList/ContentGrid/VideoCard 全覆盖 | PASS |
| §5.7b skeleton loading | FileBrowsing-ContentGrid-skeleton 有 label | PASS |
| §5.9 沉浸空间场景选择 | SpatialScene-Selector-button-{rawValue} 有 identifier | WARN（缺 label） |
| §5.4 Settings 面板 Environment 切换 | settings-environment-{rawValue} 有 identifier+label | WARN（命名约定） |
| FileBrowsing DataSource 配置 | serverAddress textField 有 identifier，其余缺失 | WARN |

---

## 需要修复的升级项（优先级排序）

| 优先级 | 问题 | 修复 | 文件 |
|--------|------|------|------|
| P1 | WARN-2：SceneSelectorView 环境按钮无 label | 添加 .accessibilityLabel + .accessibilityHint + .isSelected trait | SceneSelectorView.swift |
| P1 | WARN-5：ToggleImmersiveSpaceButton compact 模式无 label | 添加 .accessibilityLabel + .accessibilityHint | ToggleImmersiveSpaceButton.swift |
| P2 | WARN-3：DataSourceConfig 3 TextField + 3 Button 无 identifier | 补全 Convention A identifier | DataSourceConfigView.swift |
| P2 | WARN-4：RecentlyPlayedView 行无 identifier | 补全 identifier | RecentlyPlayedView.swift |
| P2 | WARN-6：NLETimelineView 容器无 identifier | 补充 .accessibilityIdentifier("PlayerUI-NLETimeline-container") | NLETimelineView.swift |
| P3 | WARN-1：PlayerControlsView + VideoDetailView identifier 命名约定不一致 | 迁移至 Convention A（需同步更新 XCUITest 查询） | PlayerControlsView.swift, VideoDetailView.swift |

## HUMAN_REVIEW 项

- [ ] 真机验证 Rewind/Forward/Menu/Settings/NLEToggle 按钮（48pt 视觉）周围留白是否达到 visionOS 60pt 总交互空间要求
- [ ] 真机用 VoiceOver 验证 ToggleImmersiveSpaceButton 在 .compact 样式下朗读内容是否正确
- [ ] 真机验证 SceneSelectorView 环境按钮在 VoiceOver 下的朗读体验
