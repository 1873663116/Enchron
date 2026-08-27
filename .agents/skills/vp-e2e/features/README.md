# Enchron 特性地图

本目录是仓库长期维护的验证真相源：每个用户可见特性一个文件，回答它是什么、用户怎么到达、harness 怎么驱动、什么可观察终态算证明。驱动应用之前先读本索引，再以对应分册为操作规程。

## Baseline preconditions

- 会话按 [SKILL.md](../SKILL.md) 的 Launch 一节建立，`ensure-session` 返回 `stage: ready`。
- 同一目标在同一时刻只有一个常驻 runner。
- 干净状态取证的固定顺序是：先 `app-command --verb resetState`（清除 `enchron.*` 键），再重启 App，之后才导入媒体。顺序颠倒时，内存中仍持有的旧媒体库对象会在下一次状态变更时把已删除的引用重新写回磁盘。
- 注入式导入的 fixture 先推入容器的 `Documents/TestMediaInbox/` 目录，再经 `importMedia` 走生产入库管线。
- 执行过程出现异常时，先跑 [SKILL.md](../SKILL.md) 的 Doctor 检查。

## Driving conventions

- 除非分册显式另有说明，所有操作从基线状态起步。命令原样精确执行，引号与参数不做改动。
- 元素定位优先使用语义 identifier；被系统容器丢弃 identifier 的字段，按 label 或 placeholder 命中。存活规则见[产品事实](../references/product.md)。
- 合成滑动一律携带 `--identifier`。省略它会导致测试会话被拆除。
- 自动隐藏的菜单与 chrome 存续时间短于两次控制器往返：要么用 `tapSequence` 在一条命令内连发，要么直接读取 `tap` 自身返回的层级。
- 每一步声明驱动方式（`real`、`injected`、`setup`、`evidence`、`wearer`，语义见 [SKILL.md](../SKILL.md)）。使用注入时必须写明绕过了什么、因此对哪类缺陷失明。
- 同一控件在 window 与 panorama 下属于两个渲染宿主，各自需要独立的 hit test 证明，互不覆盖。

## Proof and skip reporting

Accessibility 层级中的存在性、`isHittable` 与 XCTest 动作返回值，分别只证明三件事：目标被公开、框架认为可命中、框架完成了事件合成调用。**事件是否送达产品逻辑，证据必须由应用给出**（诊断串或探针）。取证时同时捕获触发动作与随后的系统状态，而不是只截取最终画面。

每个分册的 `## 证据` 一节按三类证据列出该特性的要求与看守者：

| 种类 | 定义 | 产生者 |
|---|---|---|
| 结构 | 产品递出的内容在逻辑上正确 | 逻辑测试与源码级结构检查，秒级 |
| 物理 | 真实运行环境上采集到的客观数值正确 | 设备取证 |
| 感知 | 佩戴者的主观判断成立 | 佩戴者，每种情况确认一次；当时采集的帧成为参照物，此后由机器比对 |

**一条特性证实成功，等于它声明的证据集合全部齐备。** 三类证据的分界规则是「该断言的真假由谁决定」：由产品自身代码决定的归结构证据，取决于 Apple 黑盒或物理世界的归物理证据，属于人的感受的归感知验收。表中标注**待建**或**待做**的格子是当前无人看守之处，也是这份地图的主要用途；`Scripts/rules/verify_feature_evidence_coverage.py` 会逐表清点这些缺口。

某条路径不可达时，如实报告尝试过的命令与未满足的前置条件；一个入口被阻塞，不能偷换为「另一个入口已验证」。只验证了便捷入口、而地图明明列有其它入口的证明，是不完整的证明。

### 可达性承诺

佩戴者边界（见 [SKILL.md](../SKILL.md)）之外的产品操作若不可达，即为缺陷，其归属只有两类：产品公开的 Accessibility 事实不足，或测试通道缺少能进入同一产品状态与处理管线的动词。当空间手势无法由 XCUIAutomation 合成时，允许用 DEBUG 动词进入同一产品状态或处理管线，并以应用侧证据完成送达判定。常驻的透明机制窗口对 Accessibility 层级保持隐身，也不作为可命中目标。

全量操作集由 `Scripts/verification/generate_reachability_inventory.py` 从产品源码生成到 `Config/reachability_operation_inventory.json`，每个操作携带从源码推导出的证明语境集合。浏览域操作在「主窗口浏览」语境证明一次即可；播放域操作按其生产渲染宿主实际出现的 Window、Portal、Panorama 或 Docked 语境逐项证明。同一控件复用于 ornament、attachment 或 dock 容器时，每个容器都是独立的运行时判定点。生成器无法从生产宿主推导出语境集合时会直接失败，以保证基线只收录真实的判定点。

物理设备上的第零层回归由 `Scripts/verification/reachability_matrix.py` 执行。已经证明可达的判定点在被驱动后回退为不可达时，runner 判为失败。首次发现的不可达判定点保留为已知缺陷，直到修复并经真机复测转绿。

## Feature entry contract

每个分册以一级标题和一段说明该特性在用户端表现的文字开篇，随后依序包含以下二级标题：

1. `Sub-features`：功能子项列表，每行对应一项具体行为。
2. `How to get to it (user POV)`：用户可以触达该特性的全部入口。
3. `Driving it with <harness>`：以 `Preconditions:` 开头，随后给出精确命令与预期的客观结果；harness 是该特性实际使用的驱动工装。
4. `证据`：三类证据的判据与看守者表（契约见上节）。
5. `证明的终态`：何种可观察终态算作证明。
6. `Gotchas`：可能导致测试失真或白费功夫的陷阱。

保持地图纯粹：只记录面向用户的交互路径、语义稳定的句柄、必要状态、确切命令与客观验证证据；内部实现细节归 references 与源码。

## Features

**取得媒体**
- [media-import.md](media-import.md)：媒体进入资料库的路径。
- [remote-source-connection.md](remote-source-connection.md)：SMB 与 WebDAV 的添加、浏览与打开。
- [emby-library.md](emby-library.md)：Emby 的浏览、播放与服务器端观看状态。

**播放**
- [clean-state-playback.md](clean-state-playback.md)：干净状态下从媒体库打开并播放任意已入库视频。
- [picture-interpretation.md](picture-interpretation.md)：动态范围、立体、投影的正确解释。
- [track-selection.md](track-selection.md)：音轨与字幕轨的切换。
- [viewing-state.md](viewing-state.md)：观看进度与续播。
- [network-resilience.md](network-resilience.md)：网络抖动下的播放。

**呈现与界面**
- [mode-transitions.md](mode-transitions.md)：window、portal、docked、panorama 及其切换。
- [format-editing.md](format-editing.md)：Video Format 编辑（窗口菜单与面板 Advanced Settings 两个宿主）。
- [controls-summon.md](controls-summon.md)：播放控件的显示与隐藏。

**存储**
- [cache-and-artwork.md](cache-and-artwork.md)：容器索引缓存与 Artwork。
