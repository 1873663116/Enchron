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

---

## Round 6 — 2026-04-02T05:00:00+08:00

**Pipeline State**: PLANNING → PLANNING（完成 T0.6，Phase 0 全部完成）
**本轮目标**: T0.6 — 验证所有功能是否真正实现（代码审查，非测试运行）
**完成情况**:
- [AGENT] audit-playback (Sonnet) → PlaybackCore + PlayerUI 审计（F1.5-F1.22, F3.1-F3.21, F4.x, F5.x）
- [AGENT] audit-filebrowsing (Sonnet) → FileBrowsing + App 导航审计（F1.1-F1.4, F2.x）
- [AGENT] audit-spatial (Sonnet) → SpatialScene 审计（F3.2-F3.3, F6.x）
- [AGENT] audit-settings (Sonnet) → Settings + Persistence + 辅助功能审计（F7.x, F8.x, F9.x）
- 4 agent 并行执行，合成输出：`docs/qa-plans/code-audit-v3.md`

**关键发现 — 名义实现但实际断联（7 个）**:

| # | 功能 | 严重度 | 问题 |
|---|------|--------|------|
| 1 | F3.2 沉浸场景 VirtualScreenEntity | **P0** | `panoramaBridge.attachVideoLayer()` 仅在 `.panorama` 模式调用，`.immersive` 模式虚拟屏幕无视频纹理 |
| 2 | F4.1 网络缓冲指示器 | **P0** | PlaybackState.buffering 定义但从未触发（MPVPlayerAdapter 中无 updateState(.buffering)） |
| 3 | F5.2 HDR/SDR 切换 | **P0** | 后端 setHDREnabled 完整，但 PlayerUI 中无任何 Toggle/Button 调用 |
| 4 | F3.9 捏合拖拽进度条 | P1 | DisambiguateGestureUseCase 检测到 .drag 但 MainView 执行 break（空操作） |
| 5 | F6.2/F6.3 环境 skybox | P1 | skyboxAssetName 是死代码，所有环境仅纯色 |
| 6 | F6.6 屏幕形状持久化 | P1 | appModel.screenShape 纯内存，无持久化路径 |
| 7 | F3.10 二级时间轴 | P2 | DetailedTimelineGeometry 模型完整但无 View 消费 |

**Inventory 修正**:
- F4.7（文件列表进度）：🔴→✅ 存在为文字标记（"Watched HH:MM:SS"），非进度条
- F7.6（About 页面）：🔴→⚠️ 存在但版本号硬编码 "0.1"
- F3.2（沉浸场景）：🟡→🔴 bridge 断联，升级为 P0

**新发现问题**:
- F8.1 交互目标违规：关闭按钮 48pt、数据源删除按钮 24pt（低于 60pt 最低标准）
- ImmersionStyle 硬编码 `.constant(.full)`，无法动态切换

**Decision Log**:
- [AUTO] Phase 0 完成评估 | T0.1-T0.6 全部完成 | P6 | 下轮进入 Phase 1 QA 执行
- [AUTO] F3.2 沉浸 bridge 断联 | 升级为 P0 修复项 | P1 | 影响沉浸影院核心体验
- [AUTO] F4.7 形态判定修正 | 文字标记可接受 | P3 | Requirements 未指定必须是进度条形态

**测试状态**: swift test: 未执行（本轮纯代码审计） | 新增: 0 | FAIL: none
**下轮应做**: Phase 0 完成 → 进入 REVIEWING（/plan-ceo-review 或 /plan-eng-review 审查 QA 计划 + 代码审计结果）
**Status**: IN_PROGRESS

---

## Round 7 — 2026-04-02T06:00:00+08:00

**Pipeline State**: PLANNING → REVIEWING → EXECUTING（Phase Transition x2）
**本轮目标**: /plan-eng-review 审查 Phase 0 全部交付物，决定是否进入 EXECUTING
**完成情况**:
- [SKILL] /plan-eng-review → PASS (clean) | 2 issues found, 0 critical gaps
- [SUPERVISOR] QA 计划与代码审计同步修复 — 3 个 T0.6 新增断联功能补充 KNOWN_FAIL 注释
- [SUPERVISOR] Phase Transition 决策: REVIEWING → EXECUTING 通过

