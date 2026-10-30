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

源描述。会话在打开后记录一次描述事实。

```
source.description epoch= streams= audio= subtitles=
```

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

## 三、剩余工作

一，源描述仍是记录而非值类型。音频与字幕的 `tracks(...)` 仍保留各自的加载器，播放路径靠调用方传入描述来绕过它们。外部字幕文件是独立源，必须自己探测；播放路径与外部路径尚未在类型上分开。

二，失败范围。音频打开失败与读取失败仍会撤除音轨并让视频继续。这些路径按现状保留，尚未改为会话级失败。

三，切换路径。音频切换、字幕切换、seek 三条路径尚未统一为「重新绑定 attachment」，其中 seek 已改为不撤音轨。

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
