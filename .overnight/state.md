next: plan
status: IN_PROGRESS
iteration: 1
consecutive_failures: 0
goal: "Enchron V2 综合迭代：三轴域模型重构 + UI 严格对齐 HTML 设计稿 + 视频格式自动识别 + 缩略图加载 + 播放场景切换 + Bug 修复 + QA/E2E 验收"
round: 1
context: |
  investigate 阶段完成。三个并行 Agent 产出三份调研报告（全 PASS）：
  
  1. docs/reference/2026-04-06-mpv-metadata-investigation.md
     - mpv stereo-in 完整值表确认（sbs2l/sbs2r/ab2l/ab2r/mono 等短名称）
     - 现有 ProjectionDetection.swift 中存在死代码匹配（side_by_side_left 等）
     - video-params/hdr-format 不存在，HDR 检测须用 gamma（pq=HDR10, hlg=HLG）
     - GSpherical metadata 在 mpv 中不可用（mpv 不读 FFmpeg AV_PKT_DATA_SPHERICAL）
     - MP4/MOV 球面投影检测有架构空缺——需 AVFoundation 预扫描或读 FFmpeg side data
     - Apple MV-HEVC 必须走 AVFoundation
  
  2. docs/reference/2026-04-06-thumbnail-extraction-investigation.md
     - mpv 是唯一通用路径（track-list/N/image 检测封面，screenshot-to-file 帧提取）
     - 独立 mpv 实例架构，不共享主播放实例
     - 两级缓存：NSCache + 磁盘 JPEG（Library/Caches/thumbnails/）
     - AVFoundation 仅覆盖 MP4/MOV，不支持 MKV/WebM/SMB
  
  3. docs/reference/2026-04-06-combination-matrix-investigation.md
     - 36 种组合中 3 种非法（flat+panorama），33 种可行
     - 现有渲染管线已支持核心路径，主要缺口在数据模型层
     - DecidePlaybackModeUseCase 不感知 StereoLayout，flat+stereo 路由错误
     - fisheye+stereo 极罕见，初期降格为 mono
  
  next=plan 原因：调查目标全部有明确结论，信息充分可进入规划。
  plan 阶段需基于这三份报告 + 需求文档制定 ExecPlan + TestPlan。
  注意：has_frontend=true，config 未 skip design-shotgun，plan 阶段应包含设计探索。
  skip_skills: [plan-ceo-review]（已确认）。