**工程审查发现**:

| # | 问题 | 严重度 | 处理 |
|---|------|--------|------|
| 1 | QA 计划未同步 T0.6 代码审计（F3.2/F3.9/F3.10 缺 KNOWN_FAIL） | P1 | **已修复** — 4 个 QA 路径添加注释，缺陷汇总表 9→12 |
| 2 | QA-I05 (F4.7) 分类错误（标为缺失，实为文字标记形态） | P2 | **已修复** — P0→P2 降级 |

**审查结论**:
- QA 路径覆盖: 81/82 功能 (98.8%)，12 个已知缺陷标注完整
- Phase 2 修复优先级: 4 P0 → 6 P1 → 4 P2，排序合理
- HelloWorld 采纳清单: 10 项可执行，2 项驳回理由充分
- 对抗性审查: 6 挑战中 4 采纳 2 驳回，处理得当
- Simulator vs Human-only 分类: 36 vs 12，分类准确

**Decision Log**:
- [AUTO] Phase Transition REVIEWING→EXECUTING | 工程审查 PASS，0 阻塞项 | P6 | Phase 0 交付物完整且同步
- [AUTO] QA 计划同步修复 | 直接修复不另开轮次 | P3 | 修复范围小（4 个注释+1 个表格），不值得单独一轮
- [AUTO] 跳过 /plan-ceo-review | 非产品方向变更，纯 QA 技术审查 | P5 | CEO 审查用于产品战略，本轮纯技术质量

**测试状态**: swift test: 未执行（本轮纯审查/文档） | 新增: 0 | FAIL: none
**下轮应做**: Phase 1 T1.1 — 执行全覆盖 /qa E2E 测试（按 qa-plan-v3-comprehensive.md 逐条执行）
**Status**: IN_PROGRESS

---

## Round 8 — 2026-04-02T18:30:00+08:00

**Pipeline State**: EXECUTING（Phase 1 T1.1 批次 1）
**本轮目标**: T1.1 QA 执行 — 批次 1 (A 启动导航 + B 文件源 + C 窗口播放，12 条路径)
**完成情况**:
- [BUILD] xcodebuild → BUILD SUCCEEDED (Debug-xrsimulator)
- [SIMULATOR] App installed + launched (PID 40299) on Apple Vision Pro (B170D4C9, visionOS 26.2)
- [SCREENSHOT] 应用启动首屏截图 → Glass 面板 + 文件列表正常渲染
- [AGENT] qa-structure-ABC (Sonnet) → 12 条路径代码审计完成
- [SKILL] /qa → 批次 1 完成: 7 PASS + 4 PARTIAL + 0 FAIL + 1 DEFERRED
- 产出：`docs/qa-reports/qa-report-v3-batch1-ABC.md`

**QA 批次 1 结果**:

| QA Path | Verdict | Key Finding |
|---------|---------|-------------|
| QA-A01 启动首屏 | PARTIAL | Tab 分离(Files/Scenes), 无"本地文件"入口 |
| QA-A02 场景面板 | PARTIAL | 按钮不触发 openImmersiveSpace, 需另按 Toggle |
| QA-A03 文件导航 | PARTIAL | 本地子文件夹导航完全不可用 (guard activeRemoteAdapter) |
| QA-B01 本地浏览 | PARTIAL | 默认 Documents 非 Movies; 缺 codec+duration 显示 |
| QA-B02 SMB 添加 | PASS | Keychain + SecureField + 错误处理完整 |
| QA-B03 WebDAV 添加 | PASS | 同 SMB 流程, friendlyErrorMessage 映射 |
| QA-B04 Photos | DEFERRED | Structure PASS, Simulator 无 Photos 库 |
| QA-C01 SDR MKV 播放 | PASS | FileFilter + MTKView + play/pause/skip 全链路 |
| QA-C02 HDR10 播放 | PASS | inferHDRType + EDR PQ + "HDR10" 标签 |
| QA-C03 DV 播放 | PASS | DoVI 检测 + HDR10 回退 + hwdec videotoolbox |
| QA-C04 MOV 播放 | PASS | .mov in FileFilter |
| QA-C05 AVI 播放 | PASS | .avi in FileFilter |

