# ExecPlan 033 — P1 修复: ISSUE-004 本地子文件夹导航 + F6.6 屏幕形状持久化

## 目标
修复两个 P1 缺陷：
1. ISSUE-004: 本地子文件夹导航不可用（FileBrowsingViewModel:303 guard activeRemoteAdapter 阻塞本地路径）
2. F6.6: 屏幕形状（flat/curved）不持久化，每次重启恢复默认

## 验证标准
- 本地文件浏览可以进入子文件夹
- 屏幕形状选择在 App 重启后保留
- swift test 248+ passed, 0 failures
- xcodebuild BUILD SUCCEEDED
