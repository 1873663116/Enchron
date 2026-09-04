[← overview](overview.md)

# 阶段 16：session --mode human 与时间线轮询

## 目标

`session --mode human` 开录屏、起 console、轮询时间线。人类层的成员判定同时落地：账本终态 `deferred(human)` 的节点构成人类层，静态为空。

入口条件由 ledger 校验：同一节点连续两次 attempt 的 op 结果均为 harness 超时类。超时类的取值来自 `Scripts/verification/harness/CONTRACT.md:36` 的仪器故障 kind 清单，具体为 `transport-timeout`、`response-timeout`、`readyTimeout`、`ensure-session` 未 ready。产品慢是 `Violated`，写 `failed`，不可推迟。

## 改动清单

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
