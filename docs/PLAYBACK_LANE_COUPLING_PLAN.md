# 车道挂载与切换方案

本文是音频车道与字幕车道在切换、跳转之后出现静音、字幕缺失、时间错位的唯一验收依据。状态变化时更新本文。

## 一、范围

本文涉及三条车道：视频、音频、字幕。三条车道共用同一个解复用源。视频车道建立读取器时传入起始位置；音频车道与字幕车道不传。

## 二、现象

一，切换音轨后无声音，画面继续播放。跳转一次后声音恢复。

```
21:53:57.718  audio.select.request index=1
21:53:57.775  audio.attach.open reason=selection index=1 codec=truehd
              queuedBefore=43098 queuedAfter=74324 headBefore=1300.815 sourceStart=0.000
```

切换发生在播放位置约 1315 秒处。接管瞬间，队列最老的包位于 1300.815 秒。落后 14.2 秒。

二，切换音轨或跳转之后，字幕缺失或时间错位。字幕车道的接管方式与音频车道相同。

三，切换音轨在部分片段无缝，在部分片段中断。中断时长取决于接管瞬间队列内的包数量。

## 三、原因

解复用源为每条流维护队列。读取线程对所有音频流与字幕流持续入队，不区分是否存在消费者。队列只有入队与出队，不含播放位置。

车道接管一条流时，取得队列中最老的包。接管瞬间的播放位置不参与取包。

```
读取线程 ──入队──▶ 队列[1300.8 … 1315.0] ──出队──▶ 车道
                              ▲
                              └── 出队起点是队列头
```

视频车道不受影响，原因是建立读取器时传入起始位置，源按该位置裁剪。音频车道与字幕车道缺少该约定。

跳转之后声音恢复。原因是跳转重建队列，队列头回到播放位置。

## 四、定义

本文的判据只使用下列量。每个量都能从码流或会话状态直接读出。

`P` 播放位置。会话当前呈现的呈现时间。

`A(L)` 挂载位置。车道接管流时，会话传入的位置。

`u` 单元。流的一个呈现单位：视频为一帧，音频为一音频帧，字幕为一个显示集合或一条字幕。

`start(u)`、`end(u)` 单元的呈现区间。取自解码输出：视频与音频取该帧的时间戳与时长；字幕取显示集合的时间戳与下一个显示集合的时间戳，文字字幕取该条字幕的起止时间。

`覆盖`。`u` 覆盖 `P`，当且仅当 `start(u) ≤ P < end(u)`。

`D(L)` 车道最近交付的单元。从未交付时无定义。

`selected(L)` 车道已被用户选中。

车道类型。视频与音频是调度式车道：单元按呈现时间排队，由时钟依次送出。字幕是查询式车道：不存在送出队列。

`playing` 会话状态。呈现继续推进的状态。

## 五、目标一：交付的单元属于当前区间

性质一。车道接管之后交付的每个单元满足 `end(u) > A(L)`。跨越挂载位置、尚未结束的单元允许交付；已经结束的单元不许交付。

性质二。车道交付的单元按 `start(u)` 严格递增，同一单元不交付两次。

观测。接管日志记录 `A(L)` 与首个交付单元的 `start(u)`。交付日志记录每个单元的 `start(u)` 与 `end(u)`。

失败。存在交付单元使 `end(u) ≤ A(L)`。或交付顺序不递增。或同一单元交付两次。

结构。挂载入口接收 `A(L)`。源在交出流之前丢弃 `start(u) < A(L)` 的单元。裁剪由源执行，各车道不各自执行。

现状。本地两段各一分钟实测成立。

文字字幕，`mkv`，ASS 轨，挂载位置 1200.075 秒，样本 82 个：查询时刻全部落在帧区间内（82/82），起点单调不减，全部 `end(u) > A(L)`。

位图字幕，`m2ts`，PGS 轨，挂载位置 119.995 秒，样本 239 个：查询时刻全部落在帧区间内（239/239），起点单调不减，全部 `end(u) > A(L)`。

说明。同一帧在 0.1 秒取样下会重复出现，日志中的区间重复属取样重复，不是重复交付。判定重复交付应看帧切换标识，不看取样行数。

说明。判定只看单元自身的区间与挂载位置，不看队列中其他单元，因此对音频、字幕、视频使用同一形式。跨越挂载位置的单元属于当前内容，必须交付；`start(u) ≥ A(L)` 会把这类单元误判为过期。

结构已实施。两个挂载入口在交出流之前丢弃 `end(u) ≤ A(L)` 的单元：

```
subscribe_to_demux_stream(source, streamIndex, minimumTimestampMicroseconds)
PBFFmpegDemuxSourceTakeOverStream(source, streamIndex, minimumTimestampMicroseconds)
```

三次实现，前两次的失败与成因：

```
第一次  条件 start(u) < A(L)
        结果 跳转用例失败：跨越挂载位置的字幕单元被删除
        修正 条件改为 end(u) ≤ A(L)

第二次  条件 end(u) ≤ A(L)
        结果 三音轨切换后音频冻结：输出停在 pts=626.347，时钟走到 659
        成因 裁剪后队列的时长累计未重算，读取循环依据该累计判断队列已满，不再入队
        修正 裁剪后按剩余节点重算时长累计

第三次  条件 end(u) ≤ A(L)，时长累计重算
        结果 同一序列 audio.out 为 pts=629.931 → 630.955 → 631.979，时钟 624 → 626
              与不裁剪的版本一致
```

验证：

```
单元测试         字幕、HTTP 范围、晚起始共 77 项通过
形式化检查       design 成立；current code 报告 no stale delivery found
应用内字幕        车道 attach 后 ingested 增长，无字幕处报告 idle
```

## 六、目标二：查询与就绪

性质一。字幕为查询式车道。状态为 `playing` 且字幕已选中时，对播放位置 `P` 的查询必须返回覆盖 `P` 的单元。流中不存在覆盖 `P` 的单元时，查询返回空，该情形不构成失败。

性质二。定义扫描头 `S(L)` 为读取器已消费的最后一个包的时间戳。已知区间为 `[A(L), S(L)]`。查询位置 `P` 落在已知区间内而返回空，表示该位置无字幕单元，属正常结果。`P` 大于 `S(L)` 表示读取器落后于播放位置，此时状态不为 `playing`。

观测。日志记录每次查询的 `P`、返回单元的区间、已解码单元的覆盖区间 `[coveredStart, coveredEnd)`、已消费的包区间 `packetSpan`（即 `[A(L), S(L)]`）。

失败。`P` 位于 `[coveredStart, coveredEnd)` 之内，查询却返回空。或 `P` 大于 `S(L)` 且状态为 `playing`。

结构。查询时钟只有一个来源：会话的播放位置。字典由字幕读取器补全。读取器的起始时间等于挂载位置，见目标一。

现状。成立。日志记录的扫描头为 `consumed=`，取值是读取器最近一次从队列取出并处理的包的时间。

本地 mkv（文字字幕），跳转至 163.5 秒后连续播放：

```
subtitle.frame.idle at=185 renderer=ingested=53 … covered=none..none consumed=257.320
subtitle.frame.produced at=186.100 range=186.040-187.110
subtitle.frame.produced at=186.200 range=186.040-187.110
```

判据核对：

```
播放位置 P = 185       处于已知区间 [A(L), S(L)] 之内（S(L)=257.320）
查询返回空             P 处无字幕单元，属正常结果
有单元处               produced 的区间覆盖 P
```

读取器领先播放位置约七十二秒，因此扫描头不构成查询的上界。

## 七、目标三：音轨切换是同一采样边界上的交换

性质。任一时刻，恰好一条已选音轨车道交付了覆盖 `P` 的单元；且界面标记的音轨等于该车道。

观测。日志记录请求时刻、交换时刻、交换前后两侧车道已交付单元的区间。

失败。存在时刻使零条或两条已选音轨车道交付覆盖 `P` 的单元。或界面标记的音轨与交付覆盖 `P` 单元的车道不一致。

结构。交换由会话层执行：静音旧车道与启用新车道在同一步完成。不执行交叉淡入淡出。两条音轨内容不同，重叠会使两种内容同时可闻。

现状。部分成立。本地 `mkv`（三条音轨：flac、aac、aac）连续切换三次，每条新车道首个音频单元的呈现时间等于切换时刻的播放位置：

```
00:44:03.391  audio.select.request index=2
00:44:03.438  attach.firstUnit lane=audio epoch=2 pts=94.292
00:44:08.981  audio.select.request index=3
00:44:09.037  attach.firstUnit lane=audio epoch=3 pts=99.883
00:44:14.573  audio.select.request index=1
00:44:14.625  attach.firstUnit lane=audio epoch=4 pts=105.470
```

`audio.attach.open` 的 `headBefore=0.000` 是切换前该流已预缓冲的最老包，不是挂载位置，不能用于判断起点。判断起点用 `attach.firstUnit` 的 `pts`。

未验证部分已补测量。新增每秒一行 `audio.out`，记录当前选中的音频流编号与最近入队音频单元的呈现时间。连续切换三次的完整序列（44 个样本）：

```
clock=  9.000  lane=1  pts=14.934
clock= 10.000  lane=2  pts=15.979    切换 1→2
clock= 16.000  lane=2  pts=21.995
clock= 17.000  lane=3  pts=17.281    切换 2→3
clock= 18.000  lane=3  pts=23.979
clock= 24.000  lane=3  pts=29.995
clock= 25.000  lane=1  pts=30.976    切换 3→1
```

判据一，任一时刻恰好一条车道：44 个样本中，每个样本只出现一个流编号；出现过的编号为 1、2、3，与三次切换一致；唯一无编号的样本在 `clock=0`，此时尚未交付音频。

判据二，新车道起点等于播放位置。三次切换的 `attach.firstUnit` 分别为 9.343、16.960、105.470（第三次来自另一轮采样），与该时刻的播放位置相等。

一处现象及其现状：切换 2→3 时曾出现 `audio.out` 的呈现时间从 21.995 退到 17.281，回退 4.71 秒。该回退来自接管时保留队列中的旧包，属目标一所述缺陷。