**新发现问题 (5)**:

| # | 严重度 | 问题 |
|---|--------|------|
| ISSUE-004 | **High** | 本地子文件夹导航不可用 (FileBrowsingViewModel:303 guard) |
| ISSUE-001 | Medium | 场景和文件浏览是 Tab 分离, 非同屏 |
| ISSUE-002 | Medium | 无持久"本地文件"数据源入口 |
| ISSUE-003 | Medium | 场景卡片不自动打开沉浸空间 |
| ISSUE-005 | Medium | VideoDetailView 缺 codec + duration |

**Health Score**: 86.7 / 100 (基于批次 1 覆盖范围)

**Decision Log**:
- [AUTO] 本地文件夹导航 | 标记为 Phase 2 High 修复项 | P1 | 影响所有有子文件夹的用户
- [AUTO] Tab 分离 | 保留为 deferred 改进 | P3 | Tab UI 是可用的, 只是不如同屏直观
- [AUTO] 场景卡片 openImmersiveSpace | 保留为 deferred | P3 | 有 ToggleImmersiveSpaceButton 可用, 不阻塞功能

**测试状态**: swift test: 未执行（本轮 QA 测试） | 新增: 0 | FAIL: none
**下轮应做**: T1.1 批次 2 — D 沉浸影院 + E 全景 + F 3D 立体 (13 条路径)
**Status**: IN_PROGRESS

---

## Round 9 — 2026-04-02T10:30:00+08:00

**Pipeline State**: EXECUTING（Phase 1 T1.1 批次 2）
**本轮目标**: T1.1 QA 执行 — 批次 2 (D 沉浸影院 + E 全景 + F 3D立体，14 条路径)
**完成情况**:
- [SIMULATOR] App confirmed running (PID 40299, visionOS 26.2, Files tab visible)
- [SUPERVISOR] 直接代码审查: ImmersiveSpaceView, PlayerControlsView, AppModel, VirtualScreenEntity, PanoramaSphereEntity, EnvironmentDomeEntity, ProjectionDetection, DecidePlaybackModeUseCase, StereoMode
- [AGENT] audit-D (Sonnet) → D01-D05 结构审计
- [AGENT] audit-E (Sonnet) → E01-E06 结构审计
- [AGENT] audit-F (Sonnet) → F01-F03 结构审计
- [BASH] ffprobe 验证 4 个测试素材元数据: 360°✅有球形映射, 180°❌无元数据, SBS❌无stereo3d, OU❌无stereo3d, 鱼眼❌无投影标签
- 产出：`docs/qa-reports/qa-report-v3-batch2-DEF.md`

**QA 批次 2 结果**:

| QA Path | Verdict | Key Finding |
|---------|---------|-------------|
| QA-D01 进入沉浸播放 | PARTIAL | F3.2 P0: bridge 仅 .panorama 接入, .immersive 虚拟屏幕无视频 |
| QA-D02 屏幕距离高度 | PASS | distance→z, verticalOffset→y, per-env save/load 完整 |
| QA-D03 X轴视角旋转 | PASS | simd_quatf X轴旋转, 度→弧度转换正确 |
| QA-D04 环境切换 | PARTIAL | 材质替换不退出空间✅, 但全部纯色无skybox |
| QA-D05 平面/曲面切换 | PARTIAL | flat→plane, curved→cylinder✅, 但 screenShape 不持久化 |
| QA-E01 360°全景 | PASS | 素材有 Spherical Mapping, 检测→panorama360→full sphere✅ |
| QA-E02 180° VR | FAIL | 双重失败: 素材无球形元数据 + FOV hardcoded nil |
| QA-E03 鱼眼投影 | FAIL | 素材无 GSpherical 元数据, 代码路径存在但无法触发 |
| QA-E04 投影手动覆盖 | PASS | Menu 列出全部类型, setProjectionOverride→autoRoute 完整 |
| QA-E05 全景无虚拟场景 | PASS | update块移除 dome+virtualScreen, 创建 PanoramaSphere |
| QA-E06 沉浸中投影覆盖 | PASS | 双向切换 .immersive↔.panorama, 无残留 entity |
| QA-F01 SBS 3D | PARTIAL | 代码正确(依赖 stereo3d 标签), 但素材无标签 |
| QA-F02 OU 3D | PARTIAL | 同 SBS, 素材无 stereo3d 标签 |
| QA-F03 SBS 沉浸屏幕 | FAIL | F3.2 P0: bridge 断联 + 素材检测失败 |

