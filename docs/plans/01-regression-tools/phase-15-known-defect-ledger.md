[← overview](overview.md)

# 阶段 15：已知缺陷账本

## 目标

Scenario 层的已知缺陷账本，终态 `failed(known)` 不阻塞收据。已知缺陷与普通失败在账本上是两个不同的终态，不是同一个终态加一条豁免注释。

## 改动清单

- 新增 `Config/regression/known_defects.json`。逐条：Scenario ID、缺陷描述、命中判据（签名 id 或字段谓词）、录入日期、失效条件。失效条件是这条记录何时必须被重新审视，留空即拒绝录入。
- 新增 `Scripts/regression/tools/known_defects.py`。一个函数 `classify(verdict, fields) -> NodeStatus`。命中账本中某条记录的判据时返回 `FAILED_KNOWN`，否则返回 `FAILED`。命中判定用签名 id 或阶段 13 的 `FieldPredicate`，不用自由文本匹配。
- `Scripts/regression/tools/ledger_tool.py`。`write` 动作在写入 `FAILED` 之前先过 `classify`。
- 新增 `Scripts/rules/test_regression_known_defects.py`。覆盖：命中记录写入 `failed(known)`、未命中写入 `failed`、缺 `失效条件` 的记录被拒、`failed(known)` 不进入 lane 锁的待裁决集合、`failed(known)` 不阻塞收据。

新增的 Python 文件不得含注释。

## 数据结构与形态

```python
KnownDefect(
    scenario: ScenarioID,
    description: str,
    match: SignatureID | FieldPredicate,
    recorded: date,
    expires_when: str,
)

classify(verdict: Verdict, fields: Mapping[str, Any]) -> NodeStatus
```

## 阶段验证方案

静态：

```sh
python3 Scripts/rules/run_verification.py --quick
python3 Scripts/rules/test_regression_known_defects.py
python3 Scripts/rules/test_regression_ledger_lock.py
```

运行时（模拟器 lane）：

```sh
python3 Scripts/regression/tools/server.py --once op \
  --plan .scratch/harness-tools/plan.json \
  --run-directory .scratch/harness-tools/run \
  --node <已录入已知缺陷的 NodeID> --call <CallID>

python3 Scripts/regression/tools/server.py --once ledger \
  --run-directory .scratch/harness-tools/run --view
```

对一个已录入的 Scenario 跑一次 op，账本视图中该节点为 `failed(known)`，且它所在 lane 的 `LaneLock.locked` 为假。这一对返回值证明已知缺陷既被记录也不挡路。
