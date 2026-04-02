# ExecPlan 041 — Round 22

**目标**: UX-02 VideoDetailView 分栏响应式布局
**Pipeline State**: EXECUTING (Phase 2 T2.2)
**时间**: 2026-04-02

## 改动范围

文件: `XrPlayer/PlayerUI/Views/VideoDetailView.swift`

## 方案设计

参考 HelloWorld `ModuleDetail.swift` 模式：
- `GeometryReader` 计算动态列宽
- 左栏 (40%, max 400pt): 文件标题 + 媒体元数据
- 右栏 (剩余): 轨道选择 + 播放按钮（ScrollView 保护溢出）
- HStack(spacing: 60) 水平分栏
- preparing/ready/failed 三个状态均需适配

## 实施步骤

1. 重构 `readyContent` — 分栏主布局
2. 重构 `preparingContent` — 分栏（右侧 ProgressView + 禁用按钮）
3. `failedContent` — 保持不变（ContentUnavailableView 自带布局）
4. swift build 验证
5. swift test 验证
6. git commit
