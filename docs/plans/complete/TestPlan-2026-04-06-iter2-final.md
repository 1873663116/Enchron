---
title: "TestPlan: V2 Iteration 2 — Bug Fixes §5.4-§5.11"
type: test
status: active
date: 2026-04-06
origin: docs/plans/active/ExecPlan.md
---

# TestPlan: V2 Iteration 2 — Bug Fixes §5.4-§5.11

本 TestPlan 与 ExecPlan 的 8 个实施单元一一映射。每个 Unit 的测试项区分为：
- **A** = Agent 自动化可测（编译检查、结构守卫、单元测试、Simulator 截图对比）
- **H** = 需要 visionOS 真机验证（交互体验、帧率感知、沉浸空间行为）

---

## Unit 1: §5.4 — 播放中菜单闪烁与交互修复

| # | 测试项 | 类型 | 方法 | 通过标准 |
|---|--------|------|------|----------|
| 1.1 | 编译通过 | A | `xcodebuild build` | 零 error |
| 1.2 | 播放中打开 Menu → 二级菜单稳定可见 | H | 真机播放视频 → 点击 Menu 按钮 → 观察菜单 | 菜单持续显示，无闪烁 |
| 1.3 | 二级菜单项可点击 | H | 真机点击 Subtitles/Audio/Speed → 三级菜单展开 | 点击响应正常 |
| 1.4 | 三级菜单可滚动、可选择 | H | 真机滚动 Playback Speed 列表 → 选择 1.5x | 选中项生效，播放速度变化 |
| 1.5 | 播放中打开 Settings → Playback Mode 可切换 | H | 真机点击 Settings → Playback Mode | 各项可点击，受约束矩阵限制的项灰色禁用 |
| 1.6 | 快速连续开关菜单 5 次 | H | 真机快速操作 | 无闪烁、无状态错乱 |
| 1.7 | 菜单打开时等待 10 秒不被自动隐藏 | H | 真机打开菜单后静置 10 秒 | 菜单保持可见（控件自动隐藏不影响已弹出菜单） |
| 1.8 | 暂停后菜单行为一致 | H | 真机暂停 → 打开菜单 → 操作 | 与播放中行为一致 |

---

## Unit 2: §5.5 — HDR 视频详情页超时防卡死

| # | 测试项 | 类型 | 方法 | 通过标准 |
|---|--------|------|------|----------|
| 2.1 | 编译通过 | A | `xcodebuild build` | 零 error |
| 2.2 | 超时逻辑单元测试 | A | Mock mpv 检测永不返回 → 验证 3 秒后返回 fallback profile | preparePlayback 在 3 秒内完成 |
| 2.3 | SDR 视频详情页正常加载 | H | 真机打开 SDR 视频详情 | 元数据正确，无延迟 |
| 2.4 | HDR10 视频详情页正常加载 | H | 真机打开 HDR10 视频详情 | HDR 类型显示"HDR10" |
| 2.5 | Dolby Vision 视频详情页正常加载 | H | 真机打开 DV 视频详情 | HDR 类型显示"Dolby Vision" |
| 2.6 | 导致卡死的 HDR 视频（如有）→ 3 秒后可操作 | H | 真机打开之前导致卡死的视频 | 最多 3 秒后 UI 可交互，显示 fallback 元数据 |
| 2.7 | 快速连续打开/关闭不同视频详情 | H | 真机快速切换 | generation tracking 正确取消旧任务，无 crash |
| 2.8 | 超时后点击播放 → 播放正常启动 | H | 在 fallback 状态下点击 Play | 视频正常播放 |
| 2.9 | HLG 视频详情页正常加载 | H | 真机打开 HLG 视频详情 | HDR 类型显示"HLG"（对抗审查补充） |

---

## Unit 3: §5.6 — 文件夹级别元数据预读 + 缓存

