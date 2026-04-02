# ExecPlan042 — UX-07 Window Management (openWindow/dismissWindow)

> Round: 23
> Created: 2026-04-02
> Phase: EXECUTING (Phase 2 T2.2 — HelloWorld UX 改进 #5)
> Priority: P1

## 目标

实现 UX-07：注册独立 Settings 窗口，在播放控件中添加 openWindow 入口。
参考 HelloWorld GlobeToggle.swift 模式：`@Environment(\.openWindow)` / `@Environment(\.dismissWindow)`。

## 价值

Settings Tab 已可达，但**播放视频时**用户无法不中断访问 App 级设置。
独立窗口可与播放共存，提升实用性。

## 改动范围

1. `XrPlayer/XrPlayerApp.swift`
   - 新增 `WindowGroup(id: "settings")` Scene，包含 `NavigationStack { SettingsView() }`
   - 注入 `.environment(appModel)`

2. `XrPlayer/PlayerUI/Views/PlayerControlsView.swift`
   - 新增 `@Environment(\.openWindow) private var openWindow`
   - `secondaryControlRow` 末尾新增 `settingsWindowButton`（gearshape 图标）
   - 调用 `openWindow(id: "settings")`

## 验证

- `swift build` 零 error
- `swift test` 248 passed / 0 failures
