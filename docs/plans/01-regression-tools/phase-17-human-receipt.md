[← overview](overview.md)

# 阶段 17：人类收据与 receipt 工具

## 目标

人类回归产出一份收据，收据覆盖的节点 id 与 Agent 账本关闭的节点合起来决定收据能否生成。任一 tier 的节点要么由 Agent 账本关闭，要么由覆盖该节点 id 的人类收据关闭。W3 等于真机 lane 节点全部关闭，由谁关闭不限。

## 改动清单

- 新增 `Scripts/regression/tools/human_receipt.py`。两个函数。`build_checklist(view) -> Checklist` 从账本终态为 `deferred(human)` 的节点生成 checklist，人可以扩大范围，扩大后的清单进 `checklistDigest`。`seal(checklist, timeline, recording, attributions) -> HumanReceipt` 把人点完之后的自然语言描述、Agent 按 checklist 顺序与时间线对齐后的抽帧与归因，封成收据。逐条归因用阶段 7 的 `Attribution` 枚举，不用自由文本。
- 新增 `Scripts/regression/tools/receipt_tool.py`。从账本算合并收据：全部节点已关闭时返回收据，否则返回拒绝理由与未关闭的节点清单。`failed(known)` 视为已关闭，`deferred(human)` 只有被人类收据覆盖才算关闭。
- 新增 `Scripts/rules/test_regression_human_receipt.py`。覆盖：checklist 由 `deferred(human)` 节点生成、人扩大范围后 digest 改变、收据缺任一 digest 时拒绝封存、未覆盖的 `deferred(human)` 节点使合并收据被拒、`failed(known)` 不阻塞收据。

新增文件不得含注释。

## 数据结构与形态

```python
HumanReceipt(
    checklist_digest: Digest,
    build_digest: Digest,
    device_id: str,
    recording_digest: Digest,
    attributions: tuple[NodeAttribution, ...],
)

NodeAttribution(node: NodeID, attribution: Attribution, description: str, frames: tuple[int, ...])
```

```text
receipt --run-directory [--human-receipt <path>]
  -> 收据 | {refused: 理由, openNodes: [NodeID]}
```

## 阶段验证方案

静态：

```sh
python3 Scripts/rules/run_verification.py --quick
python3 Scripts/rules/test_regression_human_receipt.py
python3 Scripts/rules/test_regression_known_defects.py
```

运行时（模拟器 lane）：

```sh
python3 Scripts/regression/tools/server.py --once ledger \
  --run-directory .scratch/harness-tools/run --view

python3 Scripts/regression/tools/server.py --once receipt \
  --run-directory .scratch/harness-tools/run
```

在有未关闭节点时 `receipt` 返回拒绝与节点清单；把这些节点关闭后再跑一次，返回收据。人类收据这一半在模拟器 lane 无法真正证明，因为 `deferred(human)` 的入口条件是连续两次 harness 超时，模拟器上难以稳定构造。模拟器 lane 能证明的是收据的拒绝路径与 `failed(known)` 的放行路径；人类收据路径的证明留到真机 lane 的一次人类回归。