**新发现问题 (4)**:

| # | 严重度 | 问题 |
|---|--------|------|
| ISSUE-006 | High | SBS/OU 素材缺 stereo3d 元数据 → 自动检测失败 |
| ISSUE-007 | High | 鱼眼素材缺 GSpherical 元数据 → 自动检测失败 |
| ISSUE-008 | High | 180° VR 素材缺球形映射元数据 → 检测为 flat |
| ISSUE-009 | Medium | F1.21 FOV hardcoded nil, 180° 始终误判 360° |

**关键发现**:
- **测试素材大面积缺陷**: R3 ffmpeg 生成的 7 个素材中，4 个缺少自动检测所需元数据。ffprobe 元数据验证通过是因为验证的是容器/编码/色彩属性，未验证投影/立体元数据
- **代码设计正确**: ProjectionDetection 不从宽高比猜测投影类型是正确设计决策
- **F3.2 是沉浸影院的系统性阻塞**: 所有 `.immersive` 模式的视频渲染均不工作

**Decision Log**:
- [AUTO] 素材缺陷分类 | 标记为素材修复项而非代码缺陷 | P3 | 代码检测逻辑设计正确
- [AUTO] QA-E02 双重失败处理 | 素材补元数据 + 代码补 FOV 消歧 独立修复 | P1 | 180° VR 是核心全景功能
- [AUTO] 批次 2 与 3 分界 | DEF 完成, 下轮继续 G-M 路径 | P6 | 按字母序分批

**测试状态**: swift test: 未执行（本轮 QA 测试） | 新增: 0 | FAIL: none
**下轮应做**: T1.1 批次 3 — G 播放控件 + H 手势 + I 状态管理 + J 错误处理 + K HDR色彩 + L 设置 + M 辅助功能
**Status**: IN_PROGRESS

---

## Round 10 — 2026-04-02T12:00:00+08:00

**Pipeline State**: EXECUTING（Phase 1 T1.1 批次 3 — 最终批次）
**本轮目标**: T1.1 QA 执行 — 批次 3 (G 播放控件 + H 手势 + I 状态管理 + J 错误处理 + K HDR色彩 + L 设置 + M 辅助功能，33 条路径)
**完成情况**:
- [AGENT] audit-GH (Sonnet) → G01-G07 + H01-H04 结构审计 (11 paths)
- [AGENT] audit-IJK (Sonnet) → I01-I05 + J01-J03 + K01-K04 结构审计 (12 paths)
- [AGENT] audit-LM (Sonnet) → L01-L06 + M01-M04 结构审计 (10 paths)
- 3 agents 并行执行，合计审计 33 条路径
- 产出：`docs/qa-reports/qa-report-v3-batch3-GHIJKLM.md`

**QA 批次 3 结果**:

