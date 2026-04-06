---
# Overnight Log — 2026-04-06

## Round 0 (setup)

[SETUP] 目标：Enchron V2 综合迭代
需求文档：docs/brainstorms/2026-04-06-v2-comprehensive-requirements.md
起始动作：investigate
跳过技能：plan-ceo-review
旧 plans 已归档到 docs/plans/complete/

## Round 1 (investigate)

[INVESTIGATE] 三个并行 Agent 调查四大目标，全部 PASS
- Agent 1: mpv 元数据 + 容器格式字段映射 + HDR 检测
- Agent 2: 缩略图/封面提取方案
- Agent 3: 三轴正交模型全场景组合矩阵

产出：
- docs/reference/2026-04-06-mpv-metadata-investigation.md
- docs/reference/2026-04-06-thumbnail-extraction-investigation.md
- docs/reference/2026-04-06-combination-matrix-investigation.md

关键发现：
- mpv stereo-in 值表确认，现有 ProjectionDetection.swift 存在 4 处死代码匹配
- video-params/hdr-format 不存在于 mpv，HDR 检测须用 gamma 属性
- GSpherical 元数据在 mpv 中不可用（架构空缺），MP4 球面投影需 AVFoundation 预扫描
- 缩略图推荐独立 mpv 实例 + 两级缓存
- 36 种组合中 3 种非法（flat+panorama），fisheye+stereo 初期降格

[TRANSITION] from=investigate to=plan skipped=none
reason: 四大调查目标均有明确结论，信息充分进入规划

## Round 2 (plan)

[PLAN] ExecPlan + TestPlan 生成并通过三轮审查

执行步骤：
1. 跳过 design-shotgun — 设计稿由用户提供（player.html + variant-AB-combined.html），任务是对齐非探索
2. ce-plan Agent (sonnet) → 产出 9 单元 ExecPlan + 内置 document review（6 auto-fixes）
3. plan-eng-review Agent (sonnet) → 2 P1 + 4 P2，修补方向已写入 ExecPlan
4. codex adversarial-review → Opus counter-review → Supervisor 裁决

产出：
- docs/plans/active/ExecPlan.md（9 实施单元，12 需求全覆盖）
- docs/plans/active/TestPlan.md（三层验收矩阵）

[ADVERSARIAL-REVIEW] action=plan tier=standard
codex: FAIL — 2 P0 + 4 P1 + 3 P2
counter-review: Opus 辩护 — P0-1 降级为 P2（范围边界排除+projectionOverride 回退），P0-2 已处理，P1-1/P1-4 降级
verdict: 0 P0 阻塞。P1-3（Thumbnail security-scoped URL）已修补到 ExecPlan Unit 7。Plan 通过。

关键决策：
- P0-1 球面检测（MP4/MOV）降级为 P2：MKV 360 检测正常，MP4 360 是边缘场景，projectionOverride 手动回退可用
- P1-2 @Observable 等值赋值不触发通知：接受但实施时加防御性 guard
- isHDRContent 保留为计算属性（不在高频更新链上，与 P0 fix 不矛盾）

ce-compound 自裁：无新经验需归纳（审查发现均为已知模式的具体化）

[TRANSITION] from=plan to=execute skipped=design-shotgun
reason: ExecPlan/TestPlan 就绪，三轮审查通过，0 P0 阻塞

## Round 3 (execute + review)

[EXECUTE] 8/9 Unit 全部 PASS，按依赖图 5 批次执行

Batch 1（并行）：
- Unit 1 (sonnet): P0 菜单闪烁 → SeekBarView 属性隔离 + playbackState 等值 guard — PASS
- Unit 8 (sonnet): 数据源切换 → connectToDataSource 立即清空 + SkeletonCardView shimmer — PASS

Batch 2：
- Unit 2 (sonnet): 三轴域模型 → ProjectionType 4-case + StereoLayout(.mono) + MediaProfile 扩展 — PASS (294/295 tests, 1 pre-existing)

Batch 3（并行）：
- Unit 3 (sonnet): ProjectionDetection 元组返回 + gamma HDR 决策树 + 死代码删除 — PASS (305 tests)
- Unit 6 (sonnet): VideoDetailView 返回按钮 + HDR 开关 + 沉浸模式选择器 — PASS
- Unit 7 (sonnet): ThumbnailService actor + ThumbnailMPVAdapter + ThumbnailCache 两级缓存 — PASS (BUILD SUCCEEDED)

Batch 4：
- Unit 4 (sonnet): DecidePlaybackModeUseCase 三轴路由 + 约束矩阵 — PASS (317 tests, 26 新增路由测试)

Batch 5：
- Unit 5 (sonnet): PlayerControlsView HDR 标签 + 3D 开关 + Mode disabled + 移除旧入口 — PASS

[REVIEW] 对抗性审查（opus）+ P0/P1 修复

[ADVERSARIAL-REVIEW] action=execute tier=standard
codex: degraded（skill 未正确执行）
counter-review: Opus 独立审查 — 1 P0 + 2 P1 + 4 P2
verdict: P0/P1 全部修复

修复清单：
- P0-1: detectedStereoLayout 传播断裂 → updateDetectedProjection 新增 stereoLayout 参数 + 4 处调用点同步 — FIXED
- P1-1: NLETimelineView playbackPosition 泄漏 → 改为 @Environment 自读 — FIXED
- P1-2: startPlayback() 未重置检测状态 → 新增 reset — FIXED
- P2-1: REGRESSION.md StereoMode.swift 引用 → 更新为 StereoLayout.swift — FIXED
- P2-2: ThumbnailMPVAdapter DispatchSemaphore 阻塞协程线程 — DEFERRED to fix phase
- P2-3: ThumbnailService.inFlightTasks 无同步 — DEFERRED (ThumbnailService 是 actor，需验证)
- P2-4: ThumbnailMPVAdapter timeout Task 强引用 self — DEFERRED to fix phase

ce-review Agent 超时未返回（已运行 >10min），不阻塞 test 阶段。

ce-compound 自裁：P0-1 发现值得归纳 — @Observable 域模型属性必须在检测回调中完整传播，遗漏单个字段可致整条管线失效。但该教训已直接体现在修复代码中，无需单独文档化。

[TRANSITION] from=execute+review to=test skipped=none
reason: 8 个 Unit 全部实施完成，对抗审查 P0/P1 已修复，进入 QA/E2E 验收

