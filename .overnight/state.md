next: review
status: IN_PROGRESS
iteration: 1
consecutive_failures: 0
goal: "修复 Enchron V2 全部已知 Bug（§5.4-§5.11）并严格对齐 player.html 播放控件设计，通过 VerifyList 闭环验证所有需求"
round: 2
context: |
  execute 轮完成。8 个 Unit 全部 PASS，无升级项。

  Unit 执行摘要：
  - Unit 1 §5.4 (P0): 移除 ornament 宽域 .animation() 修复菜单闪烁。决策门控：Menu-native
  - Unit 2 §5.5 (P0): 3s 超时 + fallback SDR profile + Task.isCancelled 检查
  - Unit 3 §5.6 (P0): 新建 MediaProfilePrefetchService（actor, 3并发, 3s超时），文件夹级别后台预读
  - Unit 4 §5.9 (P0): 统一入口(immersiveSpaceRequest) + dismissWindow(id:"main") + .full独占 + SpatialTapGesture控件召唤。结构守卫通过
  - Unit 5 §5.10 (P0): 图标对调、Play间距、SeekBar内边距、Spatial Audio标签对齐player.html
  - Unit 6 §5.7 (P1): skeleton .id(isLoading) + mergeFiles/mergeFolders增量刷新
  - Unit 7 §5.11 (P1): .move(edge:.bottom) 一行修复
  - Unit 8 §5.8 (P2): updateUIView 中显式设 nativeView.frame + layoutIfNeeded() 修复画布缩放

  ExecPlan 已归档至 docs/plans/complete/ExecPlan-2026-04-06-final.md
  下一轮：review — 代码审查 + VerifyList 标注 + 文档同步区补全 + 对抗审查
