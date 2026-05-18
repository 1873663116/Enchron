# ExecPlan043 — Phase 2 T2.3 测试素材播放验证

**创建时间**: 2026-04-02
**阶段**: EXECUTING（Phase 2 T2.3）
**本轮目标**: 验证 12 种测试素材的投影类型自动检测正确性 + 渲染管线输出正确性

---

## 背景

- Round 16 已通过 spatial-media 工具为 4 个素材注入正确的投影/立体元数据
- Round 17 修复了 skybox 纹理加载
- Round 12 修复了 `.immersive` 模式 bridge 断联
- 现在需要验证检测管线能正确处理全部 12 种素材

## 本轮任务

### 步骤 1：代码结构审查
- 分析 `ProjectionDetection.swift` 全部检测逻辑
- 逐一验证 12 个素材的检测路径（基于 ffprobe 元数据 + 代码逻辑）
- 验证 `DecidePlaybackModeUseCase` 路由逻辑

### 步骤 2：渲染管线验证
- 每种 playback mode（window / immersive / panorama）的渲染路径完整性
- 特别关注：全景类（360°/180°/鱼眼）、立体类（SBS/OU）、HDR类（HDR10/DV/HLG/HDR10+）

### 步骤 3：汇总报告
- 输出 `docs/qa-reports/material-detection-report-v3.md`
- 标注每个素材的预期检测结果 vs 实际代码逻辑

## 验收条件
- 12/12 素材的检测路径清晰可追踪
- 无遗漏的检测断联或渲染黑洞
- 发现的问题标注优先级并记入修复队列
