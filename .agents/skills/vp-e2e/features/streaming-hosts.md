# 串流主机

串流标签页维护一个主机列表：添加主机、与主机配对、读取主机提供的应用清单。侧栏选中哪一台主机，右侧内容列就显示那一台的细节与应用网格，两者必须始终一致。

## Sub-features

- 空状态下提供「添加主机」入口；已有主机时入口在侧栏的加号上。
- 添加表单支持手填地址，也支持从发现结果里挑一个地址添加。
- 提交表单后主机出现在侧栏，配对状态可读。
- 与未配对主机配对：App 给出 PIN，主机端确认后状态转为已配对。
- 选中侧栏任意一行，内容列切换到该主机的名称、地址、配对状态与应用网格。
- 应用网格读取主机提供的应用清单；清单读取失败时给出可见的失败说明，并仍然渲染首选条目的缺失位。
- 移除主机需要二次确认；确认后该行消失。

## How to get to it (user POV)

主窗口底部的导航栏切到串流标签页。侧栏顶部是主机列表，右上角是加号。空状态下内容列本身就是添加入口。

点加号打开添加表单，填地址提交。主机出现后点这一行，内容列换成详情；未配对时详情里出现配对按钮，点击后弹出 PIN。

## Driving it with computer use

Preconditions: 同[串流呈现](streaming-presentation.md)。测试通道已建立，`Documents/test-commands/` 与 `Documents/test-responses/` 为空。

导航与配对确认走真实指针动作。主机侧的 PIN 确认在 Sunshine 的 Web UI 上完成，属于 `host-sunshine` 证据：

```sh
python3 Scripts/verification/device_hub_canvas.py --device <UDID> pinch --shot-x <x> --shot-y <y> --shot-width 3840 --shot-height 2160
```

配对状态与主机行内容读产品自己发布的 accessibilityValue：

```sh
./.scratch/stream-cmd.sh streamSnapshot '{}'
```

主机的真实配对记录落在容器的 `Library/Application Support/Enchron/streaming-hosts.json`，客户端证书在同目录的 `moonlight-identity/`。这两份随容器存活，覆盖安装不丢。

## 证据

| 种类 | 判据 | 谁守 |
|---|---|---|
| 结构 | 侧栏选中的主机 ID 与内容列渲染的主机 ID 是同一个 | `StreamingModel` 单测 |
| 结构 | 添加表单的提交走生产入库路径，不直接写 `streaming-hosts.json` | 源码结构检查 |
| 物理 | 配对完成后 `streaming-hosts.json` 中该主机 `hasPairingRecord` 为真 | 容器文件读取 |
| 物理 | 点侧栏每一行，内容列的主机名与地址随之改变 | Agent 读截图 |
| 感知 | 表单的填写手感、错误提示的清晰度 | **待做** |

## 证明的终态

一次会话建立前，主机必须同时满足：侧栏存在该行、内容列的详情指向同一台主机、`hasPairingRecord` 为真、应用清单非空。四条缺一条都不能进入启动单元。

## Gotchas

- **侧栏与内容列的一致性只由产品保证。** 用命令通道直接改状态会绕过选择逻辑，因此这条一致性的唯一有效驱动是真实点击侧栏的每一行。
- **配对记录在容器里，不在 App 包里。** 覆盖安装保留配对；删 App 或抹掉容器才会丢。
- **模拟后端会混入应用清单。** 见[串流呈现](streaming-presentation.md)的 Gotchas。
