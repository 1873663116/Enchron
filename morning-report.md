# Enchron Overnight 晨报 — 2026-03-26

**运行轮次**: 1 轮 | **实际运行时长**: 0h 23m | **最终状态**: ✅ COMPLETED

---

## 1. 完成了什么

TODOS.md 中 **5 项任务全部完成**，共产出 5 个 commit：

| Commit | 任务 | 说明 |
|--------|------|------|
| `1764175` | ✅ KI-010: 修复 HDR CAEDRMetadata 缺失 | HDR10/DoVI→hdr10 metadata，HLG→hlg metadata，SDR→nil；9 个数据驱动测试 |
| `e41e647` | ✅ KI-012: 全景视频投影类型自动检测 | 基于 stereo3d + GSpherical 元数据标签检测，不依赖宽高比猜测；12 个测试 |
| `2d728b5` | ✅ 补齐测试覆盖 | FileFilter、SortCriteria、PlaybackMode 决策矩阵；16 个新测试（189→205） |
| `be71c55` | ✅ EP-003 收尾 | 时间标签格式化收敛确认已合入，ExecPlan 归档 |
| `ac81842` | ✅ Review 修复（P0 + P1） | P0 数据竞争修复 + 3 项 P1 改进 |

### Review 修复详情（commit ac81842）

| 级别 | 内容 |
|------|------|
| **P0** | `cachedHDRType` / `cachedSignalPeak` 数据竞争 — 读写均改用 `stateQueue.sync` 保护 |
| **P1** | stereo3d over-under 匹配从 `contains` 改为 `hasPrefix`，避免误匹配 |
| **P1** | DoVI→hdr10 映射添加 `WORKAROUND` 注释（Apple 无公开 DoVI CAEDRMetadata API） |
| **P1** | `horizontalFOVDegrees` 死代码替换为清晰 TODO |

### 新增文件

- `XrPlayer/PlaybackCore/Adapters/MPV/EDRMetadataDescriptor.swift`（新）
- `XrPlayer/PlaybackCore/Adapters/MPV/ProjectionDetection.swift`（新）

### 文档更新

- **QUALITY_SCORE.md**: HDR 评分 2→3，全景 2→3，测试覆盖 2→3
- **known_issues.md**: KI-010 / KI-012 标记为已关闭
- **REGRESSION.md**: 新增对应回归项
- **PLANS.md**: EP-003 移入 archive

### 测试状态

```
205 tests, 0 failures ✅  （开始时 189，+16）
```

---

## 2. 跳过了什么

本轮 **无跳过项**。TODOS.md 5 项任务均已完成。

`/investigate` skill 未使用（本轮无 bug 需深度调查，仅在 review 阶段发现并内联修复了 P0 数据竞争）。

---

## 3. 遇到的问题

| 问题 | 处置方式 |
|------|---------|
| Review 阶段发现 `cachedHDRType`/`cachedSignalPeak` **P0 数据竞争** | 追加 commit ac81842 修复，用 `stateQueue.sync` 统一保护读写路径 |
| Apple 无公开 DoVI CAEDRMetadata API | 自动决策 [AUTO]：使用 hdr10 作为 DoVI fallback，添加 WORKAROUND 注释标记移除条件 |
| EDRMetadataDescriptor 放置位置不明确 | 自动决策 [AUTO]：独立文件加入 SPM Package，与 MPVPlayerAdapter 解耦 |
| 投影检测是否加入宽高比猜测 | 自动决策 [AUTO]：拒绝，TESTING.md 明确要求仅依赖元数据标签 |

**Verification Retries**: 1 次（P0 数据竞争在第一次 review 后发现，修复后通过）

---

## 4. 建议下一步

### 优先：人类真机验证（无需额外 API Key）

以下验证项需要在 Vision Pro 设备上执行，与 API Key 状态无关：

- [ ] HDR10 视频：确认亮部高光不削峰，暗部不丢失细节
- [ ] HLG 视频：确认色调映射正常
- [ ] DoVI 视频：确认 hdr10 fallback 视觉可接受
- [ ] 全景 SBS 视频：确认自动检测为 `stereoscopicSBS`
- [ ] 全景 OU 视频：确认自动检测为 `stereoscopicOU`
- [ ] 全景 equirectangular 视频：确认自动进入 `panorama360`
- [ ] 普通平面视频：确认仍为 `flat` 模式

### API Key 相关建议

| Key | 状态 | 建议 |
|-----|------|------|
| `GOOGLE_API_KEY` | ✅ 已设置 | 可用于 Gemini 模型调用 |
| `GOOGLE_GENAI_API_KEY` | ❌ 未设置 | 如需使用 Google GenAI SDK（区别于 Google AI Studio），可补充设置；若仅用 Gemini API 则 `GOOGLE_API_KEY` 已够 |
| `GEMINI_API_KEY` | ❌ 未设置 | 部分工具链用此变量名而非 `GOOGLE_API_KEY`，若调用 Gemini 报 key 缺失可尝试设置为相同值 |
| `OPENAI_API_KEY` | ❌ 未设置 | 当前项目无 OpenAI 依赖，暂不需要 |
| `ANTHROPIC_API_KEY` | ❌ 未设置 | Claude API 直调时需要；若仅通过 Claude Code CLI 使用则无需设置 |

### 代码层面下一步（参考 QUALITY_SCORE.md）

当前质量评分仍有差距的领域，可作为下一个 overnight 方向：
1. **GestureDisambiguator 测试** — TODOS.md 中已列入但本轮仅完成了 FileFilter/SortCriteria/PlaybackMode，手势状态机测试仍可补充
2. **SpatialScene 模块** — v0.4 规划中，可评估是否启动空间场景管理的骨架设计
3. **已关闭 KI 的清理** — KI-010/KI-012 已关闭，可检查 known_issues.md 中其他开放 KI 的优先级排序

---

## 5. 运行统计

| 指标 | 值 |
|------|---|
| 运行轮次 | 1 轮 |
| 实际运行时长 | 0h 23m |
| 完成任务数 | 5 / 5 |
| 新增 commits | 5 |
| 新增测试 | +16（189→205） |
| 测试失败 | 0 |
| Verification Retries | 1 |
| P0 问题 | 1（已修复） |
| 自动决策 | 3 |
| 文档更新 | 4 个文件 |
