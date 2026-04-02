# Enchron v3 — QA 计划对抗性审查报告

> 生成时间: 2026-04-02 (v3 Round 5)
> 审查目标: qa-plan-v3-comprehensive.md (55 条路径) + feature-inventory-v3.md (82 功能)
> 三阶段裁决: Codex 挑战 → Counter-Agent 反驳 → Opus 裁决

---

## 裁决汇总

| # | 挑战 | 严重度 | Codex 建议 | Counter-Agent | Opus 裁决 | 行动 |
|---|------|--------|-----------|---------------|-----------|------|
| 1 | 沉浸环境接受纯色为 PASS | critical | 硬失败直到 skybox 通过 | 部分接受 — 加注释不硬失败 | **采纳 CA 版本** | 加 KNOWN_FAIL 注释 |
| 2 | F7.5/F7.6/F8.3/F9.x 无 QA 路径 | high | 全部加路径 | 部分接受 — F7.5/F7.6/F8.3 加路径，F9.x 保持 | **采纳 CA 版本** | +3 新路径 |
| 3 | 时间轴 zoom 未测 | high | 加 zoom 断言 | 驳回 — 功能是 scrubber 非 zoom | **驳回** | 无行动 |
| 4 | 网络异常仅结构验证 | high | 加运行时 E2E | 驳回 — 功能不存在+模拟器限制 | **驳回（加注释）** | 加升级注释 |
| 5 | 全景分类错误被接受 | high | E02 硬失败，E03 可量化 | 全部接受 | **采纳** | 修改 E02+E03 |
| 6 | 跨模式状态机测试不足 | high | 加快速切换压力测试 | 部分接受 — 加 1 条路径不做压力 | **采纳 CA 版本** | +1 新路径 QA-E06 |

**总计**: 6 条挑战，采纳 4 条（含 3 条采纳 Counter-Agent 修订版），驳回 2 条

---

## 详细裁决

### Challenge 1: 沉浸环境纯色 dome — 采纳（Counter-Agent 版本）

**Codex 挑战**: QA-D01/D04 将纯色 dome 编码为通过结果，F6.1-F6.3 skybox 纹理加载缺失被掩盖
**Counter-Agent**: 加 inline "已知缺陷" 注释（与 QA-D05 F6.6 格式一致），但不硬失败
**Opus 裁决**: **采纳 Counter-Agent 版本**

**理由**:
- skybox 纹理加载不在 P0/P1 优先级列表中，团队视纯色为 MVP 可接受状态
- 硬失败会阻塞所有沉浸空间 QA 路径，不成比例
- 但 Codex 指出的"假阳性"问题确实存在——QA 报告不应让纯色看起来像"完成"
- 加 KNOWN_FAIL 注释足够标记差距，Phase 2 决定是否升级

**行动**: QA-D01 step 2 和 QA-D04 expected results 加 "已知缺陷 F6.1-F6.3: 环境为纯色 UnlitMaterial，非 Skybox 纹理，视觉效果低于设计目标"

---

### Challenge 2: 缺失 QA 路径 — 采纳（Counter-Agent 版本）

**Codex 挑战**: F7.5/F7.6/F8.3/F9.1-F9.3 无正式 QA 路径 ID
**Counter-Agent**: F7.5/F7.6 加 Structure 路径（预期 FAIL）；F8.3 加 Structure stub + Human-only；F9.x 保持 Human-only
**Opus 裁决**: **采纳 Counter-Agent 版本**

**理由**:
- F7.5/F7.6 确实可以用代码审查确认是否存在，应有正式路径而非只在矩阵中写 "—"
- F8.3 WorldTrackingProvider 接线可以结构验证
- F9.1-F9.3 Simulator 确实无法测量（无内存 profiler、无帧率 instrument）
- 修正覆盖声明为更精确的表述

**行动**:
- 新增 QA-L05: F7.5 远程缓存清理 UI 存在性检查（预期 FAIL）
- 新增 QA-L06: F7.6 关于页面存在性检查（预期 FAIL）
- 新增 QA-M04: F8.3 WorldTrackingProvider 接线检查 + Human-only
- 修正覆盖声明

---

### Challenge 3: 时间轴 zoom — 驳回

**Codex 挑战**: QA-G04 未测试 zoom 缩放
**Counter-Agent**: DetailedTimeline 是固定中心指针 scrubber，不是 zoom 交互
**Opus 裁决**: **驳回**

**理由**:
- F3.10 "二级时间轴/精细 Scrubber" 的设计是固定中心指针模型（代码中明确定义）
- QA-G04 的步骤（模式切换、水平滑动、退出）完整覆盖了该功能的设计交互
- Codex 将 "更高时间精度" 误读为 "视觉缩放"，实际是 scrub 模式而非 zoom 模式
- 不存在需要测试的 zoom 缩放参数

---

### Challenge 4: 网络异常运行时测试 — 驳回（加升级注释）

**Codex 挑战**: QA-J01~J03 应加运行时网络故障注入
**Counter-Agent**: F4.1/F4.3 功能不存在（🔴），Simulator 无法注入网络故障
**Opus 裁决**: **驳回（加升级注释）**