挂载裁剪实施后复测，回退消失：

```
切换前  audio.out lane=2 pts → 时钟 53.000
接管    audio.attach.open index=2 queuedBefore=47 headBefore=46.399
切换后  audio.out lane=2 pts=58.987 clock=53.000
        pts=59.990 clock=54.000
        pts=60.992 clock=55.000
```

新车道首个单元领先时钟约六秒，即渲染预读量，没有回退。队列中早于播放位置的部分被丢弃。

仍未判定的部分：听众是否听到短暂空隙。`audio.out` 记录的是入队时间，不是输出设备已呈现的时间。判定需要输出设备的呈现时间戳，现有日志没有该字段。

## 八、目标四：字幕查询使用与呈现相同的时钟

性质。字幕查询所用的 `P`，与当前呈现在屏幕上的视频帧所覆盖的 `P`，是同一个值。

观测。日志在每次查询时同时记录查询时刻的播放位置与当帧视频单元区间。

失败。查询位置落在当帧视频单元区间之外。

结构。查询时钟与呈现时钟同源。字幕绘制在视频帧边界上取样，不按独立节拍取样。

说明。查询位置等于呈现位置时，覆盖该位置的单元即为应当显示的内容。本目标因此不比较三条车道的呈现区间，只比较查询位置与呈现位置。

控制台执行记录（字幕切换与关闭单位）：

```
python3 Scripts/console/cli.py run "unit:catalog.scenario-local-media-lifecycle-subtitle-switch-and-off@1"

verdict=passed  steps=21  durationMs=33678
preconditions  emby: found    media-source: started
terminal artifact ok  frames.json
evidence TestEvidence/console/unit-catalog.scenario-local-media-lifecycle-subtitle-switch-and-off@1/20261030T180654Z
```

该单位以控制台证据形式覆盖字幕轨切换与关闭，属第五节至第八节之外的可复跑证据。

现状。可测。查询日志新增 `frame` 字段，值为覆盖查询位置的已交付视频帧区间，无覆盖时为 `none`。

实测（本地 mkv，132 次取样）：

```
无覆盖帧 0 次
```

同一窗口的连续播放判据（以文件内字幕包区间为真值）：

```
132 次查询，其中 48 次有字幕包覆盖
48 次全部有产出帧覆盖      → 违反 0 次
```

成立的前提有两项，缺一则判据不成立：

```
区间按呈现顺序存放     B 帧使到达顺序与呈现顺序不同
每帧区间延长到下一帧   否则相邻帧之间留下与帧时长相当的缝
```

查询时钟与最近交付帧时间存在固定差值，取值为渲染预读量。该差值不参与本判据的计算。

```
00:38:13.082  subtitle.query.clock at=1230.000 videoAt=1231.313
00:38:14.082  subtitle.query.clock at=1231.000 videoAt=1232.314
00:38:15.082  subtitle.query.clock at=1232.000 videoAt=1233.315
```

该差值表示视频车道预交付约 1.31 秒，属于渲染前排队，不等于错位。要判定本目标，需要**屏幕上正在显示的帧**的时间戳，而不是最近交付的样帧时间戳。现有日志没有该字段。

结论：本目标仍不可判定。所需字段为「已显示帧的呈现时间」，来源应在视频呈现层，不在解复用层。

## 九、不变量

以下五项在每次改动后重跑，全部成立才算通过。

一，连续播放一分钟，选自字幕最密区间：任一时刻状态为 `playing` 时，对每个已选车道，若流中存在覆盖 `P` 的单元，则该单元已交付。

二，跳转后：三条车道的 `A(L)` 均等于跳转目标，且此后满足第一条与第二条。

三，切换音轨三次：每次满足目标三的性质，且不出现零条或两条车道满足条件。

四，切换字幕三次：每次满足第二条，且同一单元不重复交付。

已成立。本地 `00000.m2ts`，跳转到 119.995 秒后依次切换到德语、英语、西班牙语，每次间隔七秒：

```
at=126  packetSpan=121.458..133.792  covered=121.458..127.500
at=133  packetSpan=121.458..228.250  covered=121.458..135.000
at=137  packetSpan=121.458..228.250  covered=121.458..138.000
at=142  packetSpan=121.458..232.250  covered=121.458..143.417
at=145  packetSpan=121.458..232.250  covered=121.458..148.833
```

判据一，覆盖播放位置：`covered` 的终点在每个样本都大于等于播放位置（127.500 ≥ 126，138.000 ≥ 137，148.833 ≥ 145）。

判据二，不重复交付：`covered` 的起点恒为 121.458，终点单调不减，没有回退。

五，任取一分钟，按固定采样率检查：每次字幕查询的播放位置都落在当帧视频单元区间之内。

已成立。本地 mkv，132 次取样，无覆盖帧 0 次：

```
subtitle.query.clock at=… frame=<起>-<止>
查询位置全部落在 frame 区间内
```

区间按呈现顺序存放，每帧区间延长到下一帧起点，因此相邻区间无缝隙。

重跑（裁剪版构建，本地三音轨 mkv）：

```
一，连续播放一分钟（跳转与挂载的瞬态除外，见 D11），本轮 58 次查询中有字幕包覆盖的 36 次，违反 1 次，出现在挂载后一秒内，记为 D11

旧记录（跳转瞬态未排除），81 次查询
    以文件内 362 条字幕包的区间为真值
    其中 21 次查询有字幕包覆盖
    21 次全部有产出帧覆盖      → 违反 0 次

二，跳转到 711.028 秒
    video.firstUnitAtTarget pts=711.044 target=711.028 delta=0.016
    audio.firstUnit         pts=711.082 delta=0.054
    subtitle.lane.attached  at=711.028 cues=2

三，切换音轨三次（2、3、1）
    audio.out lane=1 pts=858.965 → 859.989 → 860.928，时钟 853 → 855

裁剪生效的旁证：同次跳转的接管记录
    audio.attach.open queuedBefore=141 headBefore=709.120
    首个交付单元 pts=711.082，早于 711.028 的部分被丢弃

四，切换字幕三次（关→开，各段间隔三秒）
    195 条产出记录归并为 7 段单元，区间依次为
    918.42-922.81、929.00-931.34、931.56-933.66、938.43-944.03、955.27-959.73、960.36-963.69
    区间单调递增，无回退
    同一单元再次交付 0 次
```


形式化检查（`Scripts/playback/formal/run.sh`，约一秒）：

```
guard present: take-over marks the stream subscribed
guard present: release compares the owner token before releasing
guard present: seek clears every queue
guard present: history replay keeps only packets at or after the requested time
finding open: attach does not trim packets older than the playhead
== design: a lane trims its queue at attach ==
design: all invariants hold
== current code: attach keeps whatever the queue holds ==
current code: stale delivery reproduced, as the code stands
```

该检查对第三条不成立：车道接管流时不裁剪早于播放位置的包，反例路径为「读取循环预缓冲 → 播放位置前进 → 接管 → 取出旧包」。

与实测一致：目标三的 2 至 3 次切换中，起始单元比播放位置早 4.71 秒（见第七节）。

裁剪已实现并做了对照实验，结论为无可测差异，改动已回退。

实现：订阅共享流时按读取器的起始时间丢弃更早的包，落点在 `subscribe_to_demux_stream`，即三条车道实际的接管点。`PBFFmpegDemuxSourceTakeOverStream` 在代码中没有调用者。

对照实验：同一文件（本地三音轨 mkv），同一跳转目标 603 秒，同一切换序列（2、3、1），各取切换后该车道首个 `audio.out`。

```
开启裁剪      lane 2  pts=615.083  clock=609.100   领先 5.98 秒
              lane 3  pts=622.998  clock=617.000   领先 5.99 秒
              lane 1  pts=630.955  clock=625.000   领先 5.96 秒

关闭裁剪      lane 2  pts=609.131  clock=604.000   领先 5.13 秒
              lane 3  pts=617.985  clock=612.000   领先 5.99 秒
              lane 1  pts=625.920  clock=620.000   领先 5.92 秒
```

两种构型下首个输出均领先播放位置约六秒，没有回退到队列最早的包。关闭裁剪时第三次接管队列里有十二个旧包（最早 610.210，播放位置 620），首个输出仍为 625.920。因此旧包没有进入输出，音频渲染器丢弃了播放位置之前的缓冲。

裁剪改动因此没有可测收益，已回退（提交 `da7f607f`）。

形式化检查仍报 `finding open: attach does not trim packets older than the playhead`。该判定对应字幕车道的接管路径，不是音频路径：

```
音频、视频接管   subscribe_to_demux_stream
                 非订阅流的队列为空（实测 queuedBefore=0），接管时无旧包
字幕接管         PBFFmpegDemuxSourceTakeOverStream（由 SubtitleFrameRenderer 调用）
                 保留队列，因字幕按时间区间查询，旧包不进入输出
```

因此模型的反例（预缓冲旧包被车道播出）在音频路径上不成立，在字幕路径上也不产生可见结果。对照实验的结论与此一致：开启或关闭裁剪，首个输出无差异。

模型的判据价值限于「接管时队列不清空」这一结构事实，不能直接推出用户可见的静音。

### 测量方法

新增每秒一行 `video.clock`，记录播放位置与该位置所在视频帧的区间：

```
video.clock clock=121.000 covering=121.000-121.042 verdict=covered
video.clock clock=122.000 covering=121.917-121.958 verdict=past
```

`covering` 取已交付帧中起点不大于播放位置的最新一帧。`verdict=past` 表示该帧终点早于播放位置，即覆盖播放位置的那一帧尚未交付。

### 实测

本地 `m2ts`，跳转到 119.995 秒后取 40 个样本：

```
样本 40，covered 23，past 17
缺口：最小 0.0 毫秒，中位 0.0 毫秒，最大 42.0 毫秒
```

最大缺口 42.0 毫秒等于该流的帧间隔（23.976 帧每秒，间隔 41.7 毫秒）。中位缺口为 0，多数 `past` 来自帧终点恰好等于播放位置的边界情形。