| # | 测试项 | 类型 | 方法 | 通过标准 |
|---|--------|------|------|----------|
| 3.1 | 编译通过 | A | `xcodebuild build` | 零 error |
| 3.2 | 预读服务单元测试 — 缓存命中 | A | 注入已缓存 metadata → 调用 prepareMetadata → 验证不触发 mpv 检测 | 直接返回缓存值 |
| 3.3 | 预读服务单元测试 — 缓存失效 | A | 修改 modifiedAt → 验证重新检测 | 触发新检测 |
| 3.4 | 预读并发限制测试 | A | 50 文件预读 → 验证同时进行数 ≤ 3 | TaskGroup 并发控制正确 |
| 3.5 | 进入文件夹 → 后台预读 → 打开详情页元数据正确 | H | 真机进入含 5+ 视频的文件夹 → 等待 5 秒 → 打开详情 | 首次显示即为正确元数据 |
| 3.6 | 未预读完成时打开详情页 | H | 真机进入文件夹 → 立即打开详情 | 先显示 loading，检测完成后更新为正确值 |
| 3.7 | 大量文件预读不阻塞 UI | H | 真机进入含 50+ 文件的文件夹 → 滚动列表 | 滚动流畅，预读在后台进行 |
| 3.8 | 快速切换文件夹取消旧预读 | H | 真机快速切换 3 个文件夹 → 无 crash | 旧 Task 被正确取消 |
| 3.9 | **[ENG-REVIEW]** App 进入后台时预读正在进行 | H | 真机预读中按 Digital Crown → 回到 App | 预读 Task 取消，回来后不崩溃 |
| 3.10 | 单文件预读超时 → 跳过继续 | A | Mock 单文件 mpv 永不返回 + 多文件队列 → 验证其余文件完成 | 超时文件跳过，队列继续（对抗审查补充） |

---

## Unit 4: §5.9 — 沉浸空间四项子问题修复

| # | 测试项 | 类型 | 方法 | 通过标准 |
|---|--------|------|------|----------|
| 4.1 | 编译通过 | A | `xcodebuild build` | 零 error |
| 4.2 | 结构守卫：所有 openImmersiveSpace 调用走统一路径 | A | grep 所有 `openImmersiveSpace` 调用点 → 验证仅在统一入口方法中存在 | 非统一入口不直接调用 openImmersiveSpace |
| 4.3 | §5.9a 详情页 → 沉浸播放 → 走 PlaybackLaunchCoordinator | H | 真机从详情页选"沉浸模式"播放 | 经过 coordinator，行为与控件切换一致 |
| 4.4 | §5.9a 控件 → 切换 Immersive → 走 PlaybackLaunchCoordinator | H | 真机播放中从 Settings → Playback Mode → Immersive | 经过 coordinator |
| 4.5 | §5.9b 进入 Immersive 后主窗口不可见 | H | 真机进入 Immersive 模式 → 环顾四周 | APP 主窗口不可见 |
| 4.6 | §5.9b 退出 Immersive 后主窗口恢复 | H | 真机从 Immersive 切回 Window → 主窗口 | 主窗口正常恢复可见 |
| 4.7 | §5.9c 沉浸空间为独占模式 | H | 真机进入沉浸空间 → 查看其他应用是否可见 | 其他应用不可见（.full immersion） |
| 4.8 | §5.9d 点击视频纹理 toggle 控件 | H | 真机在沉浸空间中点击虚拟屏幕 | 播放控件窗口出现/隐藏 |
| 4.9 | §5.9d 控件窗口可拖动 | H | 真机在沉浸空间中拖动控件窗口 | 窗口随手势移动 |
| 4.10 | openImmersiveSpace 失败回退 | H | 模拟失败（如可能）或检查代码回退逻辑 | 回退到 Window 模式 |
| 4.11 | **[ENG-REVIEW]** 快速 Window/Immersive/Panorama 连续切换 3 次 | H | 真机快速来回切换 | 状态机收敛到最终选择，无残留窗口、无 crash |
| 4.12 | **[ENG-REVIEW]** SceneSelectorView 选择环境 → 沉浸空间正确打开 | H | 真机在 SceneSelector 中选择不同环境 | 重构后行为与之前一致，走统一路径 |
| 4.13 | 暂停态点击纹理可召唤控件 | H | 真机在沉浸空间暂停 → 点击视频纹理 | 控件窗口出现（对抗审查补充） |

