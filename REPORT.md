# PlaybackCore 快速跳转簇清算报告

## 结论

五个长期失败测试已经全部转绿。四个 controller 测试的产品代码没有丢失最新跳转；失败来自测试样本与 bounded lead 规则冲突，测试在进入要验证的跳转所有权路径前先被首帧 watchdog 终止。处置是把伪 provider 改成能从初始位置到达各跳转目标的样本序列，并在最终目标之后增加一个超过 bounded lead 的占位样本，防止伪媒体在断言前结束。

字幕测试暴露了一处产品缺陷。暂停跳转的 decoder bootstrap 到达目标后，代码没有把 synchronizer 提交到新的媒体时间。跳转等待者虽然成功，字幕却仍按 0 秒计算。生产代码现在只在正在执行的暂停 seek 到达 bootstrap 目标时提交停止的时间轴位置；普通 `startsPaused` 打开仍保持 preroll，等待后续 `play()`。

最终全量 `swift test` 运行 203 个测试。快速跳转簇五项全部通过，剩余失败恰好是任务指定的三个基线失败。`controllerRejectsSecondOpenAndRecordsTheRejection` 含两个 issue，因此汇总为三个失败测试、四个 issue。已知的 `acceptedProResWithoutDisplayedFrameReportsRendererErrorVerbatim` 本次通过。

## `controllerSeekKeepsSessionAndAdvancesStreamEpoch`

根因是测试只提供 PTS 10 的样本，却先要求初始位置出样，再跳到 5 秒。失败现场的关键事件序列为：

```text
12 playbackDelivery.stage.video.providerRead.enter streamEpoch=1
18 videoRenderer.enqueue.started presentationTimeSeconds=10.0
19 playbackDelivery.stage.video.boundedLead.enter presentationTimeSeconds=10.0 streamEpoch=1
21 operation.seek.started
23 control.seek.started targetSeconds=5.0
24 renderer.flushedForSeek streamEpoch=2
33 videoRenderer.enqueue.started presentationTimeSeconds=10.0
34 playbackDelivery.stage.video.boundedLead.enter presentationTimeSeconds=10.0 streamEpoch=2
35 videoRenderer.firstFrameTimedOut error="No video frame was displayed within 5 seconds after playback started."
36 operation.seek.failed
37 control.seek.superseded targetSeconds=5.0
```

PTS 10 相对初始位置和 5 秒目标都超过一秒 bounded lead，所以 `boundedLead.enter` 后没有对应的 `returned`。这不是 session 被 seek 替换，也不是最新 seek 丢失。测试现在提供 PTS 0、5、7；0 和 5 分别到达初始位置与目标，7 作为占位样本阻止伪 provider 在断言前返回 end。原有的同一 session、stream epoch 为 2、rate 为 1 和最终操作 target 为 5 的断言全部保留并通过。

## `newerSeekSupersedesOlderSeekAndOwnsFinalTarget`

根因同样是不可达的单个远端样本，而不是 controller 选错赢家。失败现场已经证明 5 秒旧请求被正确取代，10 秒新请求进入 session 并取得 epoch 3：

```text
21 operation.seek.started
23 control.seek.started targetSeconds=5.0
25 control.seek.superseded targetSeconds=5.0
26 operation.seek.terminatedByCleanup
27 operation.seek.started
29 control.seek.started targetSeconds=10.0
30 renderer.flushedForSeek streamEpoch=3
39 videoRenderer.enqueue.started presentationTimeSeconds=20.0
40 playbackDelivery.stage.video.boundedLead.enter presentationTimeSeconds=20.0 streamEpoch=3
41 videoRenderer.firstFrameTimedOut
42 operation.seek.failed
43 control.seek.superseded targetSeconds=10.0
```

最新请求没有在 generation 竞争中丢失；它被 PTS 20 的 fixture 卡在 bounded lead，随后因会话失败而终止。测试现在提供 PTS 0、5、10、12。旧等待者仍必须收到 `.seekSuperseded(5)`，新等待者必须成功，最终 snapshot 仍严格要求 epoch 3、target 10 和 completed。