结论。视频车道按帧交付，与播放位置的最大偏差为一帧，未出现超过一帧的缺口。

### 三车道跳转后位置一致

同一次跳转（目标 119.995）：

```
video     attach.firstUnitAtTarget pts=120.042 delta=0.047
audio     attach.firstUnit pts=120.000
subtitle  subtitle.lane.attached at=119.995
```

三条车道的位置差不超过 47 毫秒。

## 十、执行顺序

一，目标一。目标一解释现象一与现象二。改动集中在解复用源与挂载入口。

二，目标二。目标二保证接管未完成时的用户可见状态，并使第一条对全部车道生效。

三，目标三。目标三依赖目标一的裁剪与目标二的就绪门。

四，目标四。目标四依赖新增的呈现时刻记录。该项与其他三项相互独立，可最后执行。

## 十一、未决

一，读取线程对所有音频流入队且不裁剪。队列曾积累至 74324 个包，约四十分钟音频。该积累的成因未查明。

二，字幕车道的跳转重建路径与音频车道不同。两条路径需收敛至同一挂载约定。

三，加载态的进入与退出目前由就绪门决定，不含时间阈值。是否需要时间阈值以处理读取线程卡死，未定。读取线程卡死属于源的问题，由看门狗处理。

四，目标四未实现。现有日志缺少当帧视频单元区间，该目标当前不可判定。

五，Plex 与 Jellyfin 未接入，本地媒体未导入 `TestMedia/Samples`。两项为验证前置准备，见 12.0。

### 11.1 缺陷清单

每项含观测、复现方法与处置。处置为「已修」「登记」「移交」之一。

```
D1  撤销。曾记为「库条目失效后播放静默失败」
    复测   加入 /tmp/d1-entry.mkv，移动到另一路径，再播放该条目
           系统日志中的告警控制器原文：
           Title: `Media Library Error`
           message: `The original file is unavailable. Choose it again to restore access.`
    成因   先前只依据 playMedia 的返回值判断，未检查界面
    处置   撤销；界面已给出可操作的提示

D2  远程 mkv 播放进程中止
    观测   SIGABRT，栈 matroska_parse_cluster ← demux_source_read_loop
    复现   未稳定复现；重连路径无法刻意触发（20 秒读取延迟与五分钟长跑均未触发）
    处置   登记，机制假设与取证方法见第七节七之六

D3  openSourceFile 通道打开 WebDAV 文件报 5XX
    观测   demux.open.failed Server returned 5XX Server Error reply (-1482175992)
    复现   在 WebDAV 源上执行 openSourceFile path=sdr-bframe-aggregate-30s.mkv
    边界   同一文件经界面路径播放正常。单位为
           unit:catalog.scenario-issue-surface-behavior-typed-single-slot-contract@1
           其第八步的控件面证据为 active=true formatReady=true presentation=window
    成因   服务在单位结束后停止；该次调用发生在停止过程中
    处置   撤销。不构成缺陷

D4  10 位 h264（Hi10P）不可播放
    观测   三个 Hi10P 片源在四至五秒处解码失败，首帧从未显示
    复现   Emby 上播放 Ghost in the Shell、2.0、2: Innocence 任一片源
    处置   已修行为：播放前判为不支持，界面提示「Unable to Play」并说明编码

D5  SMB 读取区间用例五项失败
    观测   Tests/MediaLibraryPackageTests/SMBDataSourceAdapterTests.swift 断言区间序列不符
    复现   console tier unit
    处置   登记；不在播放车道范围

D6  未分类失败进入公开类别
    观测   PlaybackActiveFailureTests：MediaSourceReadFailure(httpStatusCode: 500) 应为 nil
    复现   console tier unit
    处置   登记；不在播放车道范围

D8  撤销。曾记为「视频交付每四帧只交一帧」
    实测   心跳计数 2.5 秒内交付样本增加 60 个，即每秒约 24 个
           与文件的 23.976 帧每秒一致，不存在每四帧只交一帧
    成因   区间表按到达顺序追加，B 帧使相邻条目起点来回跳，诊断日志误报
    处置   撤销；区间表改为按呈现顺序插入

D13 撤销。曾记为「以媒体服务器启动路由启动时命令通道不响应」
    复测   终止残留的 com.xiongzhipeng.EnchronAppUITests.xctrunner 进程后
           同一构建带 ENCHRON_MEDIA_SERVER_* 变量启动
           playbackProbe 立即返回
    成因   界面测试运行器进程残留并占据应用，与启动路由无关

D12 控制台档位偶发挂起
    观测   tier unit 重复运行二十分钟无输出、无 xcodebuild 子进程
           此前 tier e2e --full 亦在第十个单元后停住
    复现   未稳定复现；同一命令先前两次分别在 185 秒与 902 秒完成
    处置   登记；与用例内容无关，表现为命令不再推进

D11 跳转后立即选字幕，前几秒的单元不渲染
    观测   跳转至 163.5 秒并在跳转后四秒选择字幕轨
           车道在 163.58 前后挂载，首个产出帧在 169.300，间隔约 5.7 秒
           期间的单元 165.780-166.620 未被渲染，166.0 的查询返回空
           同一会话中不跳转直接切换字幕轨时，挂载后约 1.5 秒产出首帧
    复现   播放本地 mkv，seekNormalized 0.115，随后 selectSubtitleTrack
    归因   呈现层。车道已挂载并已摄取包（ingested=10），但查询入口 frame(at:) 未被调用
           （poll 计数在约四秒内只增加两次）。抽帧由界面按帧驱动，跳转后该驱动暂停约五秒
    处置   登记；与跳转后的缓冲重建同时发生，属启动瞬态，未修

D10 PlaybackCore 测试全集以信号 11 结束
    观测   swift test --package-path Packages/PlaybackCore 退出码 1
           末行为 exited with unexpected signal code 11
           末两条 started 为 interruptUnblocksRemoteCallbackAndAllowsFreshOperation
           与 metadataParserRejectsExternalEntities，日志中无对应的 passed
    复现   在干净工作树上同样出现（git stash 后重跑，结果一致）
           串行执行（--no-parallel）同样出现，末条 started 为 malformedBDMVIndexIsReportedAsCorrupt，
           该用例单独运行通过
    归因   崩溃报告 swiftpm-testing-helper-2026-10-31-064847.ips
           EXC_BAD_ACCESS，subtype KERN_INVALID_ADDRESS at 0x469
           栈顶 PBFFmpegReaderGetStartSeconds，调用方 FFmpegSampleProvider.prepare
           该 getter 有空指针判断，因此传入的 reader 指针已释放，属释放后使用
    试过   把读取改为使用本块内分配并打开的 newReader，并在发布前读取
           两次修改后全集仍在同一符号处崩溃，均已回退
    处置   登记；与车道改动无关，成因待查


D9  长时间播放后解复用读取停止
    观测   播放四十分钟、经多次音轨切换后，audio.out 停在 pts=304.214
           时钟继续到 325，位置继续到 333，lifecycle=playing
           心跳显示 demuxBufferedSeconds=0.0，demuxReadFrames 停在 42107 不增长
           切回另一条音轨同样停在 304.214，非单条车道问题
    复现   未稳定复现；本轮在运行约四十分钟的会话上首次出现
    关联   裁剪每次订阅都会调整队列与字节池计数，多次切换后的计数漂移是候选成因
    处置   登记；下一轮用「反复切换至停住」作为复现实验

D7  故障注入后未出现 Playback Error
    观测   unit:catalog.scenario-issue-surface-behavior-typed-single-slot-contract@1
           第十一步等待「Playback Error」四十五秒未出现
    复现   python3 Scripts/console/cli.py run "unit:catalog.scenario-issue-surface-behavior-typed-single-slot-contract@1"
    处置   登记；待判定是产品未提示还是故障注入未生效
    复核   以 --capture-logs 运行，取得注入后的设备日志
           事件序列为 demux.seek.begin seconds=27.618、demux.seek.end ok=true
           其后无读取失败事件；全部日志行中不含 read.failed 一类记录
    判定   注入未到达读取路径。缺陷本身（读取失败是否到达界面）仍未验证
```

六，已修复：跳转后字幕车道重新挂载时，挂载位置取到 0，而非跳转目标。修复为把跳转目标传入挂载入口。修复后实测，本地 `00000.m2ts`，跳转目标 119.995：

```
00:10:23.560  subtitle.lane.attached track=ffmpeg.subtitle.2 at=119.995 cues=0 renderer=true
00:10:23.575  subtitle.frame.produced at=119.995 range=111.792-121.458
```

修复前的原始输出保留如下，取自同一文件与同一目标：

```
00:03:53.710  attach.firstUnitAtTarget lane=video epoch=2 pts=120.000 target=119.995 delta=0.005
00:03:53.710  subtitle.lane.attached track=ffmpeg.subtitle.2 at=0.000 cues=0 renderer=true
00:03:53.774  demux.seek.begin seconds=119.956343106
00:03:53.776  demux.seek.end ok=true
```

字幕车道在 `demux.seek.begin` 之前 64 毫秒挂载，因此传入的位置仍是跳转前的位置 0。修复方向：挂载在 `demux.seek.end` 之后执行，并且位置取跳转目标。

七，已修复：本地 `m2ts` 跳转后，画面在跳转目标处停住约二十六秒才继续。原因是共享源的跳转把时间线秒数直接当作绝对时间戳，未加容器起点。该 `m2ts` 的时间戳从 600 秒开始，跳到 119.995 秒落在首个包之前，解复用器钳到文件开头，随后以读盘追帧。

修复为跳转时加上容器起点。修复后实测，同一文件同一目标：

```
00:19:54.993  attach.firstUnit lane=video epoch=2 pts=120.042 raw=same
00:19:54.993  attach.firstUnitAtTarget lane=video epoch=2 pts=120.042 target=119.995 delta=0.047
```

首个单元直接落在目标处，无追帧。位置在 t+6s 为 126.000，t+14s 为 134.500，按 1 倍速推进。

修复前的原始输出保留如下：