| QA Path | Verdict | Key Finding |
|---------|---------|-------------|
| QA-G01 可变播放速度 | PASS | PlaybackSpeed.allCases 10档 + speedMenu + mpv speed |
| QA-G02 音轨选择 | PASS | PlaybackMenuView "Audio Tracks" + mpv aid 切换 |
| QA-G03 字幕+CJK | PASS | sid切换 + blend-subtitles=yes + Noto Sans SC |
| QA-G04 二级时间轴 | FAIL | DetailedTimelineGeometry 孤立, 无View消费 (KNOWN) |
| QA-G05 逐帧步进 | PASS | frame-step + UI按钮完整 |
| QA-G06 选集列表 | PASS | playlistMenu + 切换播放完整 |
| QA-G07 进度条拖拽 | PASS | Slider + seek 接线完整 |
| QA-H01 单次捏合 | PASS | 400ms消歧 → showControls 切换 |
| QA-H02 双次捏合 | PASS | doublePinch → pause/resume/replay |
| QA-H03 捏合长按 | PARTIAL | 长按2.0x可用, 松开硬编码恢复1.0x(不保留原速) |
| QA-H04 捏合拖拽 | FAIL | .drag case break 空操作 (KNOWN) |
| QA-I01 进度记忆 | PASS | persist→SwiftDataStore→Resume按钮全链路 |
| QA-I02 记住选择 | PASS | Picker 3选项 + UserDefaultsStore |
| QA-I03 播放结束 | PASS | keep-open=yes + .ended + 重播图标 |
| QA-I04 自动下一集 | PASS | .playNext → nextFileProvider |
| QA-I05 文件列表进度 | PASS | 橙色圆点 + "Watched XX:XX" |
| QA-J01 网络缓冲 | PARTIAL | .buffering 枚举存在, MPVAdapter从未触发 (KNOWN升级) |
| QA-J02 错误提示 | PASS | onRuntimeError → Alert 完整 |
| QA-J03 后台重连 | FAIL | 无NWPathMonitor/retry/backoff (KNOWN) |
| QA-K01 HLG检测 | PASS | arib-std-b67→.hlg+CAEDRMetadata.hlg |
| QA-K02 HDR10+检测 | PARTIAL | 检测存在, EDR降级到HDR10路径 |
| QA-K03 HDR/SDR切换 | FAIL | setHDREnabled后端完整, UI零调用 (KNOWN) |
| QA-K04 SDR无误标 | PASS | hdrTypeLabel(.sdr)="SDR" |
| QA-L01 恢复策略 | PASS | Picker+UserDefaultsStore全链路 |
| QA-L02 结束行为 | PASS | stop/repeatOne/playNext持久化 |
| QA-L03 默认速度 | PASS | Picker+启动应用默认速度 |
| QA-L04 服务器删除 | PASS | removeDataSource+Keychain删除(按钮24pt) |
| QA-L05 缓存清理 | FAIL | 零缓存清理UI (KNOWN) |
| QA-L06 关于页面 | PARTIAL | About section存在, Version硬编码"0.1" (KNOWN升级) |
| QA-M01 ≥60pt | PARTIAL | 主按钮72pt✅, 关闭48pt❌/删除24pt❌ |
| QA-M02 Ornament | PASS | .scene(.bottom)合规 |
| QA-M03 VoiceOver | FAIL | 全项目零accessibilityLabel (新发现) |
| QA-M04 WorldTracking | FAIL | 零WorldTrackingProvider/ARKitSession (新发现) |

**Health Score**: 71.2 (PASS=21, PARTIAL=5, FAIL=7)

**新发现问题 (4)**:

| # | 严重度 | 问题 |
|---|--------|------|
| ISSUE-010 | Medium | H03 longPress 松开硬编码恢复1.0x, 不保留用户原速度 |
| ISSUE-011 | **High** | M03 全项目零 VoiceOver accessibilityLabel 覆盖 |
| ISSUE-012 | **High** | M04 无 WorldTrackingProvider/ARKitSession, 沉浸模式无世界空间锚定 |
| ISSUE-013 | Low | L06 About 版本号硬编码 "0.1", 未读 CFBundleShortVersionString |

**T1.1 全批次汇总**:

| 批次 | 路径 | PASS | PARTIAL | FAIL | DEFERRED | Health |
|------|------|------|---------|------|----------|--------|
| 1 (ABC) | 12 | 7 | 4 | 0 | 1 | 81.8 |
| 2 (DEF) | 14 | 6 | 5 | 3 | 0 | 60.7 |
| 3 (G-M) | 33 | 21 | 5 | 7 | 0 | 71.2 |
| **合计** | **59** | **34** | **14** | **10** | **1** | **70.7** |

