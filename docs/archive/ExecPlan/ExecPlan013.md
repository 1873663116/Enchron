# ExecPlan013 — T0.4 对抗性审查（三阶段裁决）

> Round: 4
> Phase: PLANNING
> 日期: 2026-04-02
> 目标: 对功能清单（EP010）+ 测试计划（EP012）执行三阶段对抗性审查

---

## 阶段 1: Codex 挑战

输入：EP010 完整功能清单（42 features × 5 categories）+ EP012 测试计划（43 tests × 8 files + 8 E2E paths）

**Codex 产出 5 条挑战：**

| # | 严重度 | 挑战内容 | 引用 |
|---|--------|---------|------|
| C1 | HIGH | EP013 执行记录为空，三阶段裁决未完成 | EP013:31-33 |
| C2 | HIGH | C1 (MediaProfile) 零测试覆盖，覆盖矩阵无映射 | EP012:306-317 |
| C3 | HIGH | A15 (SceneSelector) 仅映射到 test #1 枚举基数，不验证选择器接线 | EP012:48-49 |
| C4 | HIGH | GPU/渲染管线（A5/B2/B3/B4/B5）无确定性检查，建议 frame hash/pixel probes | qa-report |
| C5 | MEDIUM | E2E 断言过于主观（"可见星空元素"、"画面无畸变"），需量化 | EP012:355-407 |

---

## 阶段 2: Counter-Agent 反驳

| # | 裁定 | 反驳理由 |
|---|------|---------|
| C1 | REJECT | 自指问题——EP013 是正在执行的载体，执行记录在审查后填充是正确时序 |
| C2 | REJECT | 事实错误——V02Tests.swift:7 有 MediaProfileTests（4 tests），覆盖矩阵标注"已 ✅"正确 |
| C3 | PARTIAL ACCEPT | test #1 确实仅覆盖枚举结构，但 UI 接线属 E2E 范畴（P2-S10/S11 覆盖）；需补注释 |
| C4 | REJECT | visionOS Simulator 不支持 Metal GPU 渲染是硬约束；测试计划已正确处理域层数学部分 |
| C5 | PARTIAL ACCEPT | 状态转换步骤可量化（enum/property assertions），渲染质量步骤需标注"人工视觉验证" |

---

## 阶段 3: Opus 裁决

### 裁决依据
- Requirements.md §2.3 三种播放模式定义
- Requirements.md §3 架构约束（v1.0 必须完整虚拟场景能力）
- Round 2 context7 调研结果（9 项架构决策 D1-D9）
- visionOS Simulator 能力边界（无 Metal GPU 渲染）

### 逐条裁决

#### Challenge 1: EP013 执行记录为空 → **驳回**

EP013 正是当前三阶段审查的工作文档。执行记录在审查完成后填充是唯一合理的时序。不构成测试计划缺陷。

#### Challenge 2: C1 (MediaProfile) 零覆盖 → **驳回**

Codex 事实判断错误。已验证 `Tests/XrPlayerCoreTests/V02Tests.swift:7` 存在 `MediaProfileTests`，包含：
- `testResolutionClampsNegativeValues`
- `testResolutionAcceptsValidValues`
- `testMediaProfileEquality`
- `testMediaProfileFrameRateClamped`

覆盖矩阵"已 ✅"标注正确。E2E 中 P3-P8 的投影检测路径隐式覆盖 MediaProfile 组装。

#### Challenge 3: A15 SceneSelector 代理测试 → **部分采纳**

**有效部分**：test #1 (`testCinemaEnvironmentHasExactlyThreeCases`) 确实只验证枚举基数，不验证选择器 UI 接线。覆盖矩阵 A15→test#1 的映射关系不够精确。

**驳回部分**：选择器 UI 接线（点击触发环境切换、状态更新）不属于域层单元测试范畴。E2E P2-S3（确认暗黑影院）、P2-S10（切换到星空夜景）、P2-S11（确认星空渲染）已覆盖此功能路径。

**行动项**：在 EP012 覆盖矩阵 A15 行添加注释——"unit test #1 仅覆盖枚举结构；选择器接线和运行时环境切换由 E2E P2-S3, P2-S10, P2-S11 验证。"

#### Challenge 4: GPU/渲染管线无确定性检查 → **驳回（记录已知局限）**

**工程约束**：visionOS Simulator 不支持 Metal GPU 渲染。CVPixelBuffer → MTLTexture blit、hemisphere mesh 渲染、SBS/OU shader 输出均无法在 CI 中确定性验证。

**测试计划已正确处理**：
- 域层数学（UV rects tests 20-25, vertex count test 28, remap coords tests 31-32）有确定性单元测试
- GPU 渲染验证由 E2E P2-P6 人工视觉检查覆盖
- 覆盖矩阵 A5 行标注"需 Metal/GPU"

**行动项**：在 EP012 中增加"已知测试局限"节，明确记录 GPU 渲染验证边界。

#### Challenge 5: E2E 断言过于主观 → **采纳（降级执行）**

**有效观察**：以下 E2E 步骤使用不可量化语言——
- P2-S11: "可见星空元素"
- P2-S14: "暖色调背景 + 柔和光照"
- P6-S2: "画面无畸变"

**行动项**：修订 E2E 路径描述，分两类：
1. **状态转换步骤** → 改为可编程断言（如 `AppModel.currentEnvironment == .starryNight`、`activeScreenGeometry == .curved`）
2. **渲染质量步骤** → 明确标注 `[HUMAN VISUAL]` 并给出最低通过标准（如"星空纹理可见且无全黑帧"、"球体投影无可见接缝"）

---

### 裁决汇总

| Challenge | 裁决 | 测试计划变更 |
|-----------|------|-------------|
| C1 — 执行记录为空 | **驳回** | 无 |
| C2 — MediaProfile 零覆盖 | **驳回** | 无 |
| C3 — A15 代理测试 | **部分采纳** | 覆盖矩阵 A15 行补注释 |
| C4 — GPU 无确定性检查 | **驳回（记录局限）** | 增加"已知测试局限"节 |
| C5 — E2E 断言主观 | **采纳（降级）** | 修订 E2E 步骤描述 |

### 对测试计划的影响

- **测试数量不变**：43 个单元测试 + 8 条 E2E 路径维持不变
- **无新增测试**：所有被采纳的挑战均通过文档修订（注释 + 描述改进）解决，不需要增加新的测试用例
- **文档修订范围**：EP012 的覆盖矩阵注释 + E2E 路径描述 + 新增"已知测试局限"节

---

## Decision Log

- [AUTO] C1 驳回 | EP013 自指问题，非测试计划缺陷 | P5 | 执行记录在审查后填充
- [AUTO] C2 驳回 | MediaProfile 已有 4 个单元测试 (V02Tests.swift:7) | P5 | Codex 事实错误
- [AUTO] C3 部分采纳 | 补覆盖矩阵注释，不增测试 | P1+P5 | E2E 已覆盖选择器接线
- [AUTO] C4 驳回 | visionOS Simulator 无 Metal GPU 约束 | P3 | 域层数学已有确定性测试
- [AUTO] C5 采纳降级 | 修订 E2E 描述，分状态/渲染两类 | P1+P5 | 可量化优先，渲染标注人工