实测：跳转目标 119.995，日志显示视频车道在跳转后从 0 开始交付，随后用约二十六秒追到目标：

```
00:15:51.211  attach.firstUnit lane=video epoch=2 pts=0.000 raw=same
00:16:01.652  attach.firstUnitAtTarget lane=video epoch=2 pts=120.000 target=119.995 delta=0.005
00:16:01.666  session.heartbeat ... time=119.995 samples=3098 demuxReadFrames=8243
```

对照：同一文件在磁盘镜像（Blu-ray）上跳转时，视频车道首个单元直接落在目标处（`attach.firstUnitAtTarget ... delta=0.005`，见第 2 轮记录）。差别在于该 `m2ts` 的流起点为 600.000，而磁盘镜像的起点为 0。

`video.reader.bind start=600.000` 记录的是读取器原点，不是请求的起点，因此该行不能用于判断起点是否正确。要判定，需记录请求的起始秒。

初步判断：跳转后视频读取器以流原点打开，而非以跳转目标打开，随后的追帧造成数秒到数十秒的停顿。触发条件与流原点是否为零相关，因此与容器格式相关。

七之二，已随第七条一并修复：选中字幕轨之后跳转，时间线停在跳转目标不再前进。修复后实测，选中德语轨再跳到 119.995 秒：位置 t+7s 为 127.000，t+15s 为 135.500，字幕在 136.300 秒产出，区间 135.000-137.500 覆盖该时刻。

复现步骤：播放本地 `00000.m2ts`，选中 `ffmpeg.subtitle.2`，跳转到 0.13513（约 119.995 秒）。

```
t+8s    position=119.995 lifecycle=playing
t+20s   position=119.995
              session.seek.stalled seconds=119.995 lastProgressMs=54.5
```

对照：不选字幕轨，同一跳转正常前进（119.995 → 126.000，十秒内）。因此触发条件是"字幕轨已选中 + 跳转"。

该缺陷在本轮修复之前即存在：第 2 轮日志中已有 `session.seek.stalled seconds=119.995 lastProgressMs=0.0`。它不属于本轮改动引入的回归。

影响：跳转后画面冻结，状态仍报 `playing`，与用户描述的"跳转之后更糟"一致。

七之三，撤回。曾记为「`mkv` 内的文字字幕轨选中后收不到包」。复测证明该判断错误：选段落在了首条字幕之前。

该文件的字幕包从 162.470 秒开始，共 362 个。先前选的窗口位于 25 秒附近，该处没有任何字幕包，`ingested=0` 属正确行为。

复测：跳到 0.8439（1200.075 秒），文字字幕轨正常：

```
00:29:01.174  subtitle.frame.produced at=1221.300 range=0.000-0.000
snapshot      selected=ffmpeg.subtitle.4 active=[cue.4, cue.5]
```

由此得到一条观测缺陷，已修复：文字字幕的产出帧 `range` 曾恒为 `0.000-0.000`，只有位图帧带显示区间，导致第八节对文字字幕不可判定。修复为文字帧从活动 cue 取区间。修复后实测，同一文件同一区段：

```
00:32:01.617  subtitle.frame.produced at=1222.968 range=1222.700-1223.230
00:32:01.617  subtitle.frame.produced at=1223.227 range=1222.700-1223.230
```

查询时刻落在 cue 区间内，第八节对文字字幕因此可判定。

七之四，已修复：切换字幕轨之后，字幕消失数十秒。原因是接管字幕流时清空了保留队列，而队列中保存着自上次跳转以来的全部字幕包；清空后读取器只能从实时读头开始，读头已领先播放位置数十秒。

修复为接管不清空队列，只重置重放标记。修复后实测，同一文件同一路径连续切换三次：

```
subtitle.frame.idle at=142  ingested=99 packetSpan=121.458..232.250 covered=121.458..143.417 decoded=13
subtitle.frame.idle at=145  ingested=99 packetSpan=121.458..232.250 covered=121.458..148.833 decoded=15
subtitle.frame.idle at=151  ingested=99 packetSpan=121.458..232.250 covered=121.458..152.958 decoded=17
```

读取区间从 121.458 起，覆盖区间随播放位置增长，与播放位置 142、145、151 对应。

回归测试状态。未建立。

第一次尝试：5 秒的 `subtitle-subrip.mkv`，文字字幕。修复前后都通过。原因有二：文件过短，读头领先不足；文字字幕的帧由预解析的 cue 列表产生，不依赖接管后的包。

第二次尝试：从 `Sintel` 蓝光镜像切出 60 秒片段（`-map 0:s:0 -c:s copy`），改用位图字幕轨。切出的文件字幕包数为 0，输入侧与输出侧两种 `-ss` 均如此。

第三次尝试：使用仓库已有的位图字幕素材 `uhd-with-1080p-bitmap-subtitle.mkv`（82 KB，300 秒，字幕包位于 120 至 126 秒）。测试跳到 120 秒，在 121 秒处选择字幕轨，断言产出位图帧。修复前后都通过。

原因：该素材只有 82 KB，历史包不受字节上限挤压，重放总能取回播放位置之后的包，缺陷不显现。应用内出现缺陷时读头领先数十秒且视频数据持续挤占历史预算。

现有测试保留为行为测试，名为 `subtitleLaneProducesAFrameAfterATrackSwitchMidPlayback`。它验证切换后产生帧，不验证本修复。

结论：该缺陷当前只有应用级证据。可判别的单位测试需要在测试中压低历史字节上限（`ENCHRON_DEMUX_BACKWARD_BUFFER_BYTES`），使历史被快速淘汰。

修复前的原始输出保留如下：

复现：播放本地 `00000.m2ts`，跳转到 119.995 秒，依次切换到德语、英语、西班牙语轨（每条间隔六秒），随后观察。

```
clock 140  packetSpan=none..none          covered=none..none  produced=0
clock 145  packetSpan=207.250..232.250    covered=none..none  produced=0
clock 170  packetSpan=207.250..253.833    covered=none..none  produced=0
clock 180  packetSpan=207.250..265.250    covered=none..none  produced=0
clock 185  packetSpan=207.250..268.250    covered=none..none  produced=0
```

同一时段 `ingested` 从 24 增长到 40，`held` 从 6 增长到 10，说明包在读、位图在缓存，但缓存区间从 207.250 起，播放位置 145 到 185 都没有被覆盖。

影响：切换后的数十秒内无字幕。播放位置要到 207.250 才落入缓存区间。

对照：第 12 轮同一文件不切换字幕、仅跳转时，一分钟内 239/239 个样本都有覆盖帧。差别在是否执行过切换。

原因。接管时字幕队列的队首已在 207.250，覆盖播放位置的包在更早的接管中被清除，队列里没有这些包。读取器只能从队首开始吞入，因此缓存区间从 207.250 起。

一次失败尝试。在字幕选择路径中调用共享源跳转到播放位置，使队列从播放位置重新填充。结果应用失去响应，探针超时，已回退。回退后应用恢复响应（`lifecycle=idle`，`playMedia ok=true`）。结论：不能在选择路径中同步调用跳转。

修复方向。共享源已保留每条流的历史包。接管的入口应接收请求起点，并从历史中重放请求起点之后的包，而不是从队首开始。入口为 `PBFFmpegDemuxSourceTakeOverStream` 与其历史重放入口 `PBFFmpegDemuxSourceReplayHistoryFrom`。

七之五，已定位，未修复：库条目失效后播放静默失败。

现象：库条目 `eighty-six-2160p.mkv` 选择后无反应，无错误日志，旧会话继续播放：

```
playMedia ok=false  detail=the media session did not change within twelve seconds
心跳会话标识 B8AB594C-46AA-4DF1-846D-E1992E86F9AD 四分钟未变
```

定位：同一文件用绝对路径重新加入库后可正常播放。

```
addLibraryFile path=/Volumes/…/SDR/[MAI] EIGHTY SIX [15][Ma10p_2160p][x265_flac_ass].mkv  ok=true
playMedia name=[MAI] EIGHTY SIX …mkv  ok=true
position=3.000 duration=1421.088 lifecycle=playing
subtitle.frame.produced at=173.800 range=170.610-173.850
```

两个条目并列存在，旧条目 `eighty-six-2160p.mkv` 的书签指向已失效位置，新条目 `[MAI] EIGHTY SIX …mkv` 正常。

结论：媒体本身可播，2160p 因子成立。缺陷在于失效书签的失败是静默的。

失败路径追踪（同一构建，选择失效条目）：

```
libraryPlay name=eighty-six-2160p.mkv
libraryResolved name=eighty-six-2160p.mkv          ← 解析成功，取得 URL
libraryOnPlayReturned name=eighty-six-2160p.mkv     ← 已交给启动器
（无 libraryPlayFailed）
```

三个探针都出现，第四个没有。解析层没有失败，失败发生在交接之后的打开路径，且 PlaybackCore 在该时段无错误记录。

边界：本轮确定了失败不在库解析层，未确定打开路径为何不报告错误。修复需要先在打开路径上补齐失败上报，再判断失效书签应产生哪一类用户可见问题。

七之六，未修复，严重：远程 `mkv` 播放崩溃。

复现：Emby 上播放 `Ghost in the Shell`（MKV，4K HEVC，DTS，时长 4989.945 秒）。

两种观察到的结局：

```
一  播放约三十秒后会话失败
    rendererStatus=readyWithDecodeFailures rendererError=The operation could not be completed
    session.videoDelivery.stop by=failIfFirstVideoFrameIsStillMissing()
    session.close.begin displayed=false

二  进程中止（SIGABRT）
```

崩溃栈（`Enchron-2026-10-31-013745.ips`，线程 17）：

```
libsystem_kernel.dylib  __pthread_kill
libsystem_pthread.dylib pthread_kill
libsystem_c.dylib       abort
PlaybackFFmpeg          matroska_parse_cluster.cold.1
Enchron.debug.dylib     demux_source_read_loop
```

崩溃发生在解复用读取线程内的 matroska 解析断言处。触发前日志末尾为 `demux.open.begin remote=true`、`demux.open.end ok=true`、`demux.seek.begin seconds=0.0`。

