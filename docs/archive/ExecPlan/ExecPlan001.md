# ExecPlan 001 — F3.2 Bridge 断联修复

## 目标
修复 `.immersive` 模式虚拟屏幕无视频纹理的 P0 缺陷。

## 根因
`PlayerControlsView.switchPlaybackMode()` 中：
- Step 1 (line 415): 仅在离开 `.panorama` 时 detach bridge
- Step 5 (line 448): 仅在进入 `.panorama` 时 attach bridge
- `.immersive` 模式被完全遗漏

## 修复
文件: `XrPlayer/PlayerUI/Views/PlayerControlsView.swift`

1. **Step 1 (line 414-417)**: 条件从 `currentMode == .panorama` 改为 `currentMode == .panorama || currentMode == .immersive`
2. **Step 5 (line 447-452)**: 条件从 `mode == .panorama` 改为 `mode == .panorama || mode == .immersive`

## 验证
- `swift build` 零 error
- 现有 248 tests 全绿（无退化）
