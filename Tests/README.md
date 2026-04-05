# XrPlayer 测试目录

推荐先看：
- [`TESTING.md`](../TESTING.md) — 双轨验证体系
- [`docs/quality_gates.md`](../docs/quality_gates.md) — 质量门禁

## 运行方式

```bash
swift test
```

## 当前测试文件

| 文件 | 覆盖范围 |
|------|---------|
| `CoreLogicTests.swift` | FileFilter、LocalDataSourceAdapter、ProjectionType 分类、PlaybackSpeed/Position 边界 |
| `DetailedTimelineGeometryTests.swift` | 二级进度条几何计算（数据驱动，覆盖充分） |
| `V02Tests.swift` | Domain 值对象（MediaProfile、PlaybackSpeed、PlaybackPosition、AudioTrack/SubtitleTrack）、DisambiguateGestureUseCase 状态机 |
| `V03Tests.swift` | 远程浏览适配器（SMB/WebDAV）、KeychainStore、CredentialSourceID、DataSource/ConnectionInfo Codable |
| `V04Tests.swift` | MPVConfiguration 选项生成、PlaybackControlling Mock 流程、HDR 配置安全、VideoToolboxBridge |
| `PlaybackTimeFormatterTests.swift` | 时间标签格式化器 |

## 自动化测试不覆盖的领域

以下必须通过真机验证（见 REGRESSION.md）：

- 真机 UI / UX 体验与流畅度
- 沉浸空间真实表现
- HDR 视觉正确性（CAEDRMetadata 效果需要 HDR 显示器或 AVP）
- 全景渲染球面映射正确性

## 维护原则

新增修复时，优先补：
1. 回归测试（纯逻辑可自动化的部分）
2. REGRESSION.md 对应回归项
3. 人类真机验证清单
