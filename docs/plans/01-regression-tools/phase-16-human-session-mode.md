[← overview](overview.md)

# 阶段 16：session --mode human 与时间线轮询

## 目标

`session --mode human` 开录屏、起 console、轮询时间线。人类层的成员判定同时落地：账本终态 `deferred(human)` 的节点构成人类层，静态为空。

入口条件由 ledger 校验：同一节点连续两次 attempt 的 op 结果均为 harness 超时类。超时类的取值来自 `Scripts/verification/harness/CONTRACT.md:36` 的仪器故障 kind 清单，具体为 `transport-timeout`、`response-timeout`、`readyTimeout`、`ensure-session` 未 ready。产品慢是 `Violated`，写 `failed`，不可推迟。

## 前置阻塞：账本里没有第二次 attempt

重开节点的设计与取舍记在[阶段 15](phase-15-known-defect-ledger.md)，本阶段的 `deferrable` 直接读那条规则产出的 attempt 序列。

## 改动清单

- `Scripts/regression/core/runview.py`。`_record_verdict` 的裁决准入表放行 `deferred(human)`：阶段 8 只允许 INDETERMINATE 聚合写 `indeterminate`，因为 `DEFERRED_HUMAN` 不属于 `PRODUCT_NODE_STATUSES`，绕过证据义务并释放 lane，在 `deferrable` 存在之前是一个无人把守的出口。本阶段与该函数一并放行。
- `Scripts/regression/tools/ledger_lock.py`。增一个函数 `deferrable(view, node) -> bool`。读该节点的两次最近 attempt，两次都是超时类才返回真。产品侧的慢、断言不匹配、崩溃都返回假。判定读的是仪器故障 kind，不读耗时数值：耗时长短由 `Scripts/verification/harness/budgets.py` 的预算体系折算成 `provisional-budget-expired`，那也是仪器故障，与产品慢是两回事。
- `Scripts/regression/tools/session_tool.py`。`--mode human` 落地：起阶段 11 的分段录屏，起 console，每 2 到 3 秒轮询一次 `snapshot --no-screenshot`、控制面字段与 PlaybackCore 的容器内 `tmp/playbackcore-live-debug/current.json`，逐行写 `timeline.jsonl`。接受 `mark` 打标，把人在此刻的标记写进同一条时间线。`halt` 时停录屏并取回。
- 新增 `Scripts/rules/test_regression_human_session.py`。覆盖：连续两次超时才可 defer、一次超时加一次产品失败不可 defer、`timeline.jsonl` 每行是合法 JSON 且时间戳单调、`mark` 落在正确的时间点、`halt` 之后录屏文件存在。

新增文件不得含注释。

## 数据结构与形态

```python
deferrable(view: RunView, node: NodeID) -> bool
```

```text
session --mode human --device <UDID> --stage ensure --checklist <deferred 节点清单>
  -> {stage, timeline: Path, recording: Path, consoleReady: bool}
```

`timeline.jsonl` 每行：

```text
{at, source: snapshot|controlPlane|playbackCore|mark, payload}
```

## 与原清单的偏离

六处：

- **仪器故障的 kind 原本根本不进账本。** `_harness_recovered` 在 `Halt` 时把 `InstrumentFault` 原样抛出（`regression_operation_adapter.py:82-84`），`op_tool` 让它逃逸成工具错误，因此调用输出里只有产品失败带 kind，仪器失败连一条记录都没有。`deferrable` 于是无据可依。现在 `op_tool` 捕获它，把 `failure.class=instrument` 与 kind 记进该次调用的 outputs：一次尝试失败在仪器上，这是关于这次 attempt 的事实，本来就该进账本。
- **超时类的取值按本仓库的实际清单对账。** 原清单写的 `response-timeout` 不在 `harness/CONTRACT.md:36` 的仪器故障 kind 里；`readyTimeout` 是 `ensure-session` 的一个阶段，压根到不了 op 调用。实际可用的超时类是 `transport-timeout`、`wait-expired`、`provisional-budget-expired`，`HARNESS_TIMEOUT_KINDS` 就是这三个。
- **入口条件在回放层执行，工具层同一条规则再拒一次。** `deferrable_from` 长在 `runview.py`，`_record_verdict` 用它拦住任何不满足条件的 `deferred(human)`，因此一份手写的账本回放不过去——这是阶段 8 定下的原则。`admit_verdict` 用同一个函数在写入前给出可读的拒绝理由，排在 Oracle 结果检查之后：一个 `Violated` 的节点该听到的是「Oracle 结果是 violated」，而不是人类层的门槛。
- **重开机制随阶段 15 落地。** 「同一节点连续两次 attempt」的前提是节点能跑第二次，那部分与已知缺陷账本同批提交。
- **`poll_timeline` 的休眠由调用方传入，没有默认值。** `Scripts/regression/tools/` 禁用 `time.sleep`，`harness_primitives_gate` 在门禁上抓到了这一行。这条规则是对的：`tools/` 里的工具不该自己决定睡多久。休眠成为一个必填参数，console 传它进来。
- **`session --mode human` 的时间线可测，佩戴者循环未验证。** `poll_timeline`、`mark`、`read_timeline` 接受注入的读数、时钟与休眠，因此每行是合法 JSON、时间戳单调、`mark` 落在它之后的读数之前这三条都由自测钉住。真正驱动佩戴者会话的那半部分需要一台真机和一个人，本次没有跑过，不声称跑过。

## 阶段验证方案

静态：

```sh
python3 Scripts/rules/run_verification.py --quick
python3 Scripts/rules/test_regression_human_session.py
python3 Scripts/rules/test_regression_ledger_lock.py
```

运行时（模拟器 lane）：

```sh
python3 Scripts/regression/tools/server.py --once session \
  --mode human --device <模拟器 UDID> --stage ensure \
  --execution-input .scratch/harness-tools/execution-input.json \
  --output-directory .scratch/<日期>-harness-tools/evidence

python3 Scripts/regression/tools/server.py --once session \
  --mode human --device <模拟器 UDID> --stage halt
```

console 起来之后手动操作模拟器若干步并打一次 mark，`halt` 之后检查 `timeline.jsonl` 的行数与时间戳单调、mark 落在操作之后、录屏分段非空。人类层的完整流程在真机上才有意义，模拟器 lane 能证明的是轮询、打标与录屏取回三条通路都通。
