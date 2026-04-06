next: test
status: IN_PROGRESS
iteration: 1
consecutive_failures: 0
goal: "修复 Enchron V2 全部已知 Bug（§5.4-§5.11）并严格对齐 player.html 播放控件设计，通过 VerifyList 闭环验证所有需求"
round: 4
context: |
  execute 轮（round 3）完成。修复 review 发现的 2 P1 + 4 P2 + 2 文档同步项，共 7 个 commit。
  
  代码修复：
  - P1-1: MainView.swift .dismiss case 末尾显式 dismissWindow(id: "playerControls")
  - P2-1: buildPrefetchRequests() 白名单过滤 scheme（file/http/https），SMB 不再触发无效请求
  - P2-2: Dolby Vision 检测回退为字符串字面量 "DolbyVisionConfiguration"（visionOS SDK 无公开常量）
  - P2-6: mergeFiles/mergeFolders 改用 Dictionary(_:uniquingKeysWith:) 防 crash
  - P2-7: detectProfile defer 块中 asset.cancelLoading()

  文档同步：
  - ARCHITECTURE.md App Invariants 新增沉浸空间统一路径约束
  - REGRESSION.md 新增 REG-134~REG-140 共 7 条

  构建验证：xcodebuild build_sim PASS（仅预存 warnings）
  VerifyList：51/51 全部 [x]
  
  next=test：所有 VerifyList 条目代码层面已完成，需 test 验证运行时行为。
  P2-2 实际修复方案与 review 建议不同（公开常量不存在），已验证构建通过。
