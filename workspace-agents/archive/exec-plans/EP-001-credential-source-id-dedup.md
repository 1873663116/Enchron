# Credential Source ID Dedup

本 ExecPlan 是活文档。Progress、Surprises & Discoveries、Decision Log、
Outcomes & Retrospective 四个章节必须在工作进行中保持更新。

本文档须遵循 PLANS.md（仓库根目录）的全部要求进行维护。

## Purpose / Big Picture

这轮清理不改变任何用户可见功能。目标是把 FileBrowsing 中“凭证稳定键”的生成逻辑收敛到单一入口，避免 `DataSource`、`SMBDataSourceAdapter`、`WebDAVDataSourceAdapter` 三处各自维护同一不变量。完成后，后续对 SMB 与 WebDAV 凭证键规则的修改只需要改一个位置，并且现有行为保持不变，尤其是 SMB 忽略 share、WebDAV 包含 rootPath 的规则不变。

## Progress

- [x] (2026-03-15 08:46 CST) 阅读自动化治理文档、AGENTS.md、ARCHITECTURE.md、REGRESSION.md、TESTING.md，确认本轮为单一 entropy cleanup 任务。
- [x] (2026-03-15 08:47 CST) 扫描候选问题，锁定“credentialSourceID 逻辑分散重复”作为高置信度单一主题。
- [x] (2026-03-15 08:48 CST) 在 `ConnectionInfo` 中建立唯一的 credential source ID 入口，并让 `DataSource` 与 SMB/WebDAV adapter 全部复用。
- [x] (2026-03-15 08:48 CST) 调整测试，直接覆盖共享入口，并保留 `DataSource` 转发兼容性断言。
- [x] (2026-03-15 08:49 CST) 执行 `swift build`、`swift test`、`swiftlint lint`、`scripts/check-workaround.sh XrPlayer/`，验证通过并确认回归项为 REG-020、REG-021、REG-022。
- [ ] (2026-03-15 08:47 CST) 如果验证通过，提交、推送并创建或更新 PR。

## Surprises & Discoveries

- Observation: 自动化 worktree 当前是 detached HEAD，未绑定自动化分支。
  Evidence: `git status --short --branch` 返回 `## HEAD (no branch)`。

## Decision Log

- Decision: 仅处理 credential source ID 去重，不顺手扩展为更大的 FileBrowsing 凭证重构。
  Rationale: 这是高置信度、低风险、可审查的清理主题，符合熵治理文档要求。
  Date: 2026-03-15

- Decision: 把唯一入口放在 `FileBrowsingDomain.ConnectionInfo`，而不是 `DataSource` 或某个 adapter。
  Rationale: 键规则直接依赖连接信息，不依赖 `DataSource` 标识，也不应由某个具体协议 adapter 私有掌握。
  Date: 2026-03-15

## Outcomes & Retrospective

- Outcome: `credentialSourceID` 规则已集中到 `FileBrowsingDomain.ConnectionInfo`，`DataSource` 与 SMB/WebDAV adapter 不再各自拼接字符串。
- Outcome: 自动化验证全部通过，行为兼容性由现有断言和新增共享入口断言共同覆盖。
- Remaining: 仍需提交、推送并创建 PR，让 reviewer agent 和人类在 PR 维度审查。

## Context and Orientation

本仓库的 FileBrowsing 上下文负责统一本地、SMB、WebDAV 数据源。凭证存储使用 `Persistence/Adapters/KeychainStore.swift`，存取时依赖一个稳定字符串键。当前这个键的规则已经在测试中固化：SMB 只按 `sourceType + host + port` 生成，忽略用户后续选择的 share；WebDAV 按 `sourceType + host + port + rootPath` 生成。相关文件分别是 `XrPlayer/FileBrowsing/Domain/Entities/DataSource.swift`、`XrPlayer/FileBrowsing/Adapters/SMB/SMBDataSourceAdapter.swift`、`XrPlayer/FileBrowsing/Adapters/WebDAV/WebDAVDataSourceAdapter.swift` 和 `Tests/XrPlayerCoreTests/V03Tests.swift`。

这里的“稳定键”指的是：同一个远端数据源在不同运行、不同 UI 入口下都能命中同一条凭证记录的字符串 ID。该不变量如果分散在多个实现里，会导致未来某处改了格式，另一处未同步，从而出现“保存了凭证但连接阶段或播放阶段读不到”的隐性回归。

## Plan of Work

先在 `XrPlayer/FileBrowsing/Domain/ValueObjects/ConnectionInfo.swift` 新增一个只读属性，用它统一描述 credential source ID。然后把 `DataSource.credentialSourceID` 改成透传该属性，删除 SMB 与 WebDAV adapter 中的私有重复 helper，所有读 keychain 的调用改为使用 `info.credentialSourceID`。最后更新测试命名与断言，使测试直接覆盖共享入口，同时保留现有行为期望不变。

## Milestones

### M1: 集中稳定键规则

这一里程碑完成后，FileBrowsing 的 credential source ID 规则只在一个地方定义。`DataSource` 和两个远程 adapter 都不会再各自拼接字符串。结果应当是代码更易局部推理，但外部行为完全保持兼容。

#### 验证（双轨）

Agent 自检：
- `swift build` — 预期无 error
- `swift test` — 预期所有测试通过
- `swiftlint lint` — 预期无 error 级别违规
- `scripts/check-workaround.sh XrPlayer/` — 预期通过

人类真机验证：
- 因为本次改动命中 `FileBrowsing/Adapters/SMB/*` 与 `FileBrowsing/Adapters/WebDAV/*`，需要执行 `REG-020`、`REG-021`、`REG-022` 对应的 SMB 连接/凭证持久化/WebDAV 浏览播放检查。

## Concrete Steps

在仓库根目录执行：

    git switch -c automation/clearer-credential-source-id
    swift build
    swift test
    swiftlint lint
    scripts/check-workaround.sh XrPlayer/

如果任一命令失败，先修复再重复执行，直到四项都通过为止。

## Validation and Acceptance

验收标准是行为兼容而不是抽象变化本身。自动化上，现有关于 credential source ID 的测试必须继续通过；手工上，SMB 仍应在选择 share 前后复用同一凭证，WebDAV 仍按 host/port/path 维度区分不同凭证作用域。若这些行为无法证明，就不应提交。

## Idempotence and Recovery

本次修改应当是幂等的：重复应用不会产生额外状态变化。如果分支创建后验证失败，可继续在同一分支修复并重跑验证；不要切回 `main` 或直接向主线提交。

## Artifacts and Notes

关键证据将是：

    Tests/XrPlayerCoreTests/V03Tests.swift 中关于 credentialSourceID 的断言保持不变

以及四项必需验证命令全部通过的终端结果。

## Interfaces and Dependencies

不会修改跨模块 protocol 或公开契约。涉及的稳定接口仅限：

- `FileBrowsingDomain.ConnectionInfo`
- `FileBrowsingDomain.DataSource`
- `SMBDataSourceAdapter`
- `WebDAVDataSourceAdapter`

本次不会引入新依赖，也不会改动 `workspace-agents/contracts/`。

Revision note (2026-03-15): 初版计划，记录本轮熵治理主题、分支前提异常和验证路径。
Revision note (2026-03-15): 根据实现进展更新 Progress 与 Outcomes，记录验证结果和命中回归项。
