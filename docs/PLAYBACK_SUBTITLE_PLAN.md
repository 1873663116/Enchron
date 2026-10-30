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

片头无字幕是内容事实。该盘第一句字幕在 70.4 秒，之前没有包。

## 二、目标一：字幕的挂载点等于请求时间

行为。选中字幕、恢复播放、跳转之后，字幕读取器手里的包覆盖请求时间，而不是从订阅那一刻开始。

观测。日志 `subtitle.lane.attached` 记录挂载位置与条数；日志 `subtitle.frame.idle` 的 `covered` 下界不早于请求时间减一秒。

失败。`covered` 的下界比请求时间早出一秒以上；或挂载后三秒内 `ingested` 一直为零。

结构。读取器的起始时间只有一个来源：会话传入的时间线位置。

现状。连续播放成立。跳转后未成立：读取器按新位置重建成功，但收不到包。

```
subtitle.lane.attached track=ffmpeg.subtitle.10 at=620.286 cues=0 renderer=true
subtitle.frame.idle at=620 ingested=0 queue=empty/1
subtitle.frame.idle at=635 ingested=0 queue=empty/1
```

## 三、目标二：跳转之后字幕继续投递

行为。跳转完成后，字幕包继续到达读取器，字幕随播放继续显示。

观测。跳转后三秒内 `ingested` 增长；`covered` 的上界在播放时钟之前不少于一秒；该时刻有字幕时 `subtitle.frame.produced` 的 `at` 落在帧的显示区间内。

失败。跳转后十秒内 `ingested` 不增长；或 `covered` 不与时钟同步移动。

结构。跳转只移动源的位置，不改变订阅关系：一条流在跳转前后属于同一个主人。

现状。未成立。读取线程在工作（`demuxReadFrames` 持续增长），但该流队列始终为空（`queue=empty/1`）。

需要查清的方向：跳转是否重建了容器的流映射，使原流编号在新位置不再承载字幕包。

## 四、目标三：回归目录

字幕在两个验收目标完成后更新回归目录：新增或改写覆盖「跳转后字幕跟随」的场景，并把结构化断言接入现有测试。执行时机在目标一、目标二之后。

## 五、不变量

以下五项在每次改动后重跑，全部成立才算通过。

一，连续播放：任取一分钟，`subtitle.frame.produced` 的 `at` 落在该帧显示区间内。

二，字幕开关：开启、关闭、再开启后，字幕恢复显示，音频不断。

三，切换字幕轨：切换后字幕按新轨显示，播放不中断。

四，音视频：字幕改动不影响起播、跳转、换音轨、停顿恢复。

五，失败归属：字幕读取失败不使会话失败；音频或视频失败仍按既有归属处理。

## 六、未决

一，跳转后该流不再投递的根因未定位。

二，位图轨的三维左右眼映射未验证。

三，外挂字幕文件路径本次未改动，未复测。

## 七、验证入口

单元档。`console tier unit`。当前该档为红，三条失败与字幕无关，记录在案：

```
a seek back from ended still enters the seeking stage       EnchronDomainTests
unclassified failures do not become a public active category EnchronDomainTests
unknown source length uses chunked transfer and disables seeking EnchronDomainTests
```

其中第三条所在的测试文件在本工作树中被另一工作流修改，未提交。

实机路径。模拟器 UDID `7619BD56-B81A-44E1-B3DC-912FB3019E7E`，通过应用命令通道执行 `openSourceFile`、`playDiscTitle`、`answerResumePrompt`、`selectSubtitleTrack`、`seekNormalized`、`playbackProbe`，再用 `log show` 读取 `subtitle.*` 日志。
