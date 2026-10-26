# 串流韧性

串流在主机断连、网络中断与会话收口时保持状态可读，不遗留资源。断连不等于退出：会话结束后主窗口仍然可用，主机仍然可选。

## Sub-features

- 网络中断后会话进入 interrupted，恢复后可以回到 streaming。
- 主机主动断开会话时客户端进入 ended，原因为产品自己给出的原因。
- 会话结束后输入全部释放、音频停止、渲染器归还。
- 断连后主窗口仍可用，Moonlight 标签页的主机列表与内容列不受影响。
- 退出 App 时会话干净收口，不留下悬挂的会话。
- App 进入后台（按数字表冠、摘下头显）时，本地连接断开，主机上的应用继续运行，播放窗口保留；App 回到 active 时，以 resume 重连同一主机与应用。这与文件播放在后台只暂停、回来再重建的行为一致。
- 渲染器重建、表面重新绑定、渲染器 flush 时，待发帧队列清空并向主机请求关键帧。渲染器报解码告警只累计计数，不改动交付。
- 音频帧到达而音频引擎已停止（例如场景进入后台造成的打断）时，引擎每秒最多重启一次。

## How to get to it (user POV)

网络中断由外部条件造成，用户侧表现为画面卡住后恢复或会话结束。会话结束也可能是自己点了返回或关闭了窗口。

## Driving it with computer use

Preconditions: 会话在 streaming 状态。

用户能做的收口（返回、关窗）走真实指针动作。用户做不到的故障（断网、杀进程）用命令通道注入，必须标为 `injected`：

```sh
# 人为断开，作为故障注入
./.scratch/stream-cmd.sh streamDisconnect

# 恢复
./.scratch/stream-cmd.sh streamResume
```

收口判定读探针：

```sh
D="$(xcrun simctl get_app_container <UDID> com.xiongzhipeng.Enchron data)/Documents"
grep -E "session end|input release|audio stop|stream content disappeared" "$D/stream-session-probe.log" | tail
```

后台与恢复读 `stream suspended for background`、`stream resuming after background` 与新会话的 `session start`。解码恢复读 `video surface bind`、`frame queue depth`。音频读 `audio interruption type= reason=`（visionOS 上 reason 3 表示场景进入后台）与 `audio engine start reason=framesWithoutEngine`。

## 证据

| 种类 | 判据 | 谁守 |
|---|---|---|
| 结构 | 会话结束路径释放输入、停止音频、归还渲染器，三条同时发生 | `StreamSessionCoordinator` 单测 |
| 结构 | 断连不销毁主机记录与会话窗口之外的界面状态 | 源码结构检查 |
| 物理 | 会话结束后探针三行齐备：`input release`、`session end`、`audio stop` | 探针 |
| 物理 | 结束后主窗口的Moonlight 标签页仍可操作，主机行仍在 | Agent 读截图 |
| 物理 | 中断后恢复，`streamSnapshot` 从 interrupted 回到 streaming | 控制面读数 |
| 感知 | 卡住时的等待感、有没有明确的提示 | **待做** |

## 证明的终态

断连的证明终点是「会话干净结束而 App 仍然可用」：探针三行齐备，且主窗口可以继续浏览与重新启动会话。

## Gotchas

- **断连注入对「用户点返回是否有效」失明。** 用命令通道断开跳过的是按钮的命中路径，因此这条注入不能作为返回控件可用的证据。
- **`stream content disappeared` 是窗口消失的收口行**，与 `session end` 不是同一件事，两条都要看。

## 本轮补齐范围（2026-10-26 裁决）

范围、阶段与验收见 `docs/reviews/streaming-port-review/plan.md`。

纳入：

- 断线后的重连入口与状态；当前只有注入式断开，用户侧没有恢复路径。
- 弱网提示。
- 失败原因分类，会话与呈现共用同一份数据源。
- 主机多地址带来的可达性切换记在 [串流主机](streaming-hosts.md)，不在本文件展开。

不做：会话内自动重启的触发面，维持现有的两类（显示模式切换、主机帧率不匹配）。
