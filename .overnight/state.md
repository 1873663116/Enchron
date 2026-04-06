next: execute
status: IN_PROGRESS
iteration: 1
consecutive_failures: 0
goal: "修复 Enchron V2 全部已知 Bug（§5.4-§5.11）并严格对齐 player.html 播放控件设计，通过 VerifyList 闭环验证所有需求"
round: 3
context: |
  review 轮完成。ce-review + adversarial review (codex: degraded, Opus 替代)。

  审查结果：0 P0 / 2 P1 / 5 P2 / 5 P3
  VerifyList 进度：46/51 [x]，5 条待完成

  P1 必修项（下轮 execute 目标）：
  - P1-1: MainView.swift — requestDismissImmersiveSpace 路径补 dismissWindow(id: "playerControls")
    根因：isTransitioningPlaybackMode flag 阻断 onChange 二次触发，playerControls 窗口残留
  - P1-2: REGRESSION.md — 补充 7+ 条回归项（§5.4/§5.5/§5.6/§5.9/§5.11/§5.8）

  P2 修复项（同轮处理）：
  - P2-1: MediaProfilePrefetchService 过滤 SMB URL（smb:// 不走 AVFoundation 预读）
  - P2-2: Dolby Vision key 改用 kCMFormatDescriptionExtension_DolbyVisionConfiguration
  - P2-6: mergeFiles/mergeFolders Dictionary(uniqueKeysWithValues:) → uniquingKeysWith 防 crash
  - P2-7: detectProfile AVURLAsset 取消时 asset.cancelLoading()

  文档同步项：
  - ARCHITECTURE.md 补充沉浸空间入口统一路径约束
  - REGRESSION.md 新增回归项

  审查报告：docs/qa-reports/e2e/2026-04-06-v2-code-review.md
  VerifyList：docs/plans/active/VerifyList.md（已更新）
