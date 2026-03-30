# Overnight Log

---
## Round 1 — 2026-03-26T17:55:00+08:00

**Pipeline State**: EXECUTING → VERIFYING → COMPLETING
**Has Frontend**: false
**本轮完成**:
- KI-010: 实现 CAEDRMetadata 设置，HDR10/DoVI→hdr10 metadata, HLG→hlg, SDR→nil。9 个数据驱动测试。commit 1764175
- KI-012: 实现全景视频投影类型自动检测（stereo3d + GSpherical 元数据）。12 个测试。commit e41e647
- 补齐测试覆盖: FileFilter、SortCriteria、PlaybackMode 决策矩阵。16 个新测试（189→205）。commit 2d728b5
- EP-003 归档: 时间标签格式化收敛已完成，ExecPlan 标记 done 并移入 archive。commit be71c55
- 文档同步: QUALITY_SCORE.md（HDR 2→3, 全景 2→3, 测试 2→3）, known_issues.md（KI-010/KI-012 关闭）, REGRESSION.md 更新
- [SKILL] 未使用 /investigate（无 bug 需调查）

**Review 修复** (commit ac81842):
- P0: cachedHDRType/cachedSignalPeak 数据竞争 — 读写均用 stateQueue.sync 保护
- P1: stereo3d over-under 匹配从 contains→hasPrefix 避免误匹配
- P1: DoVI→hdr10 映射添加 WORKAROUND 注释
- P1: horizontalFOVDegrees 死代码替换为清晰 TODO

**Decision Log**:
- [AUTO] EDRMetadataDescriptor 放置位置 | 独立文件加入 SPM Package | P3 | MPVPlayerAdapter 不在测试模块，独立文件更简洁
- [AUTO] DoVI metadata 类型 | 使用 hdr10 而非专有 API | P5 | Apple 无公开 DoVI CAEDRMetadata API
- [AUTO] 投影检测不使用宽高比猜测 | 仅依赖元数据标签 | P1 | TESTING.md 明确要求不自动猜测

**产出文件**:
- XrPlayer/PlaybackCore/Adapters/MPV/EDRMetadataDescriptor.swift (新)
- XrPlayer/PlaybackCore/Adapters/MPV/ProjectionDetection.swift (新)
- XrPlayer/PlaybackCore/Adapters/MPV/MPVPlayerAdapter.swift (改)
- Tests/XrPlayerCoreTests/V04Tests.swift (改, +21 tests)
- Tests/XrPlayerCoreTests/CoreLogicTests.swift (改, +16 tests)
- Package.swift (改)
- QUALITY_SCORE.md, REGRESSION.md, known_issues.md, PLANS.md (改)

**Verification Retries**: 1 (P0 data race found in review, fixed in ac81842)
**Final Test**: 205 tests, 0 failures ✅
**Status**: COMPLETED

**人类真机验证清单**:
- [ ] HDR10 视频：确认亮部高光不削峰，暗部不丢失细节
- [ ] HLG 视频：确认色调映射正常
- [ ] DoVI 视频：确认 hdr10 fallback 可接受
- [ ] 全景 SBS 视频：确认自动检测为 stereoscopicSBS
- [ ] 全景 OU 视频：确认自动检测为 stereoscopicOU
- [ ] 全景 equirectangular 视频：确认自动进入 panorama360
- [ ] 普通平面视频：确认仍为 flat 模式
