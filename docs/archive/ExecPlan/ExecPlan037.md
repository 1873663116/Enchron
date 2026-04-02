# ExecPlan037 — P1 缺陷修复: G04 二级时间轴 + M03 VoiceOver

**Round**: 18
**Phase**: EXECUTING (Phase 2 T2.1)
**Pipeline State**: EXECUTING

## 目标

修复两个 P1 缺陷：
1. **G04 二级时间轴接线**: DetailedTimelineGeometry 孤立组件，无 View 消费 → 接线到 PlayerControlsView
2. **M03 VoiceOver**: 全项目零 accessibilityLabel → 为关键交互元素添加辅助功能标注

## 计划

### G04 二级时间轴
1. 审查 DetailedTimelineGeometry 的 API
2. 找到 PlayerControlsView 中的时间轴 Slider
3. 将 DetailedTimelineGeometry 集成为精细 seek 模式

### M03 VoiceOver
1. 扫描所有 View 文件，识别缺少 accessibilityLabel 的交互元素
2. 按优先级添加：播放控件 > 文件浏览 > 设置 > 空间场景
3. 确保 Button/Toggle/Slider/Image 等都有标注

## 验收条件
- [ ] DetailedTimelineGeometry 被至少一个 View 消费
- [ ] 关键交互元素有 accessibilityLabel
- [ ] swift build 零 error
- [ ] swift test 全绿
