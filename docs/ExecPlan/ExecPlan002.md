# ExecPlan 002 — F4.3 自动重连 (P0 #4)

## 问题
网络流播放断开后无自动重连。无 NWPathMonitor，无 retry/backoff。QA-J03 FAIL。

## 方案

### 1. NetworkMonitor — 网络状态观察
- 新文件: `XrPlayer/App/NetworkMonitor.swift`
- 使用 NWPathMonitor 监听网络状态变化
- @Observable class，暴露 `isConnected: Bool` 和 `waitForConnection() async`

### 2. PlaybackLaunchCoordinator — 重连逻辑
- 在 `beginPlayback` catch 块中检测网络错误
- 网络错误 → 设 playbackState = .buffering + 最多 3 次重试
- 指数退避: 2s, 4s, 8s
- 每次重试前用 NWPathMonitor 确认网络已恢复
- 利用现有 generation 计数器取消过期重试

### 3. 错误分类提取
- 将 FileBrowsingViewModel.isNetworkRecoverableError 提取为共享工具方法
- 同时在 PlaybackLaunchCoordinator 中复用

## 验证
- swift build 零 error
- swift test 全绿 (≥248)