## `threeRapidSeeksOnlyAllowNewestWaiterToEnterSession`

失败序列显示第一请求进入 session 后被取代，第二请求在 controller generation 层被第三请求取代，因此没有进入 session，第三请求以 15 秒和 epoch 3 进入 session。真正终止第三请求的是 PTS 20 与 15 秒目标之间五秒的 bounded lead：

```text
22 operation.seek.started
24 control.seek.started targetSeconds=5.0
26 control.seek.superseded targetSeconds=5.0
27 operation.seek.terminatedByCleanup
28 operation.seek.started
30 control.seek.started targetSeconds=15.0
31 renderer.flushedForSeek streamEpoch=3
40 videoRenderer.enqueue.started presentationTimeSeconds=20.0
41 playbackDelivery.stage.video.boundedLead.enter presentationTimeSeconds=20.0 streamEpoch=3
42 videoRenderer.firstFrameTimedOut
43 operation.seek.failed
44 control.seek.superseded targetSeconds=15.0
```

处置是提供 PTS 0、5、10、15、17。测试仍要求 5 秒与 10 秒两个旧等待者分别收到对应的 `.seekSuperseded`，15 秒等待者成功，并要求最终 snapshot 的 target 为 15、epoch 为 3。这样测试覆盖的仍是“只有最新等待者进入并拥有 session”，不再混入首帧 watchdog。

## `rapidRelativeSeeksAccumulateInsideTheCore`

失败时 controller 已经把两次相对跳转累计为 20 秒。事件序列证明 10 秒旧请求被正确取代，20 秒最新请求进入 epoch 3；它最终失败是因为唯一的 PTS 30 样本仍超过 bounded lead：

```text
27 operation.seek.started
29 control.seek.started targetSeconds=10.0
31 control.seek.superseded targetSeconds=10.0
32 operation.seek.terminatedByCleanup
33 operation.seek.started
35 control.seek.started targetSeconds=20.0
36 renderer.flushedForSeek streamEpoch=3
45 videoRenderer.enqueue.started presentationTimeSeconds=30.0
46 playbackDelivery.stage.video.boundedLead.enter presentationTimeSeconds=30.0 streamEpoch=3
47 videoRenderer.firstFrameTimedOut
48 operation.seek.failed
49 control.seek.superseded targetSeconds=20.0
```

测试现在提供 PTS 0、10.5、20.5、22.5。半秒余量覆盖 pause 前已经前进的实际 base time，同时仍在目标的一秒 bounded lead 内。最终断言仍从 snapshot 读取 target，并要求它等于 `baseSeconds + 20`；没有把产品定义的累加语义改成固定 20 秒。

## `rapidSeeksOnlyPublishCuesAtTheNewestCommittedPosition`

这是产品缺陷，不是测试时序假设错误。失败现场显示 1.25 秒旧请求被正确取代，3.5 秒最新请求在 video epoch 3 和 subtitle epoch 4 完成：

```text
318 subtitle.selection.completed trackID=ffmpeg.subtitle.1 cueCount=2
319 operation.seek.started
320 subtitle.cues.clearedForSeek subtitleEpoch=3
321 control.seek.started targetSeconds=1.25
328 control.seek.superseded targetSeconds=1.25
329 operation.seek.terminatedByCleanup
330 operation.seek.started
331 subtitle.cues.clearedForSeek subtitleEpoch=4
332 control.seek.started targetSeconds=3.5
1041 control.seek.completed targetSeconds=3.5 streamEpoch=3 subtitleStreamEpoch=4
1044 operation.seek.completed
```

紧接完成事件读取的 snapshot 显示 `lastVideoSample.presentationTimeSeconds` 为 3.667、subtitle suppression 已解除、所选轨道仍为 `ffmpeg.subtitle.1`，但 `rendererState.currentTimeSeconds` 为 0 且 rate 为 0。字幕查询按 synchronizer time 工作，所以它正确地按 0 秒返回空数组；错误在暂停 seek 没有提交时间轴。

