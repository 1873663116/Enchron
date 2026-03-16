# 收敛 PlayerUI 时间标签格式化重复实现

本 ExecPlan 是活文档。Progress、Surprises & Discoveries、Decision Log、
Outcomes & Retrospective 四个章节必须在工作进行中保持更新。

本文档须遵循 PLANS.md（仓库根目录）的全部要求进行维护。

## Purpose / Big Picture

这次清理不改变任何播放功能，只把 `PlayerUI` 中重复出现的时间标签格式化逻辑收敛到一个地方。完成后，主播放控件和精确时间轴会继续显示同样的时间字符串，但以后如果要调整显示规则，只需要改一个 formatter，而不是同时改多个视图并承担漂移风险。

## Progress

- [x] (2026-03-17 14:05) 读取 `AGENTS.md`、`ARCHITECTURE.md`、`REGRESSION.md`、`TESTING.md`、`quality_gates.md` 和 `PLANS.md`，确认本轮必须先建自动化分支与 Exec Plan。
- [x] (2026-03-17 14:12) 锁定清理主题为 `PlayerUI` 时间标签格式化去重，范围限定在同一上下文内，不改模块接口。
- [x] (2026-03-17 14:19) 抽出共享 formatter，替换 `PlayerControlsView` 和 `DetailedTimelineView` 的重复实现，并补充 formatter 单元测试。
- [x] (2026-03-17 14:25) 完成仓库要求的验证：`swift build`、`swift test`、`swiftlint lint`、`scripts/check-workaround.sh XrPlayer/`。
- [ ] (2026-03-17 14:26) 提交、推送并创建 PR，随后触发 `@CodeX Review`。

## Surprises & Discoveries

- Observation: `swift test` 依赖 `Package.swift` 中显式列出的源文件；只在 `XrPlayer/` 新增文件还不够，测试侧也要同步暴露。
  Evidence: `Package.swift` 的 `sources` 数组手动列举了 `PlayerUI/UseCases` 文件。

## Decision Log

- Decision: 这次只处理时间标签格式化重复，不顺手整理其他魔法数字或 UI 常量。
  Rationale: `cleaner` 要求单主题、小范围、可审查；扩大到布局常量会混入新的设计判断。
  Date: 2026-03-17

- Decision: 新 formatter 放在 `XrPlayer/PlayerUI/UseCases/`。
  Rationale: 该逻辑直接服务 `PlayerUI` 展示文本，不属于 `Shared`，也不应继续埋在任一具体 View 内。
  Date: 2026-03-17

## Outcomes & Retrospective

本轮目标已经达成：`PlayerUI` 中原本分散在两个视图里的时间格式化逻辑已经收敛到一个 formatter，主控件与精确时间轴的显示规则由单元测试兜住。剩余动作只剩发布 PR 和等待云端审查，没有新的实现缺口。

## Context and Orientation

当前重复点位于 `XrPlayer/PlayerUI/Views/PlayerControlsView.swift` 与 `XrPlayer/PlayerUI/Views/DetailedTimelineView.swift`。这两个视图都把秒数转换成面向用户的时间标签，其中主播放控件使用普通时钟格式，精确时间轴既使用普通时钟格式，也使用带帧号的精确格式。重复逻辑意味着今后如果修正边界显示或统一样式，必须在多个视图中手动同步，容易形成文档和实现之外的隐性漂移。

本轮不会修改 `PlaybackCore`、`App`、`Persistence` 或跨模块 protocol。它只会在 `PlayerUI/UseCases` 内增加一个共享 formatter，并让两个 `View` 调用它，再补一组纯逻辑测试证明格式输出保持稳定。

## Plan of Work

先在 `XrPlayer/PlayerUI/UseCases/` 新增 `PlaybackTimeFormatter.swift`，提供两个静态方法：一个输出主控件与刻度标签使用的普通时钟字符串，一个输出精确时间轴当前指针使用的带帧时钟字符串。然后修改 `PlayerControlsView.swift` 和 `DetailedTimelineView.swift`，删除视图私有的重复格式化函数，统一改为调用新 formatter。最后更新 `Package.swift` 让 `swift test` 能编译新文件，并在 `Tests/XrPlayerCoreTests/` 中新增 formatter 测试，覆盖“小时显示”“分钟显示”和“带帧显示”三个边界。

## Milestones

### M1: 提取共享时间标签格式化器

完成后，`PlayerUI` 的两个视图不再各自维护私有格式化函数，而是共用一个 formatter。用户看见的字符串应保持不变。证明方式是运行编译和单元测试，并检查 diff 只围绕 formatter 与其调用方。

#### 验证（双轨）

Agent 自检：
- `swift build` — 预期无 error
- `swift test` — 预期全部通过，且新增 formatter 测试通过
- `swiftlint lint` — 预期无 error 级别违规
- `scripts/check-workaround.sh XrPlayer/` — 预期通过

人类真机验证：
- 打开任意视频，观察主进度条左侧当前时间与右侧总时长显示，预期与本轮前一致。
- 进入“精确时间轴”，观察首尾刻度、中心时间标签与拖动中的时间文本，预期格式仍正确，且无空白或异常截断。

## Concrete Steps

工作目录：`/Users/xiongzhipeng/Applications/Enchron`

1. 新增 `XrPlayer/PlayerUI/UseCases/PlaybackTimeFormatter.swift`。
2. 修改 `XrPlayer/PlayerUI/Views/PlayerControlsView.swift` 与 `XrPlayer/PlayerUI/Views/DetailedTimelineView.swift`，移除重复函数并改为调用新 formatter。
3. 修改 `Package.swift`，把新 formatter 文件加入 `XrPlayerCore` 目标源列表。
4. 新增 `Tests/XrPlayerCoreTests/PlaybackTimeFormatterTests.swift`。
5. 运行 `swift build`、`swift test`、`swiftlint lint`、`scripts/check-workaround.sh XrPlayer/`。

## Validation and Acceptance

验收标准是：主进度条时间、精确时间轴刻度、精确时间轴中心时间文本在行为上与改动前一致，但重复实现只保留一份；并且 `swift test` 里新增的 formatter 测试可以独立证明该显示规则。

## Idempotence and Recovery

本计划中的编辑都是增量修改，可重复执行。若新增 formatter 导致某个视图编译失败，可直接回到对应调用点恢复为局部私有函数，再重新梳理签名；不会涉及数据迁移或持久化回滚。

## Artifacts and Notes

关键验证记录：

    swift build
    Build complete! (1.31s)

    swift test
    Executed 183 tests, with 1 test skipped and 0 failures

    swiftlint lint
    Done linting! Found 49 violations, 0 serious in 82 files.

    scripts/check-workaround.sh XrPlayer/
    ✅ 所有 WORKAROUND 注释均包含移除条件说明

## Interfaces and Dependencies

不会新增或修改跨模块 protocol。新增的稳定接口仅限 `XrPlayer/PlayerUI/UseCases/PlaybackTimeFormatter.swift` 中的静态 formatter 方法，供 `PlayerUI` 视图层调用。测试依赖仍保持在 `XrPlayerCore` 目标内完成，不引入新的外部库。

Updated on 2026-03-17。完成实现与验证，待提交并创建 PR。
