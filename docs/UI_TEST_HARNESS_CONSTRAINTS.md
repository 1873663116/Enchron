# UI 测试通道与 visionOS 自动化的约束

本文记录 `Tests/EnchronAppUI`、`Tests/EnchronApp` 与 App 侧测试通道里**无法从代码本身读出**的事实：XCUITest 在 visionOS 上的实际行为、可用的观察通道、以及若干时序容差的来由。旅程词汇、证据受理判据与设备保留清单归 `.agents/skills/vp-e2e/`，本文不重复它们，只记录测试代码自身依赖的平台行为。

## 观察通道

- **测试宿主的 stdout 既不进 xcodebuild 日志，也不进设备上的 result bundle**。app 容器进得去（经 devicectl），所以测量报告写进容器而不是打印出来。解码能力矩阵就落在容器里的 `video-decoder-matrix.tsv`。
- **`XCUIScreen.main` 在当前 visionOS 构建上返回 1×1 图像**，读起来像一张黑帧而不是一次抓取失败。application element 仍然能抓，所以退化的屏幕图像要回退到它。
- **模拟器截图 lane 没有点进模拟器的通道**，想看的那一屏必须在启动时就可达；启动参数因此是到达某一屏的唯一途径。
- **精确时间轴由 scrubber 的双击打开**，合成 tap 复现不了双击，所以逐帧步进按钮在测试里除了走测试通道之外不可达。

## XCUITest 与 visionOS 的场景

- **Application element 不属于任何一个 visionOS Scene**。对它合成事件会在 Scene 查找上失败，而这个失败会结束这个长驻测试方法并把 app 一起拆掉。正确做法是让那条命令失败，而不是把整个会话拖走。
- **Panorama 与 Dock 会有意关闭主窗口**。那个 Scene 离场期间不要读它的 accessibility value：元素可能在 `exists` 与 `value` 之间消失，XCTest 把这种情况报成 application failure 而不是"节点不存在"。同理，目标控制面一出现，提交转换就可能关掉来源窗口，从那一刻起以目标状态为准。
- **被遗弃的常驻会话会让 testmanagerd 把证据一直留在头显上直到测试返回**，所以空闲的会话必须自己结束。
- **`xcodebuild` 把 `TEST_RUNNER_ENCHRON_*` 去掉前缀转发进 runner 进程**。对一个不重启的常驻 runner 来说，这是调用方够到 app 环境变量的唯一路径。
- **沉浸空间关闭之后场景输入所有权会丢**，需要显式恢复，而不是靠重启 app——重启会把当前状态一起丢掉。
- **自动隐藏的 chrome 熬得过一次控制器往返，熬不过四次**，所以菜单序列必须落在同一条命令里。

## 预算与合成输入的实测常数

2026-09-02 在模拟器与真机两条 lane 上实测得出，证据在当轮 reachability 运行的 raw 目录里：

- **XCUITest 的 `tap()` 在合成事件前等待 app 静默，等待上限约 60 秒**。导入媒体后的缩略图与库落盘工作让 app 长时间不静默，所以任何由空闲期样本推出的 p95 预算都会结构性地卡在这个窗口里、把一次正常的慢 tap 杀成 transport-timeout。合成输入类动词的预算地板由 `provisional_budgets.json` 的 `floorSeconds` 承载（当前 75 秒），高于该上限。
- **runner 的应答等待默认 30 秒**（`--timeout-seconds`），必须由调用方随预算下发，否则预算高于 30 秒的调用会先撞 runner 自己的死线，报出的 kind 是 `response-timeout` 而不是 `transport-timeout`。
- **模拟器 lane 打开本地媒体的合成 tap 会吊死 app 主线程**，而不是无害失败；这是"打开本地媒体必须经真实点击"（vp-e2e simulator.md）的更强形式。播放类场景在模拟器 lane 必须换 lane 安全的 fixture 并接受入口不可驱动，判定归 device lane。
- **无人佩戴的真机上，场景 phase 事件跨场景销毁不触发**：主窗口在播放期间被撤销再重开后，其 `scenePhase` 直接继承 active 而没有 background→active 转换。任何"等到 active 再行动"的门槛必须以布防后的新转换为准，否则会立即放行。
- **撤销一个窗口可能把整个 app 送进 background 并被系统挂起**（进程存活、命令通道与 AX 全部无响应），即便另一个窗口刚刚 appeared。播放→主窗交还因此把撤销延迟到主窗布防后的下一次 active 转换；等不到就保留双窗，绝不冒挂起风险。
- **段间复用常驻 runner 省去每段 `ensure-session` 的 115–286 秒建会话与 30–56 秒 `halt`，四段合计 10–20 分钟（device lane 关键路径约 57 分钟的 20–35%），段证据对齐由 runner `sessionID`（`ready.json`）改为每段新建的 `evidenceSession`（`evidenceSession=<uuid>`，`reachability evidence session=<uuid>`）**。

## AX 标识符在 visionOS 上丢失的地方

- **`.alert` 里的 `TextField` 丢掉 `.accessibilityIdentifier`**，而同一个 alert 的按钮保留。字段因此只剩 placeholder 这一个把手，输入动词要从标识符退回 label 谓词、再退回 placeholder，而不是让这个操作无法驱动。
- **SwiftUI `Menu` 在真机 visionOS 上可能报 `isHittable == false`，却仍然接受语义 tap**。可观察的契约是"菜单可用 → 公共选项可用 → 设置标题变了"，`isHittable` 单独不足以否决这个系统控件。
- 系统 `Menu` 里只有 `Button` 行保留标识符、`Section` 会吞掉内部每一行的标识符——两条见 `docs/DESIGN_SYSTEM_CONSTRAINTS.md`。

## 时序容差的来由

- **`PlaybackSeekPresentation` 在时长的 2% 内接受渲染器位置**，而 `waitForState` 每 0.1 秒轮询一次，所以一个 Playing 快照可能比目标多走一次轮询。
- **在 tap 之前立刻读 accessibility 状态**。用更早那次连续性等待返回的播放值，会把一个 Playing 的相对 seek 目标按 UI 准备所花的时间整体平移。
- **谓词只钉 epoch**，否则后续的自然播放会把一个本来打错的传输目标变成通过的结果。
- **30 秒的 fixture 是有意的**：证完 Cancel 语义之后要倒回，让这次往返测的是活动会话替换，而不是与媒体的自然结束赛跑。
- **一次启动可能恢复任意滚动偏移**，所以要在库的开头归一化，再按它稳定的排序去搜索。

## 状态复位的语义

App 侧测试通道的复位不是"删掉一切"：

- **TestMediaInbox 是 harness 拥有的暂存区，不是 app 状态**。在这里清掉它，等于强迫每个用例重新推一遍所有媒体文件。
- **内存中的媒体库必须最先清**：它在变更时与终止时都会把自己重新持久化，留着它就会把这次复位刚删掉的引用复活。
- **记住的服务器证书是 app 状态**，落在自己的前缀下，而产品没有"遗忘"入口；不清它，信任提示在第一次接受之后就再也不会出现。
- **复位必须报告它建立出来的状态**，只报删除数量会把下一个单元真正依赖的东西——库里现在有什么——藏起来。
- **空间验收测试从隔离的播放状态开始，但同一个测试内部的进程重启必须保住它正在验证的格式**。新的 reset token 表示新测试，同一个 token 表示该测试内部的一次冷重启。
