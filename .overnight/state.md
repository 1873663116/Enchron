next: execute
status: IN_PROGRESS
iteration: 1
consecutive_failures: 0
goal: "修复 Enchron V2 全部已知 Bug（§5.4-§5.11）并严格对齐 player.html 播放控件设计，通过 VerifyList 闭环验证所有需求"
round: 1
context: |
  plan 轮完成。产出三件套：
  - ExecPlan.md: 8 Units（5 P0 + 2 P1 + 1 P2），依赖图已锁定
  - TestPlan.md: 70 测试项（含对抗审查补充的 7 项）
  - VerifyList.md: 51 条可验证需求

  plan-eng-review PASS（5 项发现已并入）：
  - A-1: SceneSelectorView/ToggleImmersiveSpaceButton 补入 Unit 4 文件清单
  - A-2: 窗口隐藏主路径定稿为 WindowGroup(id:"main") + dismissWindow
  - A-3: ImmersiveSpaceView 手势需 InputTargetComponent + CollisionComponent
  - A-4: openImmersiveSpace 返回 .opened 后才隐藏主窗口
  - Q-1: Unit 1 决策门控已加入

  对抗审查 REVISE→RESOLVED（2 P0 + 3 P1 + 1 P2 已修复）：
  - P0-1: 窗口隐藏策略收敛 + inTransition 门控写入实施步骤
  - P0-2: Unit 4 文件清单补充 + grep 结构守卫
  - P1-1: Unit 1 决策门控（Menu-native vs Popover-custom → 影响 Unit 5）
  - P1-2: TestPlan 补充 HLG + SBS/TB 测试
  - P1-3: TestPlan 补充错误路径测试
  - P2-1: 暂停态控件召唤

  并行组：Unit 1/2/4/6/7 可并行启动。Unit 3 依赖 Unit 2。Unit 5 依赖 Unit 1+4。Unit 8 最后。
  下一轮执行策略：dispatch 5 个并行 Agent（Unit 1/2/4/6/7），收结果后 dispatch Unit 3 和 Unit 5。
