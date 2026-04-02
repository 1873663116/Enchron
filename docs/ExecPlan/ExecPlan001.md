# ExecPlan 001 — F4.1 网络缓冲指示器修复 (P0 #2)

## 问题
`PlaybackState.buffering` 枚举已定义但从未触发。MPVPlayerAdapter 未观察 mpv 的 `paused-for-cache` 属性，网络流播放卡顿时用户无任何视觉反馈。

## 修改清单

### 1. MPVPlayerAdapter.swift — 观察 paused-for-cache
- `observeCoreProperties()` 添加 `mpv_observe_property(handle, 9, "paused-for-cache", MPV_FORMAT_FLAG)`

### 2. MPVPlayerAdapter.swift — 处理 paused-for-cache 变更
- `handlePropertyChange()` 添加 `case "paused-for-cache":` 分支
- flag=true → `updateState(.buffering)`
- flag=false → 根据 mpv pause 状态恢复 `.playing` 或 `.paused`
- 必须排除 `isAwaitingVisualPlaybackStart` 期间的误触发

### 3. UI 缓冲指示器
- 在 MainView 或 PlayerControlsView 中添加 ProgressView 叠加层
- 条件：`playbackState == .buffering`
- 样式：居中圆形 spinner + "Buffering..." 文字

### 4. WindowVideoViewModel.swift — 确保 .buffering 不关闭视频
- 已有：`case .idle, .loading, .buffering, .stopped, .failed: break` — 无需修改

## 验证
- swift build 零 error
- swift test 全绿 (≥248)
- 代码审查：.buffering 触发路径完整
