# 串流音频

串流会话把主机的声音在佩戴者处播放出来。音频链路的健康以产品的音频探针为准：接收、入队与丢弃三个计数构成一条可核对的链路。

## Sub-features

- 会话建立后音频启动，采样率与声道数可读。
- 主机发声时客户端收到音频包并全部入队。
- 会话结束时音频停止。
- 音频链路断开后不残留播放。
- 设置页的「PC 端播放音频」打开后声音留在主机，本机不接收主机音频；控制面 `hostAudio=1`。

## How to get to it (user POV)

会话进行中主机播放声音，佩戴者直接听到。没有单独的音频开关；会话开始即有声音，会话结束即停止。

## Driving it with computer use

Preconditions: 会话在 streaming 状态；主机侧有一个可辨识的声音来源。

主机发声由主机的播放器给出，属于 `host-audio` 证据。客户端链路读控制面：

```sh
./.scratch/stream-cmd.sh streamSnapshot '{}'   # audio:received=… audio:enqueued=… audio:dropped=…
D="$(xcrun simctl get_app_container <UDID> com.xiongzhipeng.Enchron data)/Documents"
grep -E "audio (start|stop)" "$D/stream-session-probe.log" | tail
```

## 证据

| 种类 | 判据 | 谁守 |
|---|---|---|
| 结构 | 音频在会话启动后开始、在会话结束后停止，不跨越会话边界 | `StreamSessionCoordinator` 单测 |
| 物理 | 控制面 `audio:received` 与 `audio:enqueued` 同时增长，`audio:dropped=0` | 控制面读数 |
| 物理 | 探针出现 `audio start rate=… channels=…` 与 `audio stop` | 探针 |
| 物理 | 断连对照：断开会话后不再有 `audio:received` 增长 | 控制面读数 |
| 物理 | 「PC 端播放音频」打开时启动 URL 带 `localAudioPlayMode=1`，控制面 `hostAudio=1` | 模拟器日志 + 命令通道 |
| 感知 | 音画同步、是否有爆音 | **待做** |

## 证明的终态

音频的证明是一条闭合链：主机确实在发声、客户端确实收到并全部入队、会话结束后确实停止。客户端计数增长只证明收到了包，不证明声音被播放出来；播放本身归感知证据，不由 Agent 判定。

## Gotchas

- **模拟器的音频输出不等于真机。** 模拟器上听到的声音经由宿主 Mac 播放，不能作为真机音频链路的证据。
- **`audio:received` 增长而 `enqueued` 不增长，是链路断开而不是没声音。**
- **PC 端播放时本机收不到音频帧，`audio:received` 保持 0 是预期。** 判据改为启动 URL 的 `localAudioPlayMode`。

## 本轮补齐范围（2026-10-26 裁决）

范围、阶段与验收见 `docs/reviews/streaming-port-review/plan.md`。

纳入：

- 声道数按设备能力协商（立体声、六声道、八声道），主机多声道内容不再被下混成立体声。
- 设置页出现多声道音频开关。

不做：空间音频与头部追踪、音频输出设备的手动切换。设备切换出问题时按缺陷处理，不作为移植项。
