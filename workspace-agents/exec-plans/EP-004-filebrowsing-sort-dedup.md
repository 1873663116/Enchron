# 收敛 FileBrowsing 排序逻辑重复实现

本 ExecPlan 是活文档。Progress、Surprises & Discoveries、Decision Log、
Outcomes & Retrospective 四个章节必须在工作进行中保持更新。

本文档须遵循 PLANS.md（仓库根目录）的全部要求进行维护。

## Purpose / Big Picture

这次清理不改变任何文件浏览行为，只把 `FileBrowsing` 三个数据源适配器里重复的媒体文件排序逻辑收敛到一个共享入口。完成后，本地、SMB、WebDAV 仍会按原来的名称、时间、大小规则排序，但排序规则只保留一份，后续调整时不会再出现三个适配器各改各的漂移风险。

## Progress

- [x] (2026-03-21 10:17) 读取 `AGENTS.md`、`ARCHITECTURE.md`、`REGRESSION.md`、`TESTING.md`、`quality_gates.md`、`PLANS.md` 和 `cleaner` 技能，确认必须在隔离 worktree 上执行单主题清理。
- [x] (2026-03-21 10:25) 锁定清理主题为 `FileBrowsing` 适配器排序逻辑去重，范围限定在同一限界上下文内，不改跨模块接口。
- [x] (2026-03-21 10:31) 将排序规则收敛到共享入口，替换本地 / SMB / WebDAV 适配器内的重复实现，并补充 `SortCriteriaTests` 纯逻辑测试。
- [x] (2026-03-21 10:35) 完成仓库要求的验证：`swift build`、`swift test`、`swiftlint lint`、`scripts/check-workaround.sh XrPlayer/`。
- [ ] (2026-03-21 10:26) 提交、推送并创建或更新 PR，随后触发 `@CodeX Review`。

## Surprises & Discoveries

- Observation: 三个 `FileBrowsing` 适配器目前维护的是同一份排序规则，只是分散在各自私有函数里。
  Evidence: `LocalDataSourceAdapter.swift`、`SMBDataSourceAdapter.swift`、`WebDAVDataSourceAdapter.swift` 中都存在同构的 `sort(files:by:)` 实现。

## Decision Log

- Decision: 共享排序入口放在 `XrPlayer/FileBrowsing/Domain/ValueObjects/SortCriteria.swift`。
  Rationale: 排序规则由 `SortCriteria` 定义和驱动，属于 `FileBrowsing` 领域值对象本身，不应继续散落在各 adapter 私有实现里，也不需要提升到 `Shared`。
  Date: 2026-03-21

- Decision: 本轮只收敛排序逻辑并补纯逻辑测试，不顺手改文件夹排序、错误提示文案或其他重复点。
  Rationale: `cleaner` 要求单主题、小范围、可审查；扩大范围会混入新的产品或交互判断。
  Date: 2026-03-21

## Outcomes & Retrospective

当前核心目标已经达成：`FileBrowsing` 三个 adapter 不再各自维护排序规则，名称 / 修改时间 / 文件大小排序统一收敛到 `SortCriteria`，并由纯逻辑测试覆盖。剩余动作只剩提交、推送和发布 PR；没有新的实现缺口。

## Context and Orientation

当前重复点位于 `XrPlayer/FileBrowsing/Adapters/Local/LocalDataSourceAdapter.swift`、`XrPlayer/FileBrowsing/Adapters/SMB/SMBDataSourceAdapter.swift` 和 `XrPlayer/FileBrowsing/Adapters/WebDAV/WebDAVDataSourceAdapter.swift`。这三个适配器都会把 `FileBrowsingDomain.MediaFile` 按 `SortCriteria` 排序，但它们各自维护同样的 `switch` 逻辑：名称按不区分大小写排序，修改时间按时间先后排序，大小按字节数排序，再根据升序/降序决定是否反转结果。

本轮不会修改 `FileBrowsing` 的对外 protocol、不会改变 `MediaFile` 结构，也不会触碰 `App`、`Persistence`、`PlaybackCore` 或 UI 层。它只会让 `SortCriteria` 持有自己的排序实现，再让三个适配器统一调用这一入口，并补一组纯逻辑测试证明名称、时间、大小、排序方向都保持稳定。