`SampleBufferPlaybackSession+Delivery.swift` 现在在 decoder bootstrap 完成且目标已到达时，若 rate 为 0 且当前操作是 seek，就用既有的 `pausedTimelineActivationTime` 选择目标或首个可显示帧位置，调用 `setTimelineStopped(at:)`，结束 seek preroll，并发布目标时间轴状态。限定当前操作为 seek 的代价是普通暂停打开不会提前结束 preroll；这正是 `pausedPrerollDoesNotScheduleAHostTimeRateZeroActivation` 固定的既有行为。字幕测试的 `activeSubtitleCues == ["再见"]` 断言没有修改，修复生产代码后通过。

## 验证与决策代价

修复前的完整基线是 203 个测试、13 个 issue。五项定向失败均通过临时订阅 `debugEvents()` 和读取 `debugSnapshot()` 取得上述序列；临时打印代码没有保留在最终 diff 中。

修复后，五项定向运行以 5 个测试全部通过结束。随后运行覆盖 seek、subtitle 和暂停 preroll 的 29 项相邻测试，29 项全部通过。最终执行完整 `swift test`，五项分别在 0.703、0.880、0.937、0.926 和 1.016 秒通过，完整运行在 1.462 秒结束。

测试 fixture 新增可达样本和最终占位样本的代价是这四项不再覆盖“首个样本远离时间轴”与“到达媒体末尾”。那两个行为已有 bounded lead、首帧 watchdog 和 end 状态的独立测试；把它们留在本簇只会阻止 supersession 与相对累加断言到达。生产修复的行为变化是暂停 seek 在目标帧可用后立即提交停止的 synchronizer 位置，字幕和其他按当前媒体时间计算的消费者会看到最新位置；播放 seek、普通暂停打开和 seek-to-end 分支不变。

`git diff --check` 通过。修改范围只有 `Packages/PlaybackCore/Sources/PlaybackCore/SampleBufferPlaybackSession+Delivery.swift` 与 `Packages/PlaybackCore/Tests/PlaybackCoreTests/PlaybackCoreTests.swift`，没有触碰任务排除的三个基线失败，也没有修改 `PlaybackFFmpegBridge.c`。

## 最终一次 `swift test` 的失败名单原文

```text
􀢄  Test appleMVHEVCFixtureIsDistinguishedFromOrdinaryHEVC() recorded an issue at PlaybackFFmpegBridgeTests.swift:533:32: Expectation failed: reader
􀢄  Test appleMVHEVCFixtureIsDistinguishedFromOrdinaryHEVC() failed after 0.213 seconds with 1 issue.
􀢄  Test appleImmersiveProviderClassifiesSourceWithoutReplacingMismatchedBridgeFormat() recorded an issue at PlaybackFFmpegBridgeTests.swift:563:2: Caught error: .ffmpeg("Open media source: No such file or directory (-2)")
􀢄  Test controllerRejectsSecondOpenAndRecordsTheRejection() recorded an issue at PlaybackCoreTests.swift:510:5: Expectation failed: first.debugSnapshot().platform == "visionOSSimulator"
􀢄  Test controllerRejectsSecondOpenAndRecordsTheRejection() recorded an issue at PlaybackCoreTests.swift:511:5: Expectation failed: first.debugSnapshot().hardwareDisplayFacts == .notAvailable
􀢄  Test appleImmersiveProviderClassifiesSourceWithoutReplacingMismatchedBridgeFormat() failed after 0.426 seconds with 1 issue.
􀢄  Test controllerRejectsSecondOpenAndRecordsTheRejection() failed after 0.456 seconds with 2 issues.
􀢄  Test run with 203 tests in 3 suites failed after 1.462 seconds with 4 issues.
Note: Some test targets reported failures:
  - PlaybackCoreTests (XCTest)
  - PlaybackCoreTests (Swift Testing)
```
