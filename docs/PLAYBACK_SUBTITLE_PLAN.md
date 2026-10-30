# 字幕车道方案

本文是字幕工作的唯一验收依据。状态变化时更新本文，不另开文档。

## 一、当前成立的事实

共享源。音视频共用一个解复用源：它有一个读取位置，并保留每条非视频流的包历史，每流最多二十四兆字节或六十秒，先到者为准。

字幕有位置。字幕读取器创建时接收起始时间，源从保留的历史里把不早于该时间的包补给它。实测：连续播放时产生的字幕帧属于包含播放时钟的显示区间。

```
subtitle.frame.produced at=114.200 range=112.946-114.364
```

订阅可换主人。一条流允许新主人接管；旧主人释放时，若令牌不匹配则不动新主人的订阅。

两种字幕共用一个读取器。内嵌文字轨与位图轨都从同一条流读包：文字轨解成「时间 → 文字」清单，位图轨解成图片窗口。

片头无字幕是内容事实。该盘第一句字幕在 70.4 秒，之前没有包。同样，字幕只出现在有台词的区间；区间之间没有包，读取器在那段时间里保持空闲是正常的。

跳转后挂在目标时间。实测跳到 109.067 秒，读取器一秒内收到第一包 110.505，五秒内覆盖 110.505 到 119.364。

```
subtitle.lane.attached track=ffmpeg.subtitle.10 at=109.067 cues=0 renderer=true
subtitle.frame.idle at=110 ingested=1 packetSpan=110.505..110.505
subtitle.frame.idle at=115 ingested=12 covered=110.505..119.364
```

字幕出现的时刻与显示区间的起点相差不超过 0.09 秒。连续播放中取八段字幕，首帧出现时刻与区间起点之差分别是 0.07、0.02、0.02、0.04、0.09、0.00、0.03、0.05 秒。

## 二、目标一：字幕的挂载点等于请求时间

行为。选中字幕、恢复播放、跳转之后，字幕读取器手里的包覆盖请求时间，而不是从订阅那一刻开始。

观测。日志 `subtitle.lane.attached` 记录挂载位置与条数；日志 `subtitle.frame.idle` 的 `covered` 下界不早于请求时间减一秒。

失败。`covered` 的下界比请求时间早出一秒以上；或挂载后三秒内 `ingested` 一直为零。

结构。读取器的起始时间只有一个来源：会话传入的时间线位置。

现状。成立。连续播放与跳转后都成立，实测见第一节。

先前记录「跳转后收不到包」的那次观察是在 620 秒处，该区间没有字幕包，不是缺陷。

## 三、目标二：跳转之后字幕继续投递

行为。跳转完成后，字幕包继续到达读取器，字幕随播放继续显示。

观测。跳转后三秒内 `ingested` 增长；`covered` 的上界不早于播放时钟；该时刻有字幕时 `subtitle.frame.produced` 的 `at` 落在帧的显示区间内。

失败。跳转后十秒内 `ingested` 不增长；或 `covered` 不与时钟同步移动。

结构。跳转只移动源的位置，不改变订阅关系：一条流在跳转前后属于同一个主人。

现状。成立。跳转后包继续到达，字幕继续显示。

```
subtitle.lane.attached track=ffmpeg.subtitle.10 at=112.195 cues=0 renderer=true
subtitle.frame.produced at=114.000 range=112.946-114.364
```

读取器在跳转后由会话重建，起始时间取时间线位置；重建接管同一条流，旧主人释放不影响新主人的订阅。

## 四、目标三：回归目录

行为。回归目录里有一个场景覆盖「跳转之后字幕继续跟随」，结构测试指向上面的会话级测试。

观测。`materialize_catalog_v2.py --check Regression` 通过；场景计数从 69 变为 70、rubric 从 106 变为 107、静态用例从 118 变为 119。

失败。场景存在但结构测试名不在允许清单里；或目录与蓝图不一致。

结构。场景只引用已存在的操作与判定；结构化断言字段与测试打印的字段一致。

现状。成立。目录已更新并校验通过：场景计数 69 → 70，rubric 106 → 107，静态用例 118 → 119，`materialize_catalog_v2.py --check Regression` 通过，目录自检 49 项通过，四条回归规则通过，`console tier static --code-only` 通过。

会话级测试打印的结构化断言：

```
ENCHRON_ASSERTION {"assertion":"subtitle-follows-seek","check":"subtitle-lane-seek","seekTargetSeconds":2.000,"cueCount":1,"cueText":"再见"}
```

目录写入被三处固定计数挡住，改动它们是受评审的契约变更，本轮未做：

```
Scripts/regression/materialize_catalog_v2.py:1331   64 Promises / 69 Scenarios
Scripts/regression/completion.py:74,77              69 scenarios / 106 rubrics
Scripts/rules/tests/test_regression_catalog_v2_materializer.py   69 / 118 等五处
```

## 五、不变量

以下五项在每次改动后重跑，全部成立才算通过。

一，连续播放：任取一分钟，`subtitle.frame.produced` 的 `at` 落在该帧显示区间内。实测八段字幕，差值 0.00 到 0.09 秒。

二，字幕开关：开启、关闭、再开启后，字幕恢复显示，音频不断。实测关闭后再开启，字幕在 194.600 秒重新出现，`lifecycle=playing`。

三，切换字幕轨：切换后字幕按新轨显示，播放不中断。实测切到法语轨后字幕在 300.900 秒出现，`lifecycle=playing`。

四，音视频：字幕改动不影响起播、跳转、换音轨、停顿恢复。起播、跳转、换音轨在实机上成立。停顿恢复以两个看门狗单元测试为准：`displayStallRebuffersTheTimelineWithStarvedContinuity` 与 `aSourceThatNeverAdvancesFailsFromLoadingAsStalled`，本轮两项通过。实机复现受阻的原因见第六节第一条。

五，失败归属：字幕读取失败不使会话失败；音频或视频失败仍按既有归属处理。

## 六、未决

一，停顿恢复未在实机上复现。`throttle` 与 `setSourceReadDelay` 对这条播放路径都不生效：限速 0.001 Mbps 时管线吞吐仍是 1.22 MB/s，读取延迟 20 秒时位置照常推进；看门狗阈值降到 1 毫秒也不进入 `stalled`。停顿恢复因此以单元测试为准，见第五节第四条。需要一条能真正中断管线读取的钩子，或者一个真正慢的源，才能做实机复现。

二，位图轨的三维左右眼映射未验证。

三，外挂字幕文件路径本次未改动，未复测。

四，单元档三条与字幕无关的失败未归属：`a seek back from ended still enters the seeking stage`、`unclassified failures do not become a public active category`、`unknown source length uses chunked transfer and disables seeking`。

## 七、验证入口

单元档。`console tier unit`。当前该档为红，三条失败与字幕无关，记录在案：

```
a seek back from ended still enters the seeking stage       EnchronDomainTests
unclassified failures do not become a public active category EnchronDomainTests
unknown source length uses chunked transfer and disables seeking EnchronDomainTests
```

其中第三条所在的测试文件在本工作树中被另一工作流修改，未提交。

实机路径。模拟器 UDID `7619BD56-B81A-44E1-B3DC-912FB3019E7E`，通过应用命令通道执行 `openSourceFile`、`playDiscTitle`、`answerResumePrompt`、`selectSubtitleTrack`、`seekNormalized`、`playbackProbe`，再用 `log show` 读取 `subtitle.*` 日志。
