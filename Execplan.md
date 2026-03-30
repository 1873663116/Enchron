# Execplan — Round 1

本 ExecPlan 是活文档。Progress、Surprises & Discoveries、Decision Log、
Outcomes & Retrospective 四个章节必须在工作进行中保持更新。

本文档须遵循 PLANS.md（仓库根目录）的全部要求进行维护。

## Pipeline State
Pipeline State: COMPLETED
Has Frontend: false

## 本轮目标

本轮完成 TODOS.md 中所有 5 个任务：
1. **KI-010 修复 HDR CAEDRMetadata 缺失** ✅
2. **KI-012 实现全景视频投影类型自动检测** ✅
3. **补齐测试覆盖** ✅
4. **EP-003 收尾** ✅
5. **文档同步** ✅

## Progress

### KI-010: HDR CAEDRMetadata 修复
- [x] 阅读 MPVPlayerAdapter.swift，定位 applyHDRRuntimeConfiguration() 和 setHDREnabled()
- [x] 创建 EDRMetadataDescriptor.swift（可测试的纯值类型 + 选择逻辑）
- [x] 在 MPVPlayerAdapter 中添加 applyEDRMetadataToLayer() 方法
- [x] 在 applyHDRRuntimeConfiguration() 中调用 applyEDRMetadataToLayer()
- [x] 在 setHDREnabled() 中同步 edrMetadata
- [x] 在 detectAndNotifyMediaProfile() 中缓存 HDR 类型和信号峰值，SDR 内容清除旧 metadata
- [x] 补充 EDR metadata 选择逻辑数据驱动单元测试（9 个测试用例）
- [x] 执行 agent 自检六件套: swift build ✅ | swift test 186 pass ✅ | swiftlint ✅ | check-workaround ✅
- [x] 更新 QUALITY_SCORE.md HDR 可信度评分 2→3
- [x] 更新 known_issues.md KI-010 标记为已关闭
- [x] git commit: 1764175

### KI-012: 全景视频投影类型自动检测
- [x] 创建 ProjectionDetection.swift（纯函数 + 输入快照类型）
- [x] 在 detectAndNotifyMediaProfile() 中读取 mpv metadata 并调用
- [x] 补充 12 个投影类型检测数据驱动单元测试
- [x] 更新 QUALITY_SCORE.md 全景模式评分 2→3
- [x] git commit: e41e647

### 补齐测试覆盖
- [x] FileFilter 边界测试 (6 tests)
- [x] SortCriteria 排序正确性 (6 tests)
- [x] PlaybackMode 决策矩阵 (4 tests)
- [x] git commit: 2d728b5

### EP-003 收尾
- [x] 归档 ExecPlan，PLANS.md 标记 done
- [x] git commit: be71c55

### 文档同步
- [x] QUALITY_SCORE.md 三项 2→3
- [x] known_issues.md KI-010/KI-012 关闭
- [x] REGRESSION.md 更新

### Review 修复
- [x] P0: cachedHDRType/cachedSignalPeak 数据竞争修复（stateQueue.sync 保护）
- [x] P1: stereo3d over-under 匹配收紧（hasPrefix 替代 contains）
- [x] P1: DoVI→hdr10 WORKAROUND 注释
- [x] P1: horizontalFOVDegrees 死代码清理
- [x] 重新构建 + 测试: 205 tests, 0 failures ✅
- [x] git commit: ac81842

## Failure Tracking

无失败记录。

## Decision Log

- Decision: 将 EDRMetadataDescriptor 和 EDRMetadataSelection 抽取为独立文件，而非内联在 MPVPlayerAdapter 中
  Rationale: MPVPlayerAdapter 不在 SPM XrPlayerCore 模块中，无法被测试模块访问。独立文件可加入 Package.swift sources 使测试可达。
  Date: 2026-03-26

- Decision: DoVI 使用 hdr10 metadata 而非专有 API
  Rationale: Apple 没有公开的 Dolby Vision CAEDRMetadata API。使用 hdr10 metadata 是最接近的近似。
  Date: 2026-03-26

- Decision: 投影检测不使用宽高比猜测
  Rationale: TESTING.md 明确要求不自动猜测，仅依赖元数据标签。
  Date: 2026-03-26

## Surprises & Discoveries

- CAEDRMetadata.hlg 在 visionOS 上直接可用，无需传入 ambientViewingEnvironment 参数（`.hlg` 是静态属性）。
- mpv stereo3d tags 有多种变体（sbs, ab2l, abr, over_under_left 等），需要全面匹配但又不能过于宽泛。

## Outcomes & Retrospective

所有 5 个 TODOS 任务已完成，共 5 个 commits。Code review 发现 P0 数据竞争已修复。
最终状态：205 tests, 0 failures。三项质量评分 2→3。

待人类真机验证：HDR 视觉效果、全景自动检测进入正确模式。

## Last Updated
2026-03-26T18:15:00+08:00
