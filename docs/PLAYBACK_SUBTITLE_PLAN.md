# 字幕车道方案

本文是字幕工作的唯一验收依据。状态变化时更新本文，不另开文档。

## 一、当前成立的事实

共享源。音频与视频共用一个解复用源。该源有一个读取位置，并为每条非视频流保留包历史：每流上限二十四兆字节或六十秒，取先到者。

字幕有位置。字幕读取器创建时接收起始时间。源从保留的历史中取出不早于该时间的包交给读取器。连续播放实测：产出帧的显示区间包含播放时钟。

```
subtitle.frame.produced at=114.200 range=112.946-114.364
```

订阅可转交。一条流允许新主人接管。旧主人释放时，若令牌不匹配，不改变新主人的订阅。

两种字幕共用一个读取器。内嵌文字轨与位图轨均从同一条流读取包。文字轨解为「时间 → 文字」清单，位图轨解为图片与显示区间。

首句字幕在 70.404 秒。该值来自内容，不是缺陷。无台词区间不存在字幕包，读取器在该区间保持空闲属正常行为。

跳转后挂载于目标时间。实测跳转至 109.067 秒：一秒内收到第一个包 110.505，五秒内覆盖 110.505 至 119.364。

```
subtitle.lane.attached track=ffmpeg.subtitle.10 at=109.067 cues=0 renderer=true
subtitle.frame.idle at=110 ingested=1 packetSpan=110.505..110.505
subtitle.frame.idle at=115 ingested=12 covered=110.505..119.364
```

字幕出现时刻与显示区间的起点相差不超过 0.09 秒。连续播放取样八段字幕，差值依次为 0.07、0.02、0.02、0.04、0.09、0.00、0.03、0.05 秒。

字幕重算有独立节拍。会话以一百毫秒挂钟周期按时间线位置重算并发布，节拍不取视频交付事件。实测连续播放发布间隔中位数 0.100 秒；跳转后 rate 为 0 的窗口内间隔 0.100 至 0.107 秒，仅跳转拆建期间出现一次 0.406 秒的间隔。

字幕帧到达窗口平面。窗口表面与沉浸表面都显式监听帧标识变化。实测连续跳转三轮，十个单元各在帧回调后 0.00 至 0.04 秒应用到实体平面；去掉该监听后同一场景有两个单元只产出未上屏，另一单元的呈现延迟为 1.64 秒。

## 二、目标一：字幕的挂载点等于请求时间

行为。选中字幕、恢复播放、跳转之后，字幕读取器持有的包覆盖请求时间，不从订阅时刻开始。

观测。日志 `subtitle.lane.attached` 记录挂载位置与条数。日志 `subtitle.frame.idle` 的 `covered` 下界不早于请求时间减一秒。

失败。`covered` 下界比请求时间早一秒以上。或挂载后三秒内 `ingested` 保持为零。

结构。读取器的起始时间只有一个来源：会话传入的时间线位置。

现状。成立。连续播放与跳转后均成立。

## 三、目标二：跳转之后字幕继续投递

行为。跳转完成后，字幕包继续到达读取器，字幕随播放继续显示。

观测。跳转后三秒内 `ingested` 增长。`covered` 上界不早于播放时钟。该时刻存在字幕时，`subtitle.frame.produced` 的 `at` 落在该帧显示区间内。

失败。跳转后十秒内 `ingested` 不增长。或 `covered` 不与时钟同步移动。

结构。跳转开始时会话释放旧的字幕读取器并置抑制位；重建完成后新的读取器以目标时间为起点接管同一条流，安装时清除抑制并递增选择代次，过期重建被丢弃。

现状。成立。跳转后字幕随播放显示，窗口平面在帧变化后更新。

```
subtitle.lane.attached track=ffmpeg.subtitle.10 at=112.195 cues=0 renderer=true
subtitle.frame.produced at=114.000 range=112.946-114.364
```

读取器在跳转后由会话重建，起始时间取时间线位置。重建时接管同一条流；旧主人释放不影响新主人的订阅。

## 四、目标三：回归目录

行为。回归目录中存在一个场景覆盖「跳转之后字幕继续跟随」，其结构测试指向上面的会话级测试。

观测。`materialize_catalog_v2.py --check Regression` 通过。场景计数由 69 变为 70，rubric 由 106 变为 107，静态用例由 118 变为 119。

失败。场景存在但结构测试名不在允许清单内。或目录与蓝图不一致。

结构。场景只引用已存在的操作与判定。结构化断言字段与测试打印的字段一致。

现状。成立。会话级测试打印的结构化断言：

```
ENCHRON_ASSERTION {"assertion":"subtitle-follows-seek","check":"subtitle-lane-seek","seekTargetSeconds":2.000,"cueCount":1,"cueText":"再见"}
```

## 五、不变量

以下五项在每次改动后重跑，全部成立才算通过。

一，连续播放：任取一分钟，`subtitle.frame.produced` 的 `at` 落在该帧显示区间内。实测八段字幕，差值为 0.00 至 0.09 秒。

二，字幕开关：开启、关闭、再开启后，字幕恢复显示，音频不中断。实测关闭后再开启，字幕在 194.600 秒重新出现，`lifecycle=playing`。

三，切换字幕轨：切换后字幕按新轨显示，播放不中断。实测切换至法语轨后，字幕在 300.900 秒出现，`lifecycle=playing`。

四，音视频：字幕改动不影响起播、跳转、换音轨、停顿恢复。起播、跳转、换音轨在实机上成立。停顿恢复由两个看门狗单元测试覆盖：`displayStallRebuffersTheTimelineWithStarvedContinuity` 与 `aSourceThatNeverAdvancesFailsFromLoadingAsStalled`。

五，失败归属：字幕读取失败不使会话失败。音频或视频失败按既有归属处理。本轮执行 `failedExternalSubtitleSourceLeavesTheCurrentSelectionAndSessionUntouched`、`anExternalSubtitleWhoseCuePreparationFailsNeverBecomesAvailable`、`aSubtitleDocumentCutOffMidReadFailsInsteadOfReturningAShorterTrack`，三项通过。

## 六、未决

一，停顿恢复未在实机上复现。`throttle` 与 `setSourceReadDelay` 对该播放路径不生效：限速 0.001 Mbps 时管线吞吐为 1.22 MB/s；读取延迟 20 秒时位置继续推进；看门狗阈值降至 1 毫秒时不进入 `stalled`。现以单元测试为准。实机复现需要能中断管线读取的钩子，或一个低速源。

二，位图轨的三维左右眼映射未验证。

三，外挂字幕文件路径本次未改动，未复测。

四，单元档三条与字幕无关的失败未归属：`a seek back from ended still enters the seeking stage`、`unclassified failures do not become a public active category`、`unknown source length uses chunked transfer and disables seeking`。

## 七、验证入口

单元档。`console tier unit`。当前该档为红，三条失败与字幕无关，见第六节第四条。

实机路径。模拟器 UDID `7619BD56-B81A-44E1-B3DC-912FB3019E7E`。通过应用命令通道执行 `openSourceFile`、`playDiscTitle`、`answerResumePrompt`、`selectSubtitleTrack`、`seekNormalized`、`playbackProbe`，再用 `log show` 读取 `subtitle.*` 日志。

呈现实测。`log show` 同时取 `com.xiongzhipeng.PlaybackCore` 与 `app.enchron` 两个子系统。`subtitle.frame.produced` 给出产出时刻与显示区间，`subtitlePixelMapping` 给出帧应用到实体平面的时刻，两者按相邻时间配对得到应用延迟。截图给出像素证据。只统计产出的日志不能判定呈现。