## Plan of Work

先修改 `XrPlayer/FileBrowsing/Domain/ValueObjects/SortCriteria.swift`，给 `SortCriteria` 增加一个针对 `[FileBrowsingDomain.MediaFile]` 的排序入口。然后删除 `LocalDataSourceAdapter.swift`、`SMBDataSourceAdapter.swift`、`WebDAVDataSourceAdapter.swift` 里的私有重复排序函数，把调用点改为使用新的共享入口。最后在 `Tests/XrPlayerCoreTests/` 增加或更新纯逻辑测试，覆盖名称、时间、大小和升降序组合，确保行为不漂移。

## Milestones

### M1: 提取 FileBrowsing 共享排序规则

完成后，三个数据源适配器不再各自维护媒体文件排序逻辑，而是共用 `SortCriteria` 中的一份实现。用户在本地、SMB、WebDAV 列表中看到的排序结果应保持不变。证明方式是运行编译和单元测试，并检查 diff 只围绕 `FileBrowsing` 排序逻辑和对应测试。

#### 验证（双轨）

Agent 自检：
- `swift build` — 预期无 error
- `swift test` — 预期全部通过，且新增排序测试通过
- `swiftlint lint` — 预期无 error 级别违规
- `scripts/check-workaround.sh XrPlayer/` — 预期通过

人类真机验证：
- 打开本地文件浏览器，分别按名称、修改时间、文件大小切换排序，预期列表顺序与当前语义一致。
- 连接 SMB 数据源并进入任意含多个视频的目录，切换排序方式，预期顺序正确且无崩溃。
- 连接 WebDAV 数据源并进入任意含多个视频的目录，切换排序方式，预期顺序正确且无崩溃。

## Concrete Steps

工作目录：`/Users/xiongzhipeng/Applications/Enchron`

1. 修改 `XrPlayer/FileBrowsing/Domain/ValueObjects/SortCriteria.swift`，新增共享排序入口。
2. 修改 `XrPlayer/FileBrowsing/Adapters/Local/LocalDataSourceAdapter.swift`、`XrPlayer/FileBrowsing/Adapters/SMB/SMBDataSourceAdapter.swift`、`XrPlayer/FileBrowsing/Adapters/WebDAV/WebDAVDataSourceAdapter.swift`，删除重复排序函数并改为调用共享入口。
3. 在 `Tests/XrPlayerCoreTests/` 补充 `SortCriteria` 的纯逻辑测试。
4. 运行 `swift build`、`swift test`、`swiftlint lint`、`scripts/check-workaround.sh XrPlayer/`。

## Validation and Acceptance

验收标准是：本地、SMB、WebDAV 的文件排序行为保持不变，但排序规则只保留一份；并且 `swift test` 里的纯逻辑测试可以独立证明名称、时间、大小在升序和降序下的排序语义。

## Idempotence and Recovery

本计划中的编辑都是增量修改，可重复执行。若共享排序入口导致某个适配器编译失败，可先恢复为原本的私有排序函数，再核对 `SortCriteria` 对 `MediaFile` 的依赖和可见性；不会涉及数据迁移、持久化变更或不可逆操作。

## Artifacts and Notes

关键验证记录：

    swift build
    Build complete! (12.24s)

    swift test
    Executed 185 tests, with 1 test skipped and 0 failures

    swiftlint lint
    Done linting! Found 50 violations, 0 serious in 85 files.

    scripts/check-workaround.sh XrPlayer/
    ✅ 所有 WORKAROUND 注释均包含移除条件说明

## Interfaces and Dependencies

不会新增或修改跨模块 protocol。新增的稳定接口仅限 `XrPlayer/FileBrowsing/Domain/ValueObjects/SortCriteria.swift` 中的共享排序方法，供 `FileBrowsing` 各 adapter 调用。测试仍保持在 `XrPlayerCore` 目标内完成，不引入新的外部依赖。

Updated on 2026-03-21。已完成排序逻辑收敛与四项必需验证，待提交并创建 PR。