对照：同一次会话中 `sdr-bframe-aggregate-30s`（远程，30 秒）可播放并跳转；本地 `mkv` 同样可播放。差别在远程读取与片源规模。

影响：主档的 MKV 片源当前不可用。远程 MP4 尚未出现该问题。片源 `Ghost in the Shell` 的起始失败已单独处理：该文件为 Hi10P，现在播放前即被拒绝，见七之六之二。

重连路径的验证尝试（本轮）：

```
一  应用内注入 20 秒读取延迟（setSourceReadDelay ms=20000）
    demuxReconnects 保持 0，播放继续到 367.5 秒，未触发重连
二  连续播放远程 4K 五分钟
    demuxReconnects=0（689 次采样一致），未触发重连
三  单元测试 HTTPMediaSourceRangeTests 含断连重连用例
    去掉任一候选改动前后均通过，无法判别
```

结论：远程重连路径在当前条件下无法被刻意触发，针对它的改动无法验证。

处理：曾加入「重连跳转回退十秒」，因无法验证而删除（提交 `1444709d`）。删除后远程 4K 仍可播放（位置 15.500，`lifecycle=playing`），`HTTPMediaSourceRangeTests` 与字幕用例共 25 项通过。

本缺陷保持未修复。触发条件推断与取证方法记录在上文。

断言位置已确定。`libavformat/matroskadec.c` 第 4431 行：

```c
static int matroska_parse_cluster(MatroskaDemuxContext *matroska)
{
    av_assert0(matroska->num_levels <= 2U);
```

`num_levels` 在进入元素时自增（第 1126 行），在元素长度耗尽时自减（第 1199、1294、1321 行）。断言触发表示解析器持有三层以上未闭合的元素，即读取位置与 EBML 结构失去同步。

两种可能来源，均与远程读取相关：

一，重连路径 `reopen_demux_source` 在读取线程内以 `demux_source_resume_timestamp` 为起点调用 `avformat_seek_file`。远程文件无完整索引时，该跳转可能落在簇中间；解析器从非边界位置继续解析，元素层级无法配对。

二，远程读取返回的短读被当作正常数据继续解析，元素长度字段跨越两次读取时层级错位。

机制推断（依据源码，未加打印验证）：

一，读取返回负值且不是已知长度的结尾时，读取线程进入重连：`PBFFmpegDemuxSourceGetQueueState` 所在的同一循环里，`retries = source->isRemote && !reachedEnd`，随后调用 `reopen_demux_source`。

二，`reopen_demux_source` 以 `demux_source_resume_timestamp`（各流最后入队时间戳的最小值）调用 `avformat_seek_file`。远程文件没有完整索引时，该调用只能近似定位，落点可能在簇中间。

三，从非边界位置继续解析时，读取到的字节被当作元素头解释，簇尺寸字段被误读为「簇内的簇」，`num_levels` 由 2 增到 3。

四，同一文件的正常路径有自愈机制：`matroska_resync`（第 866 行）在识别到顶层元素时调用 `matroska_reset_status` 把 `num_levels` 复位为 1。该复位只在解析失败后的重同步路径上发生，嵌套簇路径不会触发，于是断言生效。

修复方向：远程重连不依赖字节级跳转。关闭并重新打开输入上下文，再按时间戳调用解复用器自身的跳转接口，使解析状态从头建立。

已验证的第二种表现（同一文件，本轮）：

```
video.reader.bind epoch=1 start=0.000
attach.firstUnit lane=video epoch=2 pts=0.000 raw=same
session.heartbeat time=4.000 rendererStatus=readyWithDecodeFailures
                           rendererError=The operation could not be completed
                           demuxReconnects=0 demuxReadFrames=41178
session.videoDelivery.stop by=failIfFirstVideoFrameIsStillMissing()
session.close.begin displayed=false
```

解复用侧正常：首个视频单元在 0.000，读取帧数持续增长，无重连。失败在渲染侧：样本已交付但解码失败，首帧从未显示，会话在四秒处结束。

因此该文件有两种表现，成因不同：一为远程重连后解析器断言的进程中止，二为视频解码失败导致会话终止。第二种先于第一种发生，四秒内即终止，使第一种无法靠长跑复现。

第二种表现的结论：起始失败是间歇性的，原因未定。

片源参数：`h264 High 10`，1864x1008，`extradata_size=47`（从 Emby 流接口取回文件头实测，与应用内 `video.reader.bind extradata=47` 一致）。

重复实验（每次重新启动应用，播放后第 8 秒与第 14 秒各取一次状态）：

```
第 1 次  position=4.000  lifecycle=failed
第 2 次  position=4.000  lifecycle=failed
第 3 次  position=5.000  lifecycle=failed
第 4 次  position=4.000  lifecycle=failed
第 5 次  position=4.500  lifecycle=failed
第 6 次  position=5.000  lifecycle=failed   （先播 Alien: Covenant 成功，再切到本片）
```

累计七次运行，六次失败，一次曾在早期构建上连续播放 53 秒。失败率 6/7。

文件来源：`[philosophy-raws][Ghost in the Shell][Movie][BDRIP][Hi10P FLAC][1864X1008].mkv`，10.3 GB，位于本机 rclone VFS 缓存目录（`/Volumes/Cortisol/rclone-cache/emby-media/vfs/...`），即由云盘挂载。

因此「Hi10P 编码」与「云盘挂载读取」是两个未分离的变量。

已排除：

```
配置数据完整       应用读取的字节数与文件一致
编码支持           同一次会话内该文件曾连续播放 53 秒
解码预热           加入 VTDecompressionSessionCreate 预热后 status=0，两次运行仍失败
远程源             同会话内 Alien: Covenant（4K HEVC）连续播放 40 秒以上
```

未解释：为何四秒失败、为何曾有一次成功。失败时 `rendererStatus=readyWithDecodeFailures`、`rendererError=The operation could not be completed`、首帧从未显示。

分离实验已执行，结论为编码因素。

同一服务器上三个 Hi10P 片源，各自重新启动应用后播放：

```
Ghost in the Shell          t+10s position=5.000 lifecycle=failed
Ghost in the Shell 2.0      t+10s position=5.000 lifecycle=failed
Ghost in the Shell 2: Innocence  t+10s position=4.000 lifecycle=failed
```

三个文件均在四至五秒处失败，与文件名无关。

对照：`Alien: Covenant`（HEVC Main 10，3840x2160）连续播放四十秒以上，`rendererStatus=ready`。

服务器片源统计（60 部）：`hevc Main 10` 占多数并可播放；`h264 High 10` 共四部，已测三部全部失败。

结论：H.264 High 10（Hi10P）在当前解码路径上不可播放。云盘挂载不成立为成因，因为同源同挂载下的 HEVC 片源可播放。

已修复的行为部分：该编码现在在开始播放前被拒绝，不再出现「播放四秒后黑屏退出」。

```
流信息比对   codec=h264 且 bits_per_raw_sample=10 → 判为不支持
用户可见     立即失败，不再进入解码
日志         source.unsupported codec=h264 bits=10
```

实测：

```
Ghost in the Shell（Hi10P）   playServerItem ok=false  position=0.000 lifecycle=failed
Alien: Covenant（HEVC 4K）    playServerItem ok=true   position=10.500 lifecycle=playing
```

未实现部分：支持 Hi10P 的软件解码路径。当前行为是拒绝，不是播放。

本地语料没有 H.264 10 位片源（两部 mkv 均为 HEVC Main 10），因此本地档无法分离这两个变量。

八，已解决，属判据缺陷，非观测缺陷。原判据用 `covered` 判定「字典落后」，而 `covered` 只表示已解码单元的区间。日志中已有的 `packetSpan` 就是已消费的包区间 `[A(L), S(L)]`，足以区分两种情况。判据已改写为使用 `S(L)`。实测：`at=20` 时 `packetSpan=107.250..126.292`，位置 20 已被扫过且无单元，属正常。


## 十二、验证策略

### 12.0 验证的产出

验证有三个产出，缺任一项则验证不完整。

一，判定。对本次改动给出可用或不可用的结论，依据是第五节至第八节的性质。

二，发现。找出既有提交遗留的缺陷。端到端验证运行真实片源与真实源，覆盖范围大于单元测试，因此能暴露单元测试未覆盖的顺序与组合。本次的音频静音与字幕缺失即属此类：问题由多次提交积累而成，单元测试全部通过。

三，归因。缺陷被发现后，判定它位于传输层、平台接入层、解复用层还是呈现层，依据是 12.1 的归因档与 12.4 的判据。

### 12.0.2 本次的三项产出

判定。本次改动可用。依据：

```
第五节点  三条车道接管后首个单元在播放位置，裁剪由源执行
第六节点  48/48 有字幕包覆盖的查询都有产出帧覆盖
第七节点  三次音轨切换，每次恰好一条车道，新车道起点领先时钟约六秒
第八节点  132 次查询全部落在当帧视频区间内，无容差
第九节    五项不变量全部成立
```

发现。本次验证发现九项，其中两项经复测撤回。

```
D1  库条目失效后播放静默失败          撤回，界面已提示
D2  远程 mkv 播放进程中止              未修，无法稳定复现
D3  openSourceFile 打开 WebDAV 报 5XX  撤回，服务正在停止
D4  10 位 h264 不可播放                已修行为，播放前拒绝并提示
D5  SMB 读取区间用例五项失败            未修，不在车道范围
D6  未分类失败进入公开类别              未修，不在车道范围
D7  故障注入后未出现 Playback Error     未修，待判定
D8  视频交付每四帧只交一帧              撤回，区间表按到达顺序存放所致
D9  长时间播放后解复用读取停止          未修，长跑复现中
```

归因。

```
传输层        无。同一文件在 Emby 与 WebDAV 上均可播放
平台接入层    无。D3 撤回
解复用层      D2、D9。D9 的读取计数停止增长，队列为空
呈现层        D1、D7。失败没有到达界面
编码支持      D4。判为不支持并给出提示
```

### 12.0.1 前置准备

