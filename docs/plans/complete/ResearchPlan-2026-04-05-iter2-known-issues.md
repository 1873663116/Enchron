# ResearchPlan: Known Issues 技术调查

## 调查目标

为 handoff 文档中 3 个未充分调查的问题收集 API 行为事实，支撑需求文档产出。
已完成调查：P1 播放模式层级约束（见 docs/reference/2026-04-05-playback-mode-hierarchy-investigation.md）

## Task 1: visionOS Hover Effect 形状控制

**问题**：按钮 hover 高亮为圆形，期望匹配按钮的圆角矩形
**调查方向**：
- `hoverEffect` modifier 在 visionOS 上的行为（highlight / lift / automatic）
- `.contentShape()` 是否影响 hover effect 的形状
- Apple HIG 对 visionOS hover/focus 的规范
- 查阅 apple-docs MCP

## Task 2: visionOS Ornament Transition/Animation

**问题**：ornament 内控件出现时有位移动画，期望纯 opacity 渐显
**调查方向**：
- `.ornament()` modifier 是否有内置 insertion/removal transition
- 如何覆盖 ornament 的默认动画
- `withAnimation` 包裹 vs `.animation()` modifier 在 ornament 中的差异
- 查阅 apple-docs MCP

## Task 3: UIViewRepresentable 窗口缩放响应

**问题**：visionOS 窗口缩放时，UIViewRepresentable 包裹的 Metal 渲染层尺寸不更新
**调查方向**：
- UIViewRepresentable 的 `updateUIView` 在 visionOS 窗口 resize 时是否被调用
- GeometryReader 包裹是否能触发 size 更新
- Metal layer resize 的正确时机
- 查阅 apple-docs MCP

## 预期产出

每个任务产出：API 行为事实 + 推荐修复策略，写入 docs/reference/
