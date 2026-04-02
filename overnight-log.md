# Enchron Overnight Log — v3 全覆盖 QA 驱动迭代

> 启动时间: 2026-04-02
> 模式: QA-Plan-First + 对抗性验证 + HelloWorld 参考审计
> 基线: v2 完成（15轮, 248 tests, QA 97.75, 13/13 终止条件）

---

## Round 1 — 2026-04-02T00:00:00+08:00

**Pipeline State**: PLANNING (v3 首轮)
**本轮目标**: T0.1 — 功能全清单提取（从用户视角）
**完成情况**:
- [AGENT] req-reader (Explore) → Requirements.md 2.1-2.5 提取 40 个用户功能
- [AGENT] design-reader (Explore) → product_philosophy.md + 9 design_docs 提取 17 个功能领域
- [AGENT] code-auditor (Sonnet) → 全模块代码审计，确认每个功能的实现状态
- 合成输出：`docs/qa-plans/feature-inventory-v3.md`（82 个功能点）

**功能清单统计**:
| 状态 | 数量 | 占比 |
|------|------|------|
| 🟢 已实现已验证 | 16 | 19% |
| 🟡 已实现未设备验证 | 46 | 56% |
| 🔴 未实现/缺素材 | 16 | 19% |
| ⚪ MVP 外推迟 | 4 | 5% |

**关键发现**:
- 🔴 P0 缺失：网络缓冲指示器、自动重连、HDR/SDR 实时切换按钮、文件列表进度提示
- 🔴 测试素材缺失：MOV/AVI/HDR10+/HLG/SBS/OU/鱼眼 共 7 种
- 🔴 代码缺陷：FOV 180/360 消歧 hardcoded nil、沉浸环境 skybox 纹理名定义但未加载、屏幕形状不持久化
- 🟡 大量功能（46个）仅结构验证，未在 Simulator 上做用户体验验证

**Decision Log**:
- [AUTO] 分类标准 | 🟢=swift test 覆盖 + v2 QA 验证, 🟡=代码存在未设备验证 | P1 | v2 QA 97.75 是结构分数非用户体验分数

**测试状态**: swift test: 未执行（本轮纯文档/审计） | 新增: 0 | FAIL: none
**下轮应做**: T0.2 — HelloWorld 参考审计（读实际代码对比 UX 模式）
**Status**: IN_PROGRESS

---

## Round 2 — 2026-04-02T01:00:00+08:00

**Pipeline State**: PLANNING → PLANNING（继续 T0.2）
**本轮目标**: T0.2 — HelloWorld 参考审计（读实际代码，与 Enchron 逐项对比 UX 模式）
**完成情况**:
- [AGENT] hw-navigation (Explore) → 读取 WorldApp/ViewModel/ModuleDetail/ModuleCard，对比 Scene定义/状态管理/布局/导航
- [AGENT] hw-controls (Explore) → 读取 GlobeControls/SliderGridRow/SettingsButton，对比 Glass面板/Slider布局/Ornament
- [AGENT] hw-gestures (Explore) → 读取 DragRotation/PlacementGestures/GlobeToggle/OrbitToggle/SolarSystemToggle，对比手势/动画/沉浸空间管理
- 合成输出：`docs/qa-plans/helloworld-ux-audit-v3.md`（12 项对比，1 P0 / 6 P1 / 3 P2 / 2 不采纳）

**关键发现**:
- P0: DragRotationModifier 缺失 — 沉浸空间中全景/虚拟屏幕无弹性拖拽交互、无惯性计算
- P1: VideoDetailView 纯纵向堆叠，应改为 GeometryReader 分栏响应式布局
- P1: Glass Effect 无自定义 cornerRadius，视觉层次不分明
- P1: 缺 SliderGridRow 可复用组件，设置面板占用过多纵向空间
- P1: ImmersiveSpace 固定 .full，无 .mixed 沉浸选项
- P1: 缺 Drag+Magnify 同时手势组合
- P1: 缺 openWindow/dismissWindow 窗口管理能力
- REJECT: 合并 4 个 ViewModel 为 1 个 → 违反 DDD 限界上下文设计，不采纳
- REJECT: 简化 ImmersiveSpace 状态机 → Enchron 的 3 态更健壮，不采纳

**Decision Log**:
- [AUTO] 合并 ViewModel 建议 | 不采纳 | P5 | HelloWorld 是演示项目单一状态，Enchron 是 DDD 5 限界上下文，分离符合架构意图
- [AUTO] ImmersiveSpace 状态机简化 | 不采纳 | P5 | 3 态防重复触发 + 错误恢复更健壮
- [AUTO] 12 个 HelloWorld 文件全部实际读取 | 已验证 | P1 | 铁律 #6 合规