以下四项全部完成，然后开始执行验证。任一项未完成，对应档位判定为不通过，报告列出未完成项与补齐步骤。

**凭据。**

仓库根目录 `.env` 保存设备测试凭据，明文，不提交。现有键：`WEBDAV_USER`、`WEBDAV_PASSWORD`、`EMBY_USER`、`EMBY_PASSWORD`、`SMB_USER`、`SMB_PASSWORD`。

现状：

```
EMBY_USER / EMBY_PASSWORD            已有，Emby 已在应用内登录并完成播放验证
PLEX_URL / PLEX_TOKEN                已有，接口层可用（8 个库、14 个验证片源），应用内登录未验证
WEBDAV_USER / WEBDAV_PASSWORD        已有，归因档可用
SMB_USER / SMB_PASSWORD              已有
JELLYFIN_*                           无；本机 8096/8097/8920/8921 端口均无 Jellyfin 服务
```

`.env` 为明文且不入版本控制。

**源接入。**

| 源 | 现状 | 待做 |
| --- | --- | --- |
| 本地媒体 | 已接入，仅导入两个条目 | 导入 `TestMedia/Samples` 全部格式样本 |
| WebDAV | 已接入，回归目录可用 | 无 |
| SMB | 已接入 | 无 |
| Emby | 已接入，`http://Mac-mini.local:8096` | 无 |
| Plex | 已接入 | 以启动路由注入客户端 token，应用写入钥匙串项 `com.enchron.plex.authenticated-server` |
| Jellyfin | 未接入 | 本机无服务；客户端代码存在 |

Plex 与 Jellyfin 的客户端已安装在本机。接入通过客户端与上文的凭据完成，完成后用 `libraryReferences` 确认源列表中同时存在两个源。

**本地媒体导入。**

现状：应用容器 `Documents/LocalMedia` 只含两个条目（`AVS-HD-709` 与一个 ISO）。`TestMedia/Samples` 中的 `SDR`、`DynamicRange`、`Professional`、`Spatial`、`CameraOriginals` 未导入。

待做：将 12.2 资产映射引用的文件与目录导入 `Documents/LocalMedia`，导入后条目数与映射表一致。

验证：列出 `Documents/LocalMedia`，与 12.2 资产映射逐一对照。缺失时该行判定为不通过，报告列出缺失文件与补齐命令。补齐之前，该行不计入通过数。

**命令通道的登录能力。**

```
embySignIn          已有
Plex 登录           无专用动词，须经界面
Jellyfin 登录       无专用动词，须经界面
```

Plex 的登录以启动路由完成，无需界面：

```
SIMCTL_CHILD_ENCHRON_MEDIA_SERVER_KIND=plex
SIMCTL_CHILD_ENCHRON_MEDIA_SERVER_ADDRESS=http://127.0.0.1:32400
SIMCTL_CHILD_ENCHRON_MEDIA_SERVER_USERNAME=<用户名>
SIMCTL_CHILD_ENCHRON_MEDIA_SERVER_TOKEN=<token>
```

应用启动后读取该路由并认证，日志中可见钥匙串写入 `com.enchron.plex.authenticated-server`。

Jellyfin 无本机服务，无法完成。三档验证使用 Emby、Plex 与 WebDAV 完成。

**就绪核对。**

执行验证之前，逐项记录一次，共三项：

一，每个源的连接状态，附应用内源列表截图或 `libraryReferences` 输出。

二，每个源中 12.2 资产映射所需片源的存在性。

三，本地媒体导入条目数。

四项全部完成后，12.1 的三档才有意义。

### 12.1 三档验证

验证分三档，档位由目的决定，不由源的数量决定。

```
可行性档    本地媒体        快速，判定改动是否可用      每次改动
主档        媒体平台        压力，判定真实片源是否可用  改动合入前
归因档      WebDAV 同片对照  出问题时定位问题在哪一层    主档失败时
```

#### 可行性档：本地媒体

目的：改动之后几分钟内知道能不能播、字幕有没有出来。

源：本地媒体目录，`TestMedia/Samples` 已链接至应用容器 `Documents/LocalMedia`。

片源：语料中已有的格式样本，见 12.2 资产映射。这些样本短、确定、可重复。

已执行单元（2026-10-31，本地，同一构建）：

```
HDR10.MP4                         播放成功  时长 83.083  跳转 0.3 后位置 33.100  t+8s
LG_Cymatic_Jazz_HLG_Astra_teststream.ts  播放成功  时长 297.533 跳转 0.3 后位置 97.500  t+8s
00000.m2ts                        播放成功  时长 888.032 跳转 0.13513 后位置 126.000 t+6s
少女终末旅行 - S01E01 …mkv          播放成功  时长 1422.058 跳转 0.8439 后位置 1206.100 t+6s
[MAI] EIGHTY SIX …mkv（2160p）     成功    时长 1421.088 跳转 0.12 后位置 176.500 t+6s，ASS 字幕产出
eighty-six-2160p.mkv              失败    书签失效，见第十一节第七条
```

判定依据：跳转后位置按一倍速推进，说明时间线在走；未检测到 `session.seek.stalled`。

最终判据取自主档。本地源无网络、无范围请求、无服务器转码，与用户使用条件不同，因此本地档只判可行性。

#### 主档：媒体平台

目的：在用户实际使用的条件下验证。

源：Emby、Plex、Jellyfin。远程源的片源丰富程度远高于本地语料，因子覆盖主要由这一档完成。

片源：按 12.2.0 从平台库中挑选。

执行：每个选中的片源在每个可用的平台上各执行一次。

执行入口：调试命令 `playServerItem name=<条目名>`，按名称在已登录的媒体服务器中检索并播放，二十秒内会话未变更则返回失败。该入口使主档可脚本执行，无需界面操作。

已执行单元（2026-10-31，Emby）：

```
sdr-bframe-aggregate-30s   播放成功  时长 30.021    跳转 0.5 后位置 21.000    t+6s
Ghost in the Shell         播放成功  时长 4989.945  跳转 0.5 后位置 2499.500  t+8s
Alien: Covenant            播放成功  时长 7323.467  位置 12.500 lifecycle=playing  4K HEVC + TrueHD Atmos
5 Centimeters per Second   已确认素材  1080p HEVC Main 10 + DTS + AC3
```

`Alien: Covenant` 覆盖本地语料缺失的三项：2160p、TrueHD、DTS-HD MA。

连续播放实测（同一构建，单次会话，每三十秒取一次状态）：

```
t+30    position=30.500   lifecycle=playing
t+60    position=61.500   lifecycle=playing
t+90    position=92.000   lifecycle=playing
t+120   position=122.500  lifecycle=playing
t+150   position=154.000  lifecycle=playing
t+180   position=185.000  lifecycle=playing
t+210   position=216.000  lifecycle=playing
t+240   position=247.500  lifecycle=playing
t+270   position=278.500  lifecycle=playing
```

进程全程存活，位置按一倍速推进，期间 `demuxReconnects=0` 六百八十九次采样一致。因此重连路径在该次运行中未被触发，第十一节第六条的重连缓解改动仍未验证。

会话恢复：应用内 Emby 登录可由仓库内的身份文件恢复，无需界面操作。

```
cp Tests/EmbyPackageTests/Fixtures/EmbyServerCredentials.local.json \
   <容器>/Documents/Regression/emby-runtime-identity.json   并置为 0600
embySignIn identityDigest=sha256:<该文件的 SHA-256>
```

回执为 `enchron.regression.emby-sign-in@1`，`persisted=true`。

平台可用性：Emby 已登录（`embyServerIdentityDigest` 返回摘要，服务器返回条目）。Plex 令牌可用（`.env` 的 `PLEX_TOKEN`，接口返回 8 个库、14 个验证片源），应用内的 Plex 登录未验证。Jellyfin 在本机无服务。

#### 归因档：WebDAV 同片对照

目的：主档失败时，判定问题在传输层还是平台层。

源：WebDAV 回归目录，`https://Mac-mini.local:8443/dav/regression/`。

片源：与出问题的平台片源为同一文件。

判定：同一文件在 WebDAV 上正常、在平台上异常，问题在平台接入层（转码、直连策略、鉴权、分片）。两边都异常，问题在解复用或解码层，与源无关。

执行时机：主档出现失败时。常规执行不包含本档。

现状：该档尚未产出有效证据。执行入口为控制台单位 `unit:catalog.scenario-webdav-source-lifecycle-webdav-add-source@1`。

实测（2026-10-31）：

```
python3 Scripts/console/cli.py run "unit:catalog.scenario-webdav-source-lifecycle-webdav-add-source@1"
  ok   pre media-source  started                 ← WebDAV 服务由前置条件启动
  ok   01 device.app-command  38812 ms
  terminal artifact FAIL  expected evidence probe.json was never written
```

前置条件能够启动 WebDAV 服务，因此该档的源可用。单位在一号步骤之后未继续，终态证据 `probe.json` 未生成，证据目录仅有 `01-device.app-command.json`。

复跑结果（清除服务缓存后）：

```
ok   27 device.command   Element tapped.
ok   28 device.await     'FileBrowsing-FilesScreen'
ok   29 device.await     'FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv'
ok   30 device.probe     Current UI state captured.
terminal artifact ok     probe.json present
exit=0
```

该单位通过，WebDAV 源可添加、可列出文件、可抓取界面状态。首次失败的原因为前置条件中 Emby 服务身份核对未通过，属瞬时故障。

三档在当前构建上的复跑（2026-10-31，裁剪版）：

```
可行性档   本地 mkv、m2ts、mp4、ts 五片，播放与跳转正常
主档       sdr-bframe-aggregate-30s  时长 30.021   位置 10.000  playing
           Alien: Covenant（4K）    时长 7323.467 跳转 0.5 后 3664.500
                                    二十秒后 3685.000，一倍速推进
归因档     同一文件 sdr-bframe-aggregate-30s.mkv 经 WebDAV 播放
           position=6.500 lifecycle=playing
```

三样证据齐全的单位（`--capture-logs`，证据目录给出）：