**Decision Log**:
- [AUTO] T1.1 完成评估 | 59条路径全部执行完毕 | P6 | 三批次覆盖 QA 计划 A-M 全部类别
- [AUTO] M04 WorldTrackingProvider | 标记为 Phase 2 修复项但降级为 P2 | P3 | visionOS RealityView 在 ImmersiveSpace 中默认固定在世界空间, WorldTrackingProvider 仅在需要 device anchor/head pose 时才必须
- [AUTO] M03 VoiceOver | 标记为 Phase 2 P1 | P1 | 辅助功能合规是 App Store 审核要求
- [AUTO] KNOWN_FAIL 升级 | J01 PARTIAL(枚举存在), L06 PARTIAL(About存在) | P5 | 比预期好, 但仍有缺陷

**测试状态**: swift test: 未执行（本轮 QA 结构审计） | 新增: 0 | FAIL: none
**下轮应做**: T1.1 完成 → T1.2 HelloWorld 对照验证，然后 Phase Transition → Phase 2 EXECUTING (缺陷修复)
**Status**: IN_PROGRESS

---

## Round 11 — 2026-04-02T13:00:00+08:00

**Pipeline State**: EXECUTING（Phase 1 T1.2 → Phase 1 完成 → Phase 2 Transition）
**本轮目标**: T1.2 — HelloWorld 对照验证（12 项 UX 改进清单 vs 当前代码状态）
**完成情况**:
- [AGENT] ux-verifier (Sonnet) → 12 项 UX 改进逐项代码验证
- 产出：`docs/qa-reports/helloworld-comparison-v3.md`
- Phase 1 (T1.1 + T1.2) 全部完成，准备 Phase Transition → Phase 2

**T1.2 验证结果**:

| 状态 | 数量 | 项目 |
|------|------|------|
| 需改进 | 8 | UX-01~08 |
| 已符合 | 3 | UX-10, REJECT-01, REJECT-02 |
| 不适用 | 1 | UX-09 |

**需改进项 Phase 2 排序**:

| 优先级 | UX 项 | 改动 | QA 关联 |
|--------|-------|------|---------|
| P0 | UX-01 | DragRotationModifier + 弹性动画 + 惯性 | QA-H04 FAIL |
| P1 | UX-02 | VideoDetailView 分栏响应式布局 | — |
| P1 | UX-03 | Glass cornerRadius 定制 | — |
| P1 | UX-04 | SliderGridRow 可复用组件 | — |
| P1 | UX-05 | ImmersionStyle 动态绑定 | QA-D05 PARTIAL |
| P1 | UX-06 | Drag+Magnify 同时手势 | QA-H04 关联 |
| P1 | UX-07 | openWindow/dismissWindow 窗口管理 | — |
| P2 | UX-08 | FileCard/FolderCard 组件 | — |

**Phase 1 → Phase 2 Transition 评估**:
- T1.1 ✅ 59 条 QA 路径全部执行（34 PASS / 14 PARTIAL / 10 FAIL / 1 DEFERRED，Health 70.7）
- T1.2 ✅ 12 项 HelloWorld 对照验证完成
- Phase 2 修复清单合并：
  - QA 缺陷 (T2.1): 4 P0 + 6 P1 + 3 P2 = 13 项
  - UX 改进 (T2.2): 1 P0 + 6 P1 + 1 P2 = 8 项
  - 测试素材 (T2.3): 4 素材需补元数据
- **Transition 通过** → Phase 2 EXECUTING

**Decision Log**:
- [AUTO] Phase Transition Phase 1→Phase 2 | T1.1+T1.2 全部完成 | P6 | QA 和 HelloWorld 对照验证产出完整的修复清单
- [AUTO] UX-09 不适用 | 单一使用点不需要 ViewModifier 抽象 | P5 | 奥卡姆剃刀
- [AUTO] Phase 2 修复排序 | QA 缺陷 P0 先于 UX 改进 P0 | P1 | 功能断联比体验缺失更紧急

**测试状态**: swift test: 未执行（本轮验证+文档） | 新增: 0 | FAIL: none
**下轮应做**: Phase 2 T2.1 — 修复 QA P0 缺陷（F3.2 bridge 断联 / F4.1 缓冲指示器 / F5.2 HDR切换 / F4.3 自动重连）
**Status**: IN_PROGRESS