**测试状态**: swift test: 未执行（本轮纯文档/审计） | 新增: 0 | FAIL: none
**下轮应做**: T0.3 — 测试素材清单与获取（盘点现有素材 + ffmpeg 转制/合成缺失素材）
**Status**: IN_PROGRESS

---

## Round 3 — 2026-04-02T02:00:00+08:00

**Pipeline State**: PLANNING → PLANNING（继续 T0.3）
**本轮目标**: T0.3 — 测试素材清单与获取（盘点现有 + ffmpeg 转制/合成缺失素材）
**完成情况**:
- ffprobe 盘点现有 5 个测试视频的容器/编码/色彩元数据
- ffmpeg 并行生成 7 个缺失素材（MOV/AVI/SBS/OU/鱼眼/HLG/HDR10+）
- HLG 首次生成 color_transfer 错误（bt709），通过 x265-params 显式设置 transfer=arib-std-b67 修复
- SBS/OU 首次生成缺少音频流（-map "[v]" 排除了音频），补加 -map 0:a 修复
- ffprobe 验证全部 12 个素材元数据正确（12/12 通过）

**素材清单（12 个文件，覆盖 14 种格式类别）**:
| 文件 | 容器 | 编码 | 色彩/投影 | 来源 |
|------|------|------|-----------|------|
| SDR-test.mkv | MKV | HEVC | BT.709 SDR | 已有 |
| HDR10-test.MP4 | MP4 | HEVC | BT.2020/PQ | 已有 |
| dolby-vision-test.mp4 | MP4 | HEVC+DV | DV | 已有 |
| 180-vr-test.mp4 | MP4 | HEVC | 180° VR | 已有 |
| 360-test-nasa-wind-tunnel.webm | WebM | VP9 | 360° | 已有 |
| SDR-test-sample.mov | MOV | HEVC | BT.709 SDR | 新建(remux) |
| SDR-test-sample.avi | AVI | H.264 | BT.709 SDR | 新建(transcode) |
| SBS-stereo3d-test.mp4 | MP4 | H.264 | SBS 立体 | 新建(hstack) |
| OU-stereo3d-test.mp4 | MP4 | H.264 | OU 立体 | 新建(vstack) |
| fisheye-test.mp4 | MP4 | H.264 | 鱼眼投影 | 新建(v360) |
| HLG-test.mp4 | MP4 | HEVC | BT.2020/HLG | 新建(transcode) |
| HDR10plus-test.mp4 | MP4 | HEVC | BT.2020/PQ+MDM | 新建(transcode) |

**Decision Log**:
- [AUTO] HDR10+ 素材 | 使用静态 mastering display metadata 近似，无真正动态 SEI | P3 | ffmpeg 无法生成真 HDR10+ 动态元数据，静态 MDM 足够测试检测管线
- [AUTO] 素材时长 | 全部 15s | P3 | 足够验证格式检测/播放启动，无需长视频

**测试状态**: swift test: 未执行（本轮纯素材生成） | 新增: 0 | FAIL: none
**下轮应做**: T0.4 — E2E QA 测试路径设计（为每个 🟡/🔴 功能设计端到端测试路径）
**Status**: IN_PROGRESS

---

## Round 4 — 2026-04-02T03:00:00+08:00

**Pipeline State**: PLANNING → PLANNING（继续 T0.4）
**本轮目标**: T0.4 — E2E QA 测试路径设计（55 条完整用户操作路径）
**完成情况**:
- Supervisor 直接设计 55 条 E2E QA 测试路径，覆盖 78/82 功能点
- 13 个类别：启动导航(3) + 文件源(4) + 窗口播放(5) + 沉浸影院(5) + 全景(5) + 3D立体(3) + 播放控件(7) + 手势(4) + 状态管理(5) + 错误处理(3) + HDR色彩(4) + 设置(4) + 辅助功能(3)
- 每条路径含具体预期结果（铁律 #8 合规）
- 标注 9 个已知缺陷预期 FAIL 项（4 P0 + 5 P1）
- 标注 11 条 Human-only 验证项（附原因）
- 产出：`docs/qa-plans/qa-plan-v3-comprehensive.md`

**QA 路径统计**:
| 验证类型 | 路径数 |
|----------|--------|
| Simulator 可执行 | 36 (65%) |
| Structure 结构验证 | 31 |
| Human-only 需真机 | 11 |
| 已知缺陷预期 FAIL | 9 |

