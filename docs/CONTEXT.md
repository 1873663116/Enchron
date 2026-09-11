# Enchron 术语

本文定义在 Enchron 中容易与相近概念混淆的特有名词。

## 播放与媒体

**Playback Presentation**：视频在产品中的呈现位置，取 `window`、`portal`、`docked`、`panorama` 之一，前两者由主窗口承载，后两者由沉浸空间承载。它与解释媒体画面的 Media Format 是不同概念。
**Content Family**：一个 Playback Presentation 的画面几何类别，取 `flat`（`window` 与 `docked`）或 `panoramic`（`portal` 与 `panorama`）。它决定换片时落回哪一格，不表示视频当前由窗口还是沉浸空间承载。
**Residency**：播放相对于宿主界面的驻留状态，取 `browsing`、`playing(host:)` 或 `closing(since:reason:)`，其中 host 为 `window` 或 `immersiveSpace`。它记录播放此刻由谁承载，不是 Playback Presentation 本身，两者可以在同一个 host 内变化。
**Media Format**：用户要求 Enchron 如何解释媒体画面。它不表示视频当前呈现在哪里，也不是来源媒体自身声明的 Format Description。
**Format Description**：一条媒体流向解码器声明的技术事实，包括编码、尺寸、色彩解释，以及立体与动态范围的配置。它由来源媒体决定，不随用户偏好改变。
**Custom Angle**：Enchron 将矩形全景画面按 180° 至 360° 的水平覆盖角解释。它不表示鱼眼镜头映射。

**Media Library**：Enchron 管理的虚拟媒体分类。它保存对媒体的组织和引用，不拥有来源媒体。
**Library Folder**：Media Library 中由用户管理的虚拟分类容器。它不是本地文件系统或远程服务中的目录。
**Source Directory**：本地文件系统或远程服务实际拥有的目录。它不属于 Enchron 的虚拟媒体分类。

**File Source**：直接提供目录结构与文件字节流的媒体来源，如本地、SMB、WebDAV。它不提供媒体实体、元数据或服务器端用户状态。
**Media Byte Stream**：把一个来源媒体表达为可按字节区间读取的流。它只回答长度与指定区间的字节，不解释容器内容，也不代表提供它的来源。

**Emby Source**：提供媒体实体、元数据与服务器端用户状态的媒体服务器来源。它不是 File Source；其媒体流由系统网络库读取，再经 Media Byte Stream 交给播放核心。

**Media Reference**：从 Media Library 指向来源媒体的持久引用。它是访问入口，不是底层媒体的身份。
**Media Identity**：Enchron 用于判断不同入口是否指向同一底层媒体的稳定身份。它独立于 Media Reference。
**Content Revision**：同一 Media Identity 对应内容的版本凭据。它用于区分媒体身份未变但内容已经变化的情况。
**Media Source Information**：同一 Content Revision 的来源媒体所具有的可持久技术事实。它不是实时读取状态，也不是用户选择的 Media Format。

**Playback Collection**：用户开始播放时，本次连续播放可以包含媒体的范围。它不是已经生成的播放顺序。
**Playback Queue**：从 Playback Collection 生成的本次播放顺序。它与之后继续变化的浏览结果分离。
**Persistent Viewing State**：Enchron 为同一 Media Identity 保存的可恢复位置或已看完状态。它不是通用观看历史。
**Viewing State Authority**：一次播放会话的观看状态权威，取值为 Enchron 持久化或媒体服务器之一。它决定播放结束时进度与观看状态写向何处。

## 空间环境

**Environment**：Enchron 提供的一个稳定观影场景身份。它与场景当前采用的视觉变化分离。身份集合是 `quiet-room`、`ocean`、`placeholder-red`、`placeholder-green`、`placeholder-blue`。
**Default Environment**：`quiet-room`。它是 Docked 在没有选择时进入的场景，不出现在 Environment Card 里，没有 Environment Effect。
**Card Environment**：出现在 Environment Card 里、可被佩戴者选择的身份：`ocean` 与三个纯色占位。它们都有 Light Mode 与 Dark Mode。
**Environment Scene**：由一个独立 Swift Package 交付、实现 `EnvironmentSceneContract` 的场景运行时（Ocean、Quiet Room）。纯色占位没有 Environment Scene。
**Screen Preview**：场景内名为 `ScreenPreview` 的面片，是屏幕静止位姿的唯一作者来源：它的世界变换给出底边高度、到佩戴者的距离、朝向偏航与屏幕尺寸，场景包在 `load()` 里读成 `restPose` 后禁用它；在 Reality Composer Pro 里它同时用于观察反射。
**Environment Effect**：同一 Environment 内可变化的视觉表现。它不形成新的 Environment 身份。
**Environment Context**：当前是否有一个 Environment 处于活动状态，以及该场景当前采用什么 Environment Effect。它不是 Playback Presentation。

## 验证

**W0–W3**：一个改动在合并前必须跑到的最高验证阶段。级别按改动路径判定，四级逐级包含，低级是高级的前置。

| 级 | 跑什么 | 要什么 |
|---|---|---|
| W0 | 静态检查：结构规则、SwiftLint、脚本清单 | 只读源码，不构建 |
| W1 | W0 加构建与测试：Xcode 产品构建、PlaybackCore、领域测试、源解析对拍 | 工具链与 TestMedia |
| W2 | W1 加模拟器 Journey | 模拟器 |
| W3 | W2 加 Device Hub 真实输入 Journey | 真机注视与捏合 |