---

## Unit 5: §5.10 — 播放控件严格对齐 player.html

| # | 测试项 | 类型 | 方法 | 通过标准 |
|---|--------|------|------|----------|
| 5.1 | 编译通过 | A | `xcodebuild build` | 零 error |
| 5.2 | Simulator 截图 — 控制栏 pill 按钮数量和顺序 | A | XcodeBuildMCP screenshot → 对比 player.html | Menu → Rew → Play → Fwd → NLE → Settings，共 6 个 |
| 5.3 | Simulator 截图 — 进度条布局 | A | 截图对比 | 左侧当前时间、右侧剩余时间、中间滑块 |
| 5.4 | 顶栏布局 — 返回按钮 + 标题 + 技术标签 | H | 真机验证 | 逐元素与 player.html 一致 |
| 5.5 | Menu 面板展开方向和对齐 | H | 真机点击 Menu → 观察面板 | 向上展开，右边缘对齐 Menu 按钮 |
| 5.6 | Menu 面板内容：HDR → Subtitles → Audio → Speed | H | 真机逐项检查 | 项目顺序与 player.html 一致 |
| 5.7 | Settings 面板展开方向和对齐 | H | 真机点击 Settings → 观察面板 | 向上展开，左边缘对齐 Settings 按钮 |
| 5.8 | Settings 面板内容：Playback Mode → Environment | H | 真机逐项检查 | 项目顺序一致 |
| 5.9 | HDR 内容 → Menu 显示 HDR toggle + format label | H | 真机播放 HDR 内容 → 打开 Menu | 显示"Dolby Vision"/"HDR10"/"HLG" + ON/OFF |
| 5.10 | SDR 内容 → Menu 无 HDR toggle 项 | H | 真机播放 SDR 内容 → 打开 Menu | 无 HDR 相关项 |
| 5.11 | mono 内容 → 3D 整项灰色禁用 | H | 真机播放 mono 视频 → Settings → 3D | 3D 选项灰色不可选 |
| 5.12 | 控制栏 pill 间距和尺寸与 HTML 一致 | H | 真机截图对比 | 视觉匹配 |
| 5.13 | SBS 内容 → 3D 默认选中 Side-by-Side，可切 Off | H | 真机播放 SBS 视频 → Settings → 3D | 默认 SBS 选中，Off 可切换（对抗审查补充） |
| 5.14 | TB 内容 → 3D 默认选中 Top-Bottom，可切 Off | H | 真机播放 TB 视频 → Settings → 3D | 默认 TB 选中，Off 可切换（对抗审查补充） |

---

## Unit 6: §5.7 — 文件浏览性能与交互修复

