# Enchron 质量评分

更新时间：2026-03-26


## 评分标准

| 分数 | 含义 |
|------|------|
| 0 | 完全缺失或不可用 |
| 1 | 存在但有严重问题 |
| 2 | 可用但有明显缺陷 |
| 3 | 可用，已知问题已记录 |
| 4 | 良好，测试覆盖充分 |
| 5 | 优秀，无已知问题 |


## 领域评分

| 领域 | 评分 | 门禁依据 | 主要差距 |
|------|------|---------|---------|
| 统一时间轴 | 3 | G2 | 几何计算有测试覆盖；精确时间标签+逐帧步进已实现；真机体验需验证 |
| 播放控件反馈 | 3 | G3 | 窗口模式下控件可用，hover/focus 反馈存在；沉浸场景未实现 |
| 冷启动性能 | 2 | G4/G5 | KI-007: 首次构建后首启首播一次性冷卡顿（GPU 管线建链成本）；"i"面板卡顿已修复 |
| HDR 可信度 | 3 | G7/G8/G9 | KI-010 已修复：CAEDRMetadata 根据 HDR 类型自动设置（HDR10/DoVI→hdr10 metadata, HLG→hlg, SDR→nil）；setHDREnabled 同步 edrMetadata；EDR metadata 选择逻辑有数据驱动单元测试覆盖；需真机验证视觉效果 |
| 远程浏览(SMB) | 3 | G13 | KI-011 已修复；连接、枚举、子目录浏览和播放均正常 |
| 远程浏览(WebDAV) | 3 | G13 | 基本可用，连接稳定 |
| 沉浸场景 | 2 | G10/G11 | ImmersiveSpace 可打开/关闭；PanoramaLayerBridge Blit 管线已连通；球体渲染可工作；播放模式切换菜单已实现；app 退出时全景未清理的 bug 已修复 |
| 全景模式 | 3 | G10 | PanoramaSphereEntity + LowLevelTexture 管线已连通真机验证；投影类型自动检测已实现（stereo3d + GSpherical 元数据）；有数据驱动单元测试覆盖；需真机验证自动进入全景模式 |
| 模块边界 | 4 | G12/G17 | SwiftLint 自动守卫运行中；Domain 层 import 限制有效 |
| 前后端契约 | 3 | G13 | OpenAPI spec + mock 数据已就位；validate-contract.sh 可用 |
| 测试覆盖 | 3 | G14 | 205 个单元测试覆盖：DetailedTimelineGeometry、EDR metadata 选择、投影类型检测、FileFilter 边界、SortCriteria 排序、PlaybackMode 决策、GestureDisambiguator 状态机、MPV 配置安全 |
| 播放进度恢复 | 3 | — | RES-003 修复后 SwiftDataStore 可用；真机验证通过 |
| 凭证管理 | 3 | — | RES-005 修复后凭证 key 稳定；KeychainStore 可用 |


## 更新规则

- 每次 Exec Plan 完成时，更新相关领域评分
- 每次 known_issues.md 变更时，检查是否影响评分
- agent 不可自行提升评分超过 3 分（>=4 需要人类真机确认后才能标注）
- 评分降低不受限制——如果发现退化，立即降分并记录原因