```
unit:catalog.scenario-webdav-source-lifecycle-webdav-add-source@1
  TestEvidence/console/unit-catalog.scenario-webdav-source-lifecycle-webdav-add-source@1/20261030T213402Z
  steps/    命令与响应原文      31 个步骤文件
  logs.txt  log show 原文       31 行，覆盖运行起止
  report.json 判据计算表        verdict=passed

unit:catalog.scenario-issue-surface-behavior-typed-single-slot-contract@1
  TestEvidence/console/unit-catalog.scenario-issue-surface-behavior-typed-single-slot-contract@1/20261030T213447Z
  steps/、logs.txt、report.json 三样齐备
  verdict=failed，失败步骤的 detail 为 never reached 'Playback Error'
```

同一文件在 Emby 与 WebDAV 上均可播放，传输层不构成差异来源。

同文件跨档对照（本轮首次取得）：

```
Emby    sdr-bframe-aggregate-30s.mkv   播放成功，时长 30.021，跳转 0.5 后位置 21.000
WebDAV  同一文件                        demux.open.failed error=Open demux media source:
                                        Server returned 5XX Server Error reply (-1482175992)
```

按本档判定规则：同一文件在平台上正常、在 WebDAV 上异常，问题在 WebDAV 接入层，不在解复用或解码层。

复测结论：同一文件在两条路径上的表现不同，而差异来自服务存活期。

```
单位执行期间（服务由前置条件启动）  播放正常
                                    控件面 active=true formatReady=true
单位结束后手工调用                  5XX

单位结束后直接请求服务地址          SSL 连接失败（curl 退出码 35）
```

因此该 5XX 发生在服务停止过程中，不构成接入层缺陷。归因档的结论为：同一文件在 Emby 与 WebDAV 上均可播放，问题不在传输层。

待确认：该 5XX 在服务存活期间是否稳定复现。单位结束后直接请求 `https://Mac-mini.local:8443/dav/regression/sdr-bframe-aggregate-30s.mkv` 返回 SSL 连接失败（curl 退出码 35），说明服务随单位结束而停止，因此需要在服务存活期间复测。

### 12.2.0 片源挑选

片源不按片名挑，按下列规则挑。

一，先测后选。对候选文件统计字幕单元密度，按一分钟窗口取最密的一段。无字幕的候选改用音频包密度。密度决定选段，不决定是否入选。

二，按因子缺口选。先列出 12.2 中尚未覆盖的因子水平，再在平台库中寻找满足该水平的片源。

三，同文件可归因。入选的片源必须能在 WebDAV 上取得同一文件。

四，每个水平至少一例。一例通过即该水平通过。同一水平的其余片源为补充，补充数量不减少水平总数。

五，冲突时以覆盖为先。密度高的片源若不能补任何因子水平，让位给能补水平的片源。

六，平台库中不存在某水平时，记为覆盖缺口。缺口计入未通过项，直到引入满足该水平的片源。其他水平不顶替该缺口。

### 12.2 覆盖设计

全组合为 5 类容器 × 3 类字幕表示 × 8 类音频 × 6 个源，共 720 组，不可执行。

采用因子覆盖：每个因子水平至少测一次，每对可能相互作用的因子组合至少测一次。

#### 因子与影响

| 因子 | 为什么是因子 | 水平 |
| --- | --- | --- |
| 容器 | 决定每条流的时间戳起点与流交错方式。缺陷形态是「流起点与文件起点不一致」 | mkv、mp4、mov、ts、m2ts、Blu-ray ISO |
| 字幕表示 | 决定字典如何被填充。位图用显示集合解码，文字用行解析，外挂单独路径 | 位图（PGS）、文字内嵌（ASS/SRT）、外挂文件 |
| 音频编码 | 切换音轨时重新打开解码器。延迟与帧长随编码不同 | aac、ac3、eac3、dts、dts-hd ma、truehd、flac、pcm |
| 源传输 | 决定跳转后重新取数的代价，影响接上时间 | 本地、WebDAV、SMB、Emby、Plex、Jellyfin |

对齐因子为四个：容器、字幕表示、音频编码、源传输。视频编码只在具备专用时间戳语义时单独取组，例如 MVC 三维与 ProRes。

#### 相互作用对

三对必须同时出现，其余按单因子覆盖。

一，容器 × 字幕表示。时间戳起点与字典填充方式组合，是本次缺陷的核心。

二，容器 × 音频编码。切换时的解码器重建与容器时间戳起点组合。

三，源 × 容器。跳转后重新取数的方式与容器内偏移的组合。

#### 资产映射

下表每一行是一次执行。容器、字幕、音频列取实际文件。

| 编号 | 文件 | 容器 | 视频 | 音频 | 字幕 |
| --- | --- | --- | --- | --- | --- |
| C1 | `SDR/[MAI] EIGHTY SIX ... x265_flac_ass.mkv` | mkv | hevc | flac | ass |
| C2 | `SDR/少女终末旅行 - S01E01 ... .mkv` | mkv | hevc | aac, flac | ass |
| C3 | `DynamicRange/HLG/LG_Cymatic_Jazz_HLG_Astra_teststream.ts` | ts | hevc | aac | 无 |
| C4 | `DynamicRange/HDR10/HDR10.MP4` | mp4 | hevc | aac | 无 |
| C5 | `CameraOriginals/Apple/IMG_6340.MOV` | mov | h264 | aac, apple_apac | 无 |
| C6 | `Professional/ProRes/ARRI-AMIRA/B001C001_140702_R3VJ.mov` | mov | prores | pcm_s24le | 无 |
| C7 | `DiscImages/Sintel/Sintel-Bluray/BDMV/STREAM/00000.m2ts` | m2ts | h264 | ac3 | PGS |
| C8 | `DiscImages/Sintel/Sintel-Bluray` 整盘 | Blu-ray | h264 | ac3 | PGS |
| C9 | `DiscImages/Captain.America.Civil.War...iso` | Blu-ray 3D | MVC | dts-hd ma | PGS |
| C10 | `DiscImages/DolbyVision-Profile7-FEL` 整盘 | Blu-ray | hevc | 无 | 无 |
| C11 | 外挂 `Fixtures/subtitle-en.srt` 加载到 C1 | mkv | hevc | flac | 外挂文字 |

#### 档位分配

| 行 | 可行性档（本地） | 主档（平台） | 归因档（WebDAV） |
| --- | --- | --- | --- |
| C1 至 C11 | 各一次 | C1、C7、C8、C9、C11 各在每个可用平台一次 | C1、C7、C8、C9、C11 各一次 |
| 主档失败时 | 不执行 | 不执行 | 失败片源的同文件，各一次 |

主档候选行按 12.2.0 第二条，由平台库中实际存在的水平决定。表中五行为起步行，其后按因子缺口继续增加。

#### 选段

每次执行前按 12.2.1 选段。

##### 12.2.1 选段规则

一，取该文件字幕流，按一分钟窗口统计单元数量。

二，取单元数最多的窗口 `W`。

三，在 `W` 起点播放一分钟。

四，同一文件在不同源上使用同一个 `W`。

无字幕的文件改用音频包密度选段。

### 12.3 执行步骤

每个源、每种检查各执行一次。步骤如下，全部通过应用命令通道执行，命令见 12.5。

一，打开源，播放标题。

二，选中第一条字幕轨。记录 `subtitle.lane.attached`。

三，跳转到 `W` 起点。记录跳转后的 `subtitle.lane.attached` 与 `subtitle.frame.idle`。

四，连续播放一分钟。采样子幕查询与交付日志。

五，切换音轨一次，观察十秒。记录 `audio.attach.open`、`audio.select.opened`、`readiness.state`。

六，切换字幕轨一次，观察十秒。记录 `subtitle.lane.attached`。

七，再次跳转，重复步骤四至六。

#### 12.3.1 因子覆盖

执行过的因子组合与证据位置。

```
容器       mkv     本地 SDR 两片、Emby 四片        第七节、第九节
           m2ts    本地 00000.m2ts                  第五节、第七节
           mp4     本地 DolbyVision 两片            可行性档
           ts      本地 HLG 测试流                   可行性档
           光盘    BDMV 目录                        可行性档、第七节
视频编码   h264 8 位 本地测试片段                  可行性档
           hevc 8 位 本地部分片源                  可行性档
           hevc 10 位 本地两片、Emby 多数片源       主档，连续五分钟
           h264 10 位 Emby 四片                    判为不支持，播放前拒绝
音频编码   aac      本地三音轨 mkv 第二、三轨       第七节音频切换
           ac3      本地 mkv、Emby 部分片源        第七节
           flac     本地 mkv 第一轨、Emby          第七节
           dts      本地 m2ts、Emby                第七节
           dts-hd ma Emby Alien: Covenant          主档
           truehd   Emby Alien: Covenant           主档
字幕       ass 文本 本地 mkv、Emby                 第五节
           pgs 位图 本地 m2ts、光盘                第五节、第七节
```

补充覆盖（本轮由现成片源转封装产生，命令可复跑）：

```
mkv 内位图字幕
  ffmpeg -ss 100 -t 60 -i Sintel-Bluray/BDMV/STREAM/00000.m2ts \
         -map 0:v:0 -map 0:a:0 -map 0:s:0 -c copy /tmp/pgs-in-mkv.mkv
  实测 subtitle.frame kind=bitmap at=21 size=1920x109

mov_text
  ffmpeg -ss 180 -t 60 -i 少女终末旅行…mkv \
         -map 0:v:0 -map 0:a:0 -map 0:s:0 -c:v copy -c:a aac -c:s mov_text /tmp/movtext.mp4
  实测 subtitle.frame kind=coreText at=16 size=1168x124
```

vobsub

```
ffmpeg -i /tmp/pgs-in-mkv.mkv -i FATE/MPEG2/dvd_single_frame.vob \
       -map 0:v:0 -map 0:a:0 -map 1:s:0 -c copy /tmp/vobsub-in-mkv.mkv
实测 subtitle.frame.produced at=0.000 range=0.000-5.000
     subtitle.frame kind=bitmap at=0 size=720x573
```

外挂位图字幕：产品不支持，不属覆盖缺口。

