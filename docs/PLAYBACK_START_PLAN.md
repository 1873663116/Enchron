# 播放起播的执行与验收方案

本文规定「远程源起播不可用」这组缺陷的目标状态、判据与剩余工作。

## 一、目标状态

一个会话、一份描述、一个就绪状态机。

```
SourceSession（唯一 AVFormatContext，纪元 E）
  ├─ 源描述：容器事实、流表（语言按 PID 合并）、缺省选择
  └─ 就绪状态：loading / playable / stalled / failed

video attachment   audio attachment   subtitle attachment
  按 (E, streamIndex) 绑定，只取包，不单独失败
```

四条不变量。

一，可播性是联合判据。存在视频则必须有被接受的视频样本；存在音频则必须攒到预滚呈现时间。无音轨文件退化为仅视频。

二，数据状态与传输意图分离。数据未就绪时界面显示加载中，不显示暂停。

三，失败属于会话。单个消费者不因等待而被撤除。

四，判据用呈现时间与源侧字节进展，不用某一次实测的字节常数。

## 二、当前实现

源纪元。解复用会话在创建源时递增纪元。视频读取器、音频读取器、字幕渲染器在打开时记录绑定的纪元，读取前核对。

```
epoch 一致  -> 继续读取
epoch 不符  -> 抛错，报出旧值与新值
```

日志：`video.reader.bind epoch=`、`audio.reader.bind epoch=`、`video.read.staleEpoch`、`audio.read.staleEpoch`、`subtitle source epoch moved`。

源描述。会话在打开后创建一次 `PlaybackSourceDescription`：纪元、容器事实、流表、可用音轨与字幕轨。打开、seek、切换都读这一份值，不重新派生。

```
source.description epoch=1 streams=11 audio=4 subtitles=6
```

描述缺失时（加载器不存在或返回空）音轨枚举走兜底路径，并记录 `source.description.fallback lane=audio|subtitle reason=`。

起播闸门。会话进入 playable 的条件是联合判据成立。

```
视频样本已被接受
  且（描述中没有音频 或 音频已攒到预滚呈现时间）
```

闸门没有墙钟期限。等待期间会话保持 loading，音频轨道不被撤除。

```
源字节持续增长        -> 继续等
字节与视频样本都停住  -> stalled，抛 sourceStalled，整场失败
视频投递结束          -> 不再判定停顿
```

日志：`readiness.state state=playable reason=startGate`、`state=stalled reason=playbackStall`、`state=playable reason=sourceResumed`。

稳态停顿。播放期间每五百毫秒检查源字节与已接受视频样本的推进情况，两者都停住超过停顿阈值即进入 stalled，任一恢复即回到 playable。

界面映射。产品生命周期为 loading 或会话就绪为 stalled 时，播放键位置渲染进度指示。

seek 路径。seek 等待不再因音频晚到而撤除音轨；源停顿判定为整场失败，音频未到时音轨保留并记录 `audioRenderer.seekPrerollDeferred`。

切换路径。音频切换与字幕切换落在当前会话上，不重建会话、不换源。实测证据：播放中切字幕 `success`，音频投递继续；切音频后 `audio.select.opened index=2 codec=ac3`，随后 `audio.deliver track=…audio.2` 继续，位置从 61.5 秒推进到 63.0 秒，两个读取器重新绑定时 `video.reader.bind epoch=1`、`audio.reader.bind epoch=1` 与切换前同源。

## 三、剩余工作

一，源描述。`PlaybackSourceDescription` 是值类型，由会话创建一次，音频与字幕 provider 的轨道枚举直接收这个值，签名里没有可为空的信息参数。外部字幕文件仍是独立源，自己探测；播放路径与外部路径尚未在类型上分开。

二，失败范围。音频读取失败、seek 后音频重开失败、音频渲染器失败、音频渲染器投递失败都已改为会话级失败：会话进入 failed，两条车道一起停，音轨不被撤除。prepare 阶段的音频打开失败仍是能力事实：音轨撤除，界面显示原因（例如无解码器）。音频轨道切换回滚失败仍撤轨继续，归入阶段四。

三，回归目录的语义债。`Config/regression/catalog-v2.json` 中的 `scenario:format-coverage:audio-retirement-on-failure` 与其 rubric 断言的是旧语义（撤轨后继续），与当前实现相反；它的 criteria 文本里按旧测试名引用（`audioReadFailureRetiresAudioButVideoStillDelivers` 等）。目录本身自洽（materializer 校验通过），这笔债只在语义与文档。退役它要同步 `Scripts/regression/materialize_catalog_v2.py` 的计数守卫、`Scripts/regression/completion.py` 与两份测试里的硬编码计数。

四，切换路径。音频挂载的打开只有一处实现：初始打开、seek、音轨切换、切换回滚都调用 `openAudioAttachment`，它负责重开、核对源纪元并记录 `audio.attach.open reason=`。三条路径的停止、刷新、seek 编排序列仍各写一份。

## 四、验收矩阵

结构层。`demux.open` 一次；`source.description` 每次打开一行；三个读取器各有一行绑定日志；代码中不存在按文件实测的字节常数。

场景层。远程冷启动不 seek 出声；seek 后音频持续投递；限速导致的停顿显示为等待并自动恢复；无音轨文件正常播放。

否定层。音频延迟不触发撤轨；音频队列停住必须报停顿；交织较差的文件不误报；「视频在播、音频缺失」不由等待触发。

已有运行证据。远程 ISO 冷启动 `start.firstUnit` 两条车道与 `readiness.state state=playable reason=startGate`；限速 0.05 Mbps 时 `state=stalled reason=playbackStall` 且 `waiting=true`，解除后 `state=playable reason=sourceResumed` 且 `waiting=false`；seek 后 `audio.deliver` 持续增长且无 `seekPrerollFailed`。

## 五、风险与未决

一，停顿阈值取自 `transportBoundStallLimit`（120 秒），在真实远程源上未实测。

二，纪元轮换由测试钩子触发，真实的源重建与回环端口刷新路径没有端到端证据。

三，Emby 路径中音频包未到达的具体归属（纪元错配或队列未填充）仍未定位。

四，字幕帧时间基与音视频时间基是否一致未验证。

五，`retireAudio` 仍由音频打开失败与读取失败调用，界面以「Sound. Playing silently.」呈现；这条路径是否属于能力事实需要在阶段三一并裁定。
