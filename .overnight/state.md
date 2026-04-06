next: test
status: IN_PROGRESS
iteration: 1
consecutive_failures: 0
goal: "Enchron V2 综合迭代：三轴域模型重构 + UI 严格对齐 HTML 设计稿 + 视频格式自动识别 + 缩略图加载 + 播放场景切换 + Bug 修复 + QA/E2E 验收"
round: 3
context: |
  execute + review 阶段完成。ExecPlan 8/9 个实施 Unit 全部 PASS（Unit 9 QA/E2E 留给 test 阶段）。
  
  实施摘要：
  - Unit 1: SeekBarView 属性隔离修复 P0 菜单闪烁 + playbackState 等值 guard
  - Unit 2: ProjectionType 4-case 纯几何枚举 + StereoMode→StereoLayout 重命名（含 .mono）+ MediaProfile 新增 stereoLayout/hasCoverArt
  - Unit 3: ProjectionDetection 返回 (ProjectionType, StereoLayout) 元组 + 精确 mpv stereo-in 匹配 + gamma-based HDR 决策树（删除 video-params/hdr-format 死代码）
  - Unit 4: DecidePlaybackModeUseCase 三轴路由 + 约束矩阵（flat 禁 panorama，fisheye 强制 mono）+ 26 个路由测试
  - Unit 5: PlayerControlsView HDR 动态标签 + 3D 开关 + Playback Mode disabled 项 + 移除 Projection Override/Playlist/Screen Position 入口
  - Unit 6: VideoDetailView 返回按钮 + HDR 开关 + 沉浸模式选择器
  - Unit 7: ThumbnailService actor + ThumbnailMPVAdapter (screenshot-to-file) + ThumbnailCache 两级缓存 + VideoCardView/VideoDetailView 接入
  - Unit 8: connectToDataSource 立即清空 + SkeletonCardView shimmer 加载态
  
  对抗性审查发现 1 P0 + 2 P1，全部已修复：
  - P0-1: detectedStereoLayout 传播断裂 → updateDetectedProjection 新增 stereoLayout 参数 + PlaybackLaunchCoordinator 4 处调用同步更新
  - P1-1: NLETimelineView playbackPosition 读取泄漏 → NLETimelineView 改为 @Environment 自读
  - P1-2: startPlayback() 未重置检测状态 → 新增 detectedProjectionType/detectedStereoLayout 重置
  P2-1: REGRESSION.md StereoMode.swift 引用 → 已更新为 StereoLayout.swift
  
  ce-review 最终完成：0 P0 / 0 P1 / 4 P2 / 3 P3，确认修复后无阻塞。
  ce-review 新增 P2 发现：
  - P2-ce1: ThumbnailMPVAdapter.extractFrame() seek 前未重置 renderUpdateAvailable（可能捕获旧帧）
  - P2-ce3: EDRMetadataDescriptor WORKAROUND 注释用英文，CI check-workaround.sh 检查中文"移除条件"关键词，可能导致 CI 失败
  - P3-ce1: hdrToggleLabel .hdr10Plus 映射为 "HDR10" 而非 "HDR10+"
  - P3-ce2: hasCoverArt 字段永远为 false（ThumbnailMPVAdapter 独立检测封面，不影响功能）
  
  next=test 原因：8 个 Unit 全部实施完成，两轮审查 P0/P1 已修复，进入 QA/E2E 验收。
  
  test 阶段注意事项：
  - 执行 /qa Standard + /e2e（TestPlan 在 docs/plans/active/TestPlan.md）
  - 验证三轴路由约束矩阵（12 种组合）
  - 验证 P0 菜单交互回归
  - 验证 ThumbnailService 缩略图加载
  - 验证数据源切换骨架屏
  - 补 accessibilityIdentifier（ExecPlan Unit 9）
  - 更新 REGRESSION.md 新增回归项
  - P2-2/P2-3/P2-4（ThumbnailMPVAdapter 线程安全）可在 test 后的 fix 阶段处理