**理由**:
- F4.1 "无缓冲指示器实现"、F4.3 "无自动重连逻辑" — 功能代码不存在
- QA-J01/J03 已标注 "预期 FAIL"，结构验证确认缺失是正确的验证策略
- 对不存在的功能做运行时 E2E 只会得到相同的 FAIL 结果，基础设施开销不成比例
- 当功能实现后（Phase 2），应升级为运行时测试

**行动**: 在 QA-J01 和 QA-J03 加升级注释: "Phase 2 实现 F4.1/F4.3 后，本路径应升级为运行时 E2E（含网络故障注入）"

---

### Challenge 5: 全景分类错误 — 采纳

**Codex 挑战**: QA-E02 接受 180° 误判为 360° 作为"已知缺陷"但不 FAIL；QA-E03 使用定性断言
**Counter-Agent**: 全部接受
**Opus 裁决**: **采纳**

**理由**:
- **这属于全景视频领域，不可轻易驳回**
- F1.21（FOV 180/360 消歧 hardcoded nil）是明确的代码缺陷，根因已知
- 将误判结果描述为"可观察表现"而非 FAIL，降低了修复紧迫性
- 180° VR 是核心用户场景（Requirements 2.3），误判直接导致画面严重变形
- QA-E03 "无明显扭曲" 不可测试，应替换为可验证的结构断言

**行动**:
- QA-E02: 误判结果改为 "FAIL — F1.21 bug active, 180° content requires correct half-sphere projection"
- QA-E03: 替换 "无明显扭曲" 为 "VideoShaders.metal fisheye_remap compute shader 被调用确认（结构路径验证）；视觉质量评估 deferred to Human-only"

---

### Challenge 6: 跨模式状态机 — 采纳（Counter-Agent 版本）

**Codex 挑战**: QA-E04 只从窗口模式测试投影覆盖，缺少从沉浸模式开始的路径
**Counter-Agent**: 加 1 条 QA-E06，不做快速切换压力测试
**Opus 裁决**: **采纳 Counter-Agent 版本**

**理由**:
- **这属于播放模式路由领域，不可轻易驳回**
- 沉浸模式中覆盖投影涉及 ImmersiveSpace dismiss/open + entity 重建，失败概率更高
- v2 R14 修复了 effectiveProjectionType 路由链，但仅从窗口模式验证不够
- 快速切换压力测试过度工程——visionOS 本身对快速 ImmersiveSpace 切换就有限制（Apple 文档警告）
- 一条额外路径覆盖"沉浸模式起点"足矣

**行动**: 新增 QA-E06: 沉浸空间中手动覆盖投影为 360° → 观察模式切换 → 恢复自动检测

---

## 对 QA 计划的修订汇总

### 新增路径 (4 条)
1. **QA-E06**: 沉浸空间中投影覆盖（F1.22, F3.4）— Structure + Simulator
2. **QA-L05**: 远程缓存清理 UI 检查（F7.5）— Structure（预期 FAIL）
3. **QA-L06**: 关于页面检查（F7.6）— Structure（预期 FAIL）
4. **QA-M04**: WorldTrackingProvider 接线检查（F8.3）— Structure + Human-only

### 修改路径 (4 条)
1. **QA-D01**: step 2 加 "已知缺陷 F6.1-F6.3" 注释
2. **QA-D04**: expected results 加 "已知缺陷 F6.1-F6.3" 注释
3. **QA-E02**: 误判结果从描述改为 FAIL
4. **QA-E03**: "无明显扭曲" 改为结构路径验证断言

### 加注释 (2 条)
1. **QA-J01**: 加 Phase 2 升级注释
2. **QA-J03**: 加 Phase 2 升级注释

### 路径总数变化
- 修改前: 55 条
- 修改后: 59 条 (+4)
- 覆盖功能: 78/82 → 81/82（+F7.5, +F7.6, +F8.3；F9.4/F9.5 仍为 ⚪ 真机限定）

---

## 已知缺陷预期 FAIL 项更新

| QA 路径 | 功能 | 已知缺陷 | 优先级 |
|---------|------|---------|--------|
| QA-J01 | F4.1 | 无网络缓冲指示器 | P0 |
| QA-J03 | F4.3 | 无自动重连逻辑 | P0 |
| QA-K03 | F5.2 | 无 HDR/SDR 实时切换按钮 | P0 |
| QA-I05 | F4.7 | 文件列表进度提示 UI 缺失 | P0 |
| QA-D05 | F6.6 | 屏幕形状不持久化 | P1 |
| QA-E02 | F1.21 | FOV 180/360 消歧 hardcoded nil（**升级为 FAIL**） | P1 |
| QA-M03 | F8.4 | VoiceOver 标签未审计 | P1 |
| QA-L05 | F7.5 | 远程缓存清理 UI 缺失（**新增**） | P1 |
| QA-L06 | F7.6 | About 页面缺失（**新增**） | P1 |