| # | 测试项 | 类型 | 方法 | 通过标准 |
|---|--------|------|------|----------|
| 6.1 | 编译通过 | A | `xcodebuild build` | 零 error |
| 6.2 | Simulator 截图 — skeleton shimmer 可见 | A | 切换到远端数据源 → 截图 | skeleton cards 可见，shimmer 动画状态正确 |
| 6.3 | §5.7a 本地文件夹 50+ 文件滚动 | H | 真机滚动含大量文件的列表 | 无明显卡顿（目标 60fps） |
| 6.4 | §5.7b 切换到 WebDAV → skeleton 动画持续播放 | H | 真机切换远端数据源 → 观察动画 | shimmer 动画持续至数据加载完成 |
| 6.5 | §5.7b 切换到 SMB → skeleton 动画持续播放 | H | 真机切换 SMB → 观察动画 | 同上 |
| 6.6 | §5.7c 下拉刷新保持列表稳定 | H | 真机下拉刷新 → 观察列表 | 当前列表不跳变，增量更新 |
| 6.7 | §5.7c 刷新完成反馈 | H | 真机下拉刷新 → 等待完成 | 有明确的成功/失败视觉反馈 |
| 6.8 | 远端连接缓慢（>5s）时动画不中断 | H | 低速网络环境测试 | 动画持续播放 |
| 6.9 | 刷新失败时列表不变 | H | 真机断网 → 下拉刷新 → 观察列表 | 当前列表保持不变 + 显示失败反馈（对抗审查补充） |

---

## Unit 7: §5.11 — NLE 二级时间轴关闭动效修复

| # | 测试项 | 类型 | 方法 | 通过标准 |
|---|--------|------|------|----------|
| 7.1 | 编译通过 | A | `xcodebuild build` | 零 error |
| 7.2 | 代码结构检查 — transition 方向 | A | grep `NLETimelineView.swift` 中 `.move(edge:` → 确认为 `.bottom` | `.transition(*.move(edge: .bottom))` |
| 7.3 | 展开动效 — 从底部滑出 | H | 真机点击 NLE toggle → 观察 | 面板从底部滑出 |
| 7.4 | 关闭动效 — 向底部滑入 | H | 真机再次点击 NLE toggle → 观察 | 面板向底部滑入，与打开对称 |
| 7.5 | 快速连续 toggle | H | 真机快速点击 5 次 | 动画不中断、不跳帧 |
| 7.6 | reduceMotion 开启时行为 | H | 真机开启辅助功能 → toggle | 直接切换无动画 |

---

## Unit 8: §5.8 — 视频画布跟随窗口缩放

| # | 测试项 | 类型 | 方法 | 通过标准 |
|---|--------|------|------|----------|
| 8.1 | 编译通过 | A | `xcodebuild build` | 零 error |
| 8.2 | 代码结构检查 — containerSize 传递 | A | 验证 `updateUIView` 中根据 `containerSize` 更新 frame | containerSize 变化触发 layout 更新 |
| 8.3 | 放大窗口 → 画布同步放大 | H | 真机注视窗口边缘拖动放大 | 视频画布充满窗口，无黑边 |
| 8.4 | 缩小窗口 → 画布同步缩小 | H | 真机拖动缩小 | 视频画布缩小，无固定尺寸残留 |
| 8.5 | 快速连续 resize | H | 真机快速拖动 | 画布跟随，无撕裂或黑边闪烁 |
| 8.6 | resize 后切换视频 | H | 真机 resize → 切换视频 | 新视频以当前窗口尺寸渲染 |

---

## 汇总统计

| 类别 | 计数 |
|------|------|
| 总测试项 | 65 |
| Agent 自动化可测 (A) | 17 |
| 真机验证 (H) | 48 |
| P0 相关测试项 | 45 |
| P1 相关测试项 | 14 |
| P2 相关测试项 | 6 |

---

## 执行顺序建议

1. **每个 Unit 完成后**：先跑 A 类测试（编译 + 结构守卫 + 单元测试）
2. **全部 P0 Unit 完成后**：集中真机验证 H 类 P0 测试项
3. **P1/P2 Unit 完成后**：补充真机验证
4. **最终**：全量回归（参照 REGRESSION.md）

## 回归集关注

本轮修复涉及的模块和代码路径，需在完成后核对 `REGRESSION.md` 并新增以下回归项：
- 播放中菜单交互稳定性
- HDR 视频详情页加载
- 元数据预读缓存一致性
- 沉浸空间入口统一性
- 沉浸/窗口切换的窗口可见性状态
- NLE 时间轴开关动效
- 视频画布 resize 同步
