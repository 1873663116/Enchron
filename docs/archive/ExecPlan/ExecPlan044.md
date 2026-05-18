# ExecPlan044 — Phase 3 T3.1 全面回归

**创建时间**: 2026-04-02
**Pipeline State**: EXECUTING → VERIFYING
**本轮目标**: T3.1 全面回归 — swift test 全绿 + /qa 关键路径重新执行 + Health Score ≥ 95 + REGRESSION.md 更新

## 任务清单

1. [ ] swift test 确认全绿（≥ 248 tests, 0 FAIL）
2. [ ] swift build 确认零 error
3. [ ] /qa 重新执行修复后的关键 QA 路径（FAIL → PASS 升级验证）
4. [ ] 计算最终 Health Score
5. [ ] REGRESSION.md 新增本轮修复项的回归条目
6. [ ] overnight-log.md 追加 Round 25
7. [ ] 归档本 ExecPlan

## 关键路径（Phase 2 修复后需重验证）

| QA Path | Round 12 前状态 | 修复内容 | 预期升级 |
|---------|----------------|----------|----------|
| QA-D01 沉浸播放 | PARTIAL | F3.2 bridge 接通 (R12) | → PASS |
| QA-F03 SBS 沉浸屏幕 | FAIL | F3.2 + 素材元数据 (R12+R16) | → PARTIAL |
| QA-J01 网络缓冲 | PARTIAL | paused-for-cache 接线 (R13) | → PASS |
| QA-K03 HDR/SDR 切换 | FAIL | PlaybackMenuView HDR Toggle (R13) | → PASS |
| QA-A03 文件导航 | PARTIAL | 本地子文件夹导航修复 (R14) | → PASS |
| QA-D05 平面/曲面切换 | PARTIAL | screenShape 持久化 (R14) | → PASS |
| QA-H03 长按速度 | PARTIAL | 恢复用户原速度 (R15) | → PASS |
| QA-H04 捏合拖拽 | FAIL | drag-to-seek 实现 (R15) | → PASS |
| QA-E02 180° VR | FAIL | FOV 消歧 + 素材元数据 (R16+R24) | → PASS |
| QA-D04 环境切换 | PARTIAL | skybox 纹理加载 (R17) | → PASS |
| QA-G04 二级时间轴 | FAIL | DetailedTimelineView 接线 (R18) | → PASS |
| QA-M03 VoiceOver | FAIL | accessibilityLabel P1 (R18) | → PARTIAL |
| QA-E06 沉浸投影覆盖 | PASS | DragRotationModifier 加强 (R19-21) | → PASS+ |

## 注意

- T3.2 对抗性最终审查为下一轮目标（避免单轮超载）
