# 收敛 FolderList 元数据格式化逻辑

本 ExecPlan 是活文档。Progress、Surprises & Discoveries、Decision Log、
Outcomes & Retrospective 四个章节必须在工作进行中保持更新。

本文档须遵循 PLANS.md（仓库根目录）的全部要求进行维护。

## Purpose / Big Picture

这次清理不改文件浏览功能，只把 `FolderListView` 中直接拼接文件大小和修改时间的逻辑从 SwiftUI 视图里移出去。完成后，文件列表仍显示相同的元数据文案，但格式规则会收敛到 `FileBrowsing` 自己的 formatter，后续如果要统一文件列表展示规则，只需要改一个地方并用测试兜住。

## Progress

- [x] (2026-03-19 01:01) 读取 `AGENTS.md`、`ARCHITECTURE.md`、`REGRESSION.md`、`PLANS.md`、`TESTING.md`、`product_philosophy.md`、`quality_gates.md` 和 `known_issues.md`，确认 cleaner 必须在隔离分支上施工。
- [x] (2026-03-19 01:10) 恢复自动化记忆，排除已在 PR #7 和 PR #8 处理过的清理主题，锁定新主题为 `FolderListView` 元数据格式化收口。
- [x] (2026-03-19 01:14) 抽出 `FileBrowsing` formatter，替换 `FolderListView` 内联格式化，并补 `FolderListMetadataFormatterTests`。
- [x] (2026-03-19 01:19) 完成仓库要求的验证：`swift build` 通过，`swift test` 186 通过 / 1 跳过，`swiftlint lint` 无 error 级别违规，`scripts/check-workaround.sh XrPlayer/` 通过。
- [x] (2026-03-22 01:00) 将 `automation/clearer-folder-list-metadata-format` rebase 到最新 `origin/main`，并把冲突的 exec plan 编号顺延为 `EP-005`，避免覆盖已合并的排序清理计划。
- [x] (2026-03-22 01:06) 根据 PR #9 的剩余 review finding 调整 formatter 缓存 key：文件大小 formatter 改为随 locale key 重建，日期 formatter 额外随时间制式签名重建，并补针对缓存复用/失效的测试。
- [x] (2026-03-22 01:07) 补 `REG-024` 回归项，覆盖系统语言/地区、24 小时制或时区变化后文件列表副标题刷新。
- [ ] (2026-03-22 01:07) 提交、推送、创建中文 PR，并评论 `@CodeX Review`。

## Surprises & Discoveries

- Observation: `Package.swift` 仍使用显式 `sources` 列表管理 `XrPlayerCore` 测试目标可见文件。
  Evidence: `Package.swift` 里 `XrPlayerCore` target 逐条枚举了 `PlayerUI/UseCases/PlaybackTimeFormatter.swift` 等文件路径。

- Observation: 第二轮 review 指出的真实风险，是 thread-local cache 生命周期长于系统格式偏好，而不是 formatter 抽象本身。
  Evidence: PR #9 的 review comment 明确指出语言/地区、24 小时制变化后会继续渲染旧格式。

## Decision Log

- Decision: 这次只处理 `FolderListView` 的文件大小和修改时间格式化，不顺手抽离文件图标映射或列表布局常量。
  Rationale: cleaner 需要保持单主题、可审查、行为不变；图标映射和布局属于另一类视图结构问题，会把 diff 扩大成第二主题。
  Date: 2026-03-19

- Decision: 新 formatter 放在 `XrPlayer/FileBrowsing/UseCases/`，不放到 `Shared/`。
  Rationale: `ARCHITECTURE.md` 明确要求有业务归属的逻辑不要沉到 `Shared`；文件列表元数据文案只服务 `FileBrowsing`。
  Date: 2026-03-19

- Decision: 保留 thread-local cache，但让 cache key 显式绑定 locale identifier 与时间制式签名，而不是回退到“每次调用都新建 formatter”。
  Rationale: 这样既保留了避免行级热路径重复分配的收益，也让系统格式变化时可以自然 miss cache 并重建 formatter。
  Date: 2026-03-22

## Outcomes & Retrospective

当前实现、返工验证和回归集更新都已完成。剩余动作只剩提交、推送、创建 PR 和触发云端审查；没有新的实现缺口。

## Context and Orientation