W0 与 W1 由 `Scripts/rules/run_verification.py` 执行，是 PR 上那个会红的检查。W2 与 W3 由驱动者实时判读，产出证据清单。

**Structure Check**：W0 里的一项，读源码判定一条结构约束，不构建也不运行产品。`run_verification.py` 逐项执行并各写一份日志。

**Self-test**：给规则本身写的测试，喂已知正确与已知错误的样本，断言规则对前者放行、对后者拦截。没有它，规则报绿分不清是仓库干净还是规则坏了。命名 `test_*.py`，放进 `Scripts/rules/` 即被扫描执行，不需要登记。

**Known Bad Sample**：一份被判定为「应当被拒绝」的样本，喂给某条规则，断言它确实拒绝、且拒绝的理由正确。样本以声明式的文本变异写在 `Config/guard_selftests.json`：指定文件、要替换的原文、替换后的内容与期望的报错。`verify_guard_selftests.py` 把当前工作树复制一份，在副本上施加变异，跑副本里的那条规则，再还原。五条护栏保证样本不空转——原文必须出现且次数吻合、变异必须真的改变了被断言的内容、未变异时规则必须先通过、规则必须拒绝、且拒绝时输出的理由必须是期望的那一条。

**Mutation Coverage Mandate**：每条登记在 `STRUCTURE_CHECKS` 里的检查，都必须有一条坏样本、一份 `test_*.py` 自测，或一条写明理由的 `externalSubject` 声明；三者皆无即失败。声明用于判定对象不在仓库文本里的检查——真实媒体、xcodebuild 的行为、真机输入——它们的坏样本无法由改仓库文本构造。理由留空同样失败，所以没有静默豁免。

**Ratchet**：只能收紧不能放松的基线。`--write-baseline` 拒绝任何基线里尚不存在的条目，所以新违规的唯一出路是改代码或论证规则不成立。`design_source_architecture_baseline.json` 与 `swiftlint_baseline.json` 都按此约束。

**Journey**：按用户真实使用顺序编写的回归单元，声明前置状态、有序步骤、每步的证明目标与终态判据。每条 Journey 从干净状态开始，Journey 之间不传递状态。它组织行为层回归；送达事实由可达性矩阵回答。
**Unguarded Evidence Point**：特性声明了但尚无看守者的证据格。它不是失败，是「绿」不覆盖的已知范围，回归报告必须逐项列出。

**Lane**：一次回归运行绑定的执行环境，取 `simulator` 或 `device`；合同侧的 `LaneRequirement` 另有 `either` 与 `both` 两种要求，表示该节点接受哪些 lane。它是证据的产生环境，不是被测产品的配置。

**Operation Call**：编译计划中对某个 Operation 的一次具体调用，是回归能够执行的最小单位，由 `op` 工具发起。它不是 Operation 合同，后者声明一项能力，Operation Call 是该能力在某个节点上的一次执行。

**Rubric**：一份验收合同。front matter 的 `criteria` 逐条陈述判定依据，`negativeControls` 逐条陈述什么算不满足。它不是断言代码：能被编译成字段谓词的 criterion 走 L0，编不出的留给 L2 Agent。

**Verdict**：对一个非 Satisfied 节点写入账本的裁决，字段为首个偏离帧序号、裁切区域观察、归因（`product`、`harness` 或 `spec`）与命中的签名 id。它不是 `op` 返回的判定结果——后者是这一次调用的观测，Verdict 是对该观测的归因。

**已知缺陷台账**：登记在 `Config/regression/known_defects.json` 的一组在册缺陷，每条以一个签名 id 或一条字段谓词声明它认领哪种失败。命中的节点终态记 `failed(known)` 而不是 `failed`。它不豁免失败，只把已经归因过的失败与新失败分开。

**账本锁**：一条 lane 上出现非 Satisfied 的节点之后，该 lane 拒绝下一次 op，直到账本收到那个节点的裁决。终局调用以仪器故障收场且计划不再允许重试的 attempt 同样非 Satisfied：节点停在 `leased`，裁决只能是归因 harness 的 `indeterminate` 或 `deferred(human)`。它不是工具约定而是回放期的转移规则：一份在锁住的 lane 上继续跑 op 的账本回放不过去。绿色步骤不设锁。

**异常包**：L2 归因的唯一输入。偏离 call 前后两张截图、它们拼成的帧格图（帧序号从 0 起，这个编号就是裁决里 `firstDeviantFrame` 的取值域）、该次调用的结构化字段、以及帧命中的签名 id。它不是「失败时的日志」，产不出的部分逐条说明为什么产不出。

**判读三级**：L0 由 rubric 编译出的字段谓词，确定性；L1 固定的像素启发，命中注册表里的签名 id；L2 Agent，只在异常包之后做归因。编不出谓词的 criterion 逐条进覆盖报告，不假装已覆盖。

**人类层**：账本终态为 `deferred(human)` 的节点集合，静态为空。进入条件由账本校验：同一节点连续两次 attempt 的 op 结果都是仪器超时类。产品慢是 `Violated`，不可推迟。它不是「Agent 判不了就交给人」，而是仪器两次都没能让这个节点被判定。