**已知缺陷 P0（Phase 2 必修）**:
1. F4.1 无网络缓冲指示器
2. F4.3 无自动重连逻辑
3. F5.2 无 HDR/SDR 实时切换按钮
4. F4.7 文件列表进度提示 UI 缺失

**Decision Log**:
- [AUTO] QA 路径数量 55 条 vs TODOS 要求的最低覆盖 | 选择全覆盖 | P1 | 覆盖 78/82 功能点，排除 4 个 ⚪ MVP 外
- [AUTO] F1.14 (4K/8K 压力测试) 和 F1.23 (图片浏览) 不设路径 | 推迟 | P3 | 缺 8K 素材 + 图片浏览非 MVP
- [AUTO] 手势路径 (H01-H04) 标注 Human-only | 接受 | P5 | Simulator 手势模拟不等同真实 Hand Tracking，但保留 Structure 验证确认代码接线

**测试状态**: swift test: 未执行（本轮纯 QA 设计） | 新增: 0 | FAIL: none
**下轮应做**: T0.5 — 对抗性审查 QA 计划（三阶段裁决：Codex 挑战 → Counter-Agent 反驳 → Opus 裁决）
**Status**: IN_PROGRESS

---

## Round 5 — 2026-04-02T04:00:00+08:00

**Pipeline State**: PLANNING → PLANNING（继续 T0.5）
**本轮目标**: T0.5 — 对抗性审查 QA 计划（三阶段裁决）
**完成情况**:
- [SKILL] /codex:adversarial-review → needs-attention | 6 条挑战 (1 critical + 5 high)
- [AGENT] Counter-Agent (Sonnet) → 逐条评估 6 条挑战 | 2 ACCEPT + 2 PARTIALLY ACCEPT + 2 REBUT
- [SUPERVISOR] Opus 裁决 → 采纳 4 条（含 3 条采纳 Counter-Agent 修订版），驳回 2 条
- 产出：`docs/qa-plans/adversarial-review-v3.md`（完整裁决报告）
- QA 计划更新：+4 新路径 (QA-E06/L05/L06/M04)，修改 4 条路径，加 2 条升级注释

**三阶段裁决结果**:

| # | 挑战 | 严重度 | 裁决 | 行动 |
|---|------|--------|------|------|
| 1 | 沉浸环境纯色 dome 作为 PASS | critical | 采纳(CA版) | QA-D01/D04 加 KNOWN_FAIL 注释 |
| 2 | F7.5/F7.6/F8.3/F9.x 无 QA 路径 | high | 采纳(CA版) | +3 新路径 (QA-L05/L06/M04) |
| 3 | 时间轴 zoom 未测 | high | 驳回 | DetailedTimeline 是 scrubber 非 zoom |
| 4 | 网络异常仅结构验证 | high | 驳回+注释 | 功能不存在，加 Phase 2 升级注释 |
| 5 | 全景 180° 误判被接受 | high | 采纳 | QA-E02 误判→FAIL，QA-E03 定量化 |
| 6 | 跨模式状态机测试不足 | high | 采纳(CA版) | +1 新路径 (QA-E06) |

**QA 路径统计更新**:
| 指标 | 修改前 | 修改后 |
|------|--------|--------|
| 路径总数 | 55 | 59 (+4) |
| 覆盖功能 | 78/82 | 81/82 (+F7.5/F7.6/F8.3) |
| Simulator 可执行 | 36 | 37 |
| Structure 验证 | 31 | 35 |
| Human-only | 11 | 12 |
| 已知缺陷 FAIL | 9 | 9（E02 从描述升级为 FAIL） |

**Decision Log**:
- [AUTO] Challenge 1 (skybox) | 采纳 CA 版本（加注释不硬失败）| P3 | skybox 不在 P0/P1 列表，硬失败阻塞所有沉浸 QA 不成比例
- [AUTO] Challenge 3 (zoom) | 驳回 | P5 | DetailedTimeline 设计为固定中心指针 scrubber，Codex 误读功能
- [AUTO] Challenge 4 (网络) | 驳回+注释 | P4 | 功能🔴不存在，Simulator 无网络故障注入，结构验证是正确策略
- [AUTO] Challenge 5 (全景) | 全部采纳 | P1 | 全景领域不可降级，180° VR 误判直接影响核心用户体验
- [AUTO] Challenge 6 (跨模式) | 采纳 CA 版本（+1 路径不做压力测试）| P3 | 补充沉浸模式起点覆盖，快速切换压力测试超 MVP

**测试状态**: swift test: 未执行（本轮纯审查/文档） | 新增: 0 | FAIL: none
**下轮应做**: T0.6 — 验证所有功能是否真正实现（代码审查，非测试运行）
**Status**: IN_PROGRESS