当前重复与耦合点位于 `XrPlayer/FileBrowsing/Views/FolderListView.swift`。这个视图内部持有一个 `ByteCountFormatter` 和一个 `DateFormatter`，并直接把 `MediaFile.sizeInBytes` 与 `MediaFile.modifiedAt` 拼成 `"大小 • 时间"` 文案。这样做的问题不是功能错误，而是展示规则被埋在具体视图里，未来一旦文件列表、搜索结果列表或其它浏览视图也要显示相同元数据，就容易复制这段格式化逻辑并再次漂移。

本轮不会改 `FileBrowsing` 的 domain 实体，不会改 `PlaybackCore`，也不会调整任何跨模块 protocol。它只会在 `FileBrowsing` 上下文内新增一个 formatter，把格式化规则收口，再让 `FolderListView` 调用它，并补纯逻辑测试证明输出仍稳定。

## Plan of Work

先在 `XrPlayer/FileBrowsing/UseCases/` 新增 `FolderListMetadataFormatter.swift`，提供独立的文件大小、修改时间和组合 subtitle 格式化方法。然后修改 `FolderListView.swift`，删除视图私有 formatter 属性，改为在 cell 文案处调用共享 formatter。接着修改 `Package.swift` 让测试目标能看到新文件，并在 `Tests/XrPlayerCoreTests/` 新增 formatter 测试，覆盖“字节数转人类可读文案”“时区影响修改时间输出”“组合文案包含两个片段”三个场景。如果云端 review 再指出缓存策略问题，则优先在同一 formatter 内调整 cache key，而不是把格式化逻辑重新塞回 `FolderListView`。

## Milestones

### M1: 提取 FolderList 元数据 formatter

完成后，文件列表的每个视频条目仍然显示与现在一致的大小和修改时间，但 `FolderListView` 不再持有底层格式化器实例。证明方式是运行编译与测试，并检查 diff 仅涉及 formatter、调用方、计划文档和测试。

#### 验证（双轨）

Agent 自检：
- `swift build` — 预期无 error
- `swift test` — 预期全部通过，且新增 formatter 测试通过
- `swiftlint lint` — 预期无 error 级别违规
- `scripts/check-workaround.sh XrPlayer/` — 预期通过

人类真机验证：
- 打开任意本地或远程目录，观察文件列表中每个视频条目的“大小 • 修改时间”副标题，预期仍正常显示，无空白、无错位、无截断异常。
- 在目录中切换不同大小和不同修改时间的文件，预期副标题仍随文件变化正确更新。

## Concrete Steps

工作目录：`/Users/xiongzhipeng/.codex/worktrees/clearer-folder-list-metadata-format`

1. 新增 `XrPlayer/FileBrowsing/UseCases/FolderListMetadataFormatter.swift`。
2. 修改 `XrPlayer/FileBrowsing/Views/FolderListView.swift`，移除视图私有 formatter 属性并改用共享 formatter。
3. 修改 `Package.swift`，把新 formatter 文件加入 `XrPlayerCore` target 的 `sources` 列表。
4. 新增 `Tests/XrPlayerCoreTests/FolderListMetadataFormatterTests.swift`。
5. 运行 `swift build`、`swift test`、`swiftlint lint`、`scripts/check-workaround.sh XrPlayer/`。

## Validation and Acceptance

验收标准是：文件列表中显示给用户看的大小和修改时间文案在行为上保持不变，但实现从 `FolderListView` 内嵌 formatter 收敛为 `FileBrowsing` 自己的共享 formatter；并且 `swift test` 中新增的 formatter 测试可以单独证明关键格式规则。

## Idempotence and Recovery

本计划中的编辑都是增量修改，可重复执行。若共享 formatter 导致某个视图编译失败，可以只回退 `FolderListView` 的调用点，而不会触碰数据模型、持久化或远程协议逻辑。

## Artifacts and Notes

关键验证记录：

    swift build
    Build complete! (12.86s)

    swift test
    Executed 186 tests, with 1 test skipped and 0 failures

    swiftlint lint
    Done linting! Found 49 violations, 0 serious in 83 files.

    scripts/check-workaround.sh XrPlayer/
    ✅ 所有 WORKAROUND 注释均包含移除条件说明

## Interfaces and Dependencies

不会新增或修改跨模块 protocol。新增的稳定接口仅限 `XrPlayer/FileBrowsing/UseCases/FolderListMetadataFormatter.swift` 中的静态 formatter 方法，供 `FolderListView` 调用。测试依赖仍保留在 `XrPlayerCore` target 内，不引入新的外部库。

Updated on 2026-03-22。已完成返工实现、验证与回归集更新，待提交并创建 PR。