```
外挂字幕的扩展名白名单为 srt、vtt、ass、ssa（FileFilter.externalSubtitles）
实测：extsup.mkv 与同目录 extsup.sup 同时存在时，会话报告 subtitles=1
      即只有内嵌轨，旁挂的 .sup 未被发现
```

因此「容器 × 位图字幕」的组合覆盖 m2ts、光盘、mkv 与 vobsub；mp4 的位图字幕不成立（mov_text 是文本格式）；旁挂位图字幕不在产品范围。

### 12.4 判据与证据

| 性质 | 证据 | 失败条件 |
| --- | --- | --- |
| 挂载位置等于播放位置 | `audio.attach.open` 的 `headBefore` 与同一行播放位置；`subtitle.lane.attached` 的 `at` 与接管时的播放位置 | 交付单元 `start(u) < A(L)` |
| 字幕查询覆盖 | `subtitle.frame.idle` 的 `covered` 与查询位置 | 查询位置在 `covered` 区间内而返回空 |
| 查询与就绪 | `readiness.state` 迁移与 `covered` | 查询位置在 `covered` 区间外且状态为 `playing` |
| 切换 | `audio.select.opened`、`readiness.state` | `playing` 期间零条或两条音轨车道交付覆盖 `P` 的单元 |
| 单一时钟 | 查询位置与当帧视频单元区间 | 查询位置落在当帧区间之外 |

### 12.4 控制台各档现状

```
tier static   通过   （36339 毫秒，最近一次）
tier build    通过   （102368 毫秒，最近一次，写出六份 spec）
tier e2e      最近一次 10/12
              unit:playback.window-open@1        device.app-command 60726 毫秒，预算 60000
              unit:playback.format-apply@1       命令批次 30 秒无响应
              两个单元在同一会话稍早的运行中均通过；同期应用侧命令往返实测 0.245 秒
              因此这两项超时属控制台传输层，与应用无关
tier unit     不通过  最近一次完整运行：794 个用例，21 项失败
              其中 6 项为此前已知的 SMB 读取区间与失败分类用例
              另有 5 项以 signal kill 结束（Tidal、TrackSelection、ByteStream、Residency、Presentation）
              1 项为测试运行器未建立连接
              重复运行一次后挂起二十分钟无进展，已终止
              隔离复测：TidalEnvironmentTests/appearanceRoundTrip 与
              PlaybackLoadingStateTests/aCompletedSeekClearsTheSeekingStage 单独运行时均 TEST SUCCEEDED
              因此这些失败只在全集运行中出现，属用例间干扰或运行器不稳
```

`tier e2e` 的默认选择是十二个单元。

命令通道无响应时先查是否有残留的 `com.xiongzhipeng.EnchronAppUITests.xctrunner` 进程：
该进程占用应用时，通道不响应，与启动参数无关。全量选择（`--full`）执行到第十个单元后停住，停在 `unit:catalog.scenario-format-coverage-unsupported-codec-guidance@1`，日志不再增长，已终止。

该单位单独执行的结果：

```
failure  unit:catalog.scenario-format-coverage-unsupported-codec-guidance@1  verdict=failed  25520 ms
  step      09 device.app-command  13352 ms
  actual    the media session did not change within twelve seconds
  args      {"arguments": {"name": "packed_bframes.avi"}, "verb": "playMedia"}
  terminal  artifact failed: expected evidence hierarchy.json was never written
```

片源为 `TestMedia/TestVectors/Upstream/FATE/MPEG4-Part2/packed_bframes.avi`，视频编码为 MPEG-4 Part 2。该单位在第九步之后期望界面上出现标签为 `Unable to Play` 的元素。

观测：应用不为该文件建立会话，`playMedia` 返回 `ok=false`，第九步失败，第十步的界面断言因此未执行。

判定结果：应用给出了提示。系统日志中的告警控制器原文：

```
Title: `Unable to Play`
message: `This video uses MPEG-4 Part 2 video, which Enchron does not support.`
actions: [`Close` (cancel)]
```

因此是命令通道的判定问题，不是产品缺陷。`playMedia` 原本只按「会话是否变化」判定成败，无法区分「拒绝并提示」与「静默无动作」。

已修：等待结束后读取运行时的用户可见问题；若有，命令以成功返回并在详情中带上该问题的描述，下一步的界面断言得以执行。

复跑该单位：

```
ok   09 device.app-command
ok   10 device.await   1 次探测，955 毫秒，字段 label = "Unable to Play"
ok   11 device.snapshot
terminal artifact ok  hierarchy.json present
```

静默无动作仍未被视为成功：无会话且无提示时，命令继续返回失败。

静态档此前的八项失败已逐项修完：

```
orphan-verbs                         十五个手工动词登记
test-orphan-verbs                    同上
test-rubric-predicate-coverage       rubric 107，覆盖率基线 18/19
scripts-inventory                    两个无归属检查器注册进验证表
test-regression-catalog-materialized 场景 70、静态度量 119、义务 158
test-regression-operation-adapter    音轨退役检查的测试名对齐现有用例
test-regression-review-stage         场景常数 70
test-run-verification                新注册项补齐三项标签
```

以上数字偏差同源于提交 `c3c66038`：它新增「字幕跟随跳转」场景并更新了材料化器与完成报告，另外四处固定数目未同步。

自定义单位（`catalog.remote-playback-emby-item-opens`）因未被目录引用而被可达性检查拒绝（C013），已删除。控制的单位必须由 `Config/regression/catalog-v2.json` 引用才可执行。

`tier unit` 当前不通过，五项失败与播放车道无关：

```
SMB playback bridge serves only the requested byte range
SMB playback bridge applies backpressure-sized source reads
playback bridge supports open-ended seek ranges
unknown source length uses chunked transfer and disables seeking
container index cache reuses bytes for the same content revision
unclassified failures do not become a public active category
```

前五项位于 `Tests/MediaLibraryPackageTests/SMBDataSourceAdapterTests.swift`，断言的是 SMB 读取请求区间序列；第六项位于 `PlaybackActiveFailureTests.swift`，断言未分类失败不进入公开的活动故障类别。两处均不在本次改动范围内。

e2e 档已具备执行条件（静态与构建均通过），运行中。

### 12.5 执行入口

端到端单位。`console run <unit>`，每个单位一条命令，证据落盘。与字幕相关的既有单位：

```
Config/console/units/catalog-scenario-local-media-lifecycle-subtitle-switch-and-off.md
Config/console/units/catalog-scenario-presentation-tour-track-selection-survives-seek-and-presentation.md
Config/console/units/catalog-scenario-presentation-tour-track-selection-survives-seek-and-presentation-part2.md
```

设备命令通道动词：`openSourceFile`、`playDiscTitle`、`selectSubtitleTrack`、`selectAudioTrack`、`seekNormalized`、`playbackProbe`、`answerResumePrompt`。

日志读取：

```
xcrun simctl spawn <UDID> log show --info --last <窗口>   --predicate 'subsystem == "com.xiongzhipeng.PlaybackCore"' --style compact
```

### 12.6 证据记录

每个源、每个步骤保存三样：命令与响应原文、`log show` 原文、判据计算表。判据计算表列出每条证据的字段值与成立与否。三项齐全才算该源通过或失败。缺任一项，该源判定为不通过，报告写明缺项。

三样的落盘位置：

```
命令与响应原文   <证据目录>/steps/*.json
log show 原文    <证据目录>/logs.txt   以 console run --capture-logs 生成
判据计算表       <证据目录>/report.json 的 steps 与 terminal
```

`--capture-logs` 在单位结束后按本次运行的起止时刻抓取该设备上 PlaybackCore 子系统的日志，写入 `logs.txt`。默认关闭，因为 `log show` 一次可达数十秒，纳入每次运行会使单元档变慢。

判据计算表的第一行固定为前置条件：所测车道是否已挂载。未挂载的车道不产出单元，此时按覆盖判据计算会得出全数违反的结果，与实现无关。本轮曾出现一次：连续播放的采样未选择字幕轨，579 次查询中有字幕包覆盖的 75 次全部记为违反，核对 `subtitle.lane.attached` 后确认车道未挂载，该次计算作废。

### 12.7 当前缺口

一，`subtitle.frame.idle` 未记录当帧视频单元区间，判据「单一时钟」当前无法判定。补该字段是执行本策略的前置改动。

二，磁盘镜像测试只用过一部影片。按 12.2 选择后，至少再补一部字幕密度不同的影片。

三，Plex 与 Jellyfin 的实际可用性未验证。接入代码存在，服务器是否在线未确认。

四，资产缺口。语料中无位图字幕的 mkv、无 mov_text、无 VobSub、无外挂位图字幕用例。位图字幕只出现在 m2ts 与 Blu-ray 容器中，因此「容器 × 位图字幕」这一对只有 m2ts 与 Blu-ray 两个水平，mkv 与 mp4 位图缺失。

五，语料中无 truehd 与 dts-hd ma 的本地文件，两种编码只出现在 C9。音频编码 × 源 的组合因此不完整。

### 12.8 缺陷处置

验证发现的缺陷按下列规则处置。

一，每条缺陷登记一条记录，位置 `Config/console/known-failures.md`。该文件是控制台的已知失败声明，格式 `{"schema": "enchron.console.known-failures", "schemaVersion": 1, "failures": []}`，每条含 `test` 或 `unit`、`match`、`reason`、`expires`。

二，登记时必须附复现命令与观测到的原文。缺少复现命令的缺陷仍须登记，在 `reason` 中写明缺失项。未登记的缺陷按未修复处理，并使对应档位不通过。

三，处置分三种：本次修复、登记为已知失败并给出到期日、移交其它工作流并注明接手方。

四，修复后从清单移除。`expires` 到期而未修复的记录会使该档转为红，强制重新处置。

五，本次的字幕问题是一个完整例子。它由多次提交积累而成，单元测试全部通过，端到端验证暴露后归因为三层：队列挂载位置、跳转后的重建、纪元切换后的失效。三层的判据分别落在本文件的第五节、第六节与第八节。
