[← overview](overview.md)

# 阶段 13：rubric 谓词编译器与覆盖报告

## 目标

从 `Regression/rubrics/` 的 97 份 rubric 生成 L0 字段谓词，编不出的 criterion 逐条进覆盖报告。rubric 文本一个字不改：编译器只读 front matter 里的 `criteria` 与 `negativeControls`。

`Regression/oracle-protocol.md` 现在写明「A rubric written as natural-language criteria is not called deterministic unless an exact field predicate implementation exists; the current Catalog has no such runtime Oracle.」本阶段让这句话的后半句不再成立，同时保留前半句的判定标准。

## 改动清单

- 新增 `Scripts/regression/rubric_compiler.py`。一个函数 `compile_rubric(rubric) -> CompiledRubric`。可编译的 criterion 是那些完全由「字段名、比较符、字面值」构成的断言，取值来自 Operation 的结构化输出：`mediaKind audioOnly`、`lifecycle Playing`、`controls=shown`、`exists false`、`isEnabled false`、有序 identifier 清单相等，都属于这一类。引用像素、跨调用时序对齐或需要读 interactionTrace 行序的 criterion 编不出，原样记入 `uncompiled`。编译器不做自然语言推断：匹配不上已登记的谓词形状就是编不出，不猜。
- 新增 `Scripts/rules/check_rubric_predicate_coverage.py`。Structure Check。跑编译器，输出覆盖报告：每份 rubric 的 criterion 总数、编出的条数、编不出的逐条原文与所属 obligation。它不因覆盖率低而失败，只在编译器崩溃、rubric front matter 不可解析、或覆盖率相比基线下降时失败。这与 `docs/CONTEXT.md` 的 Unguarded Evidence Point 是同一种处理：不假装覆盖，逐项列出。
- 新增 `Config/rubric_predicate_baseline.json`。覆盖率基线，按 `docs/CONTEXT.md` 的 Ratchet 约束：`--write-baseline` 拒绝写入任何使覆盖率下降的条目。
- `Scripts/rules/run_verification.py`。`STRUCTURE_CHECKS` 增一条 `StructureCheck("rubric-predicate-coverage", "check_rubric_predicate_coverage.py")`。新增检查受 Mutation Coverage Mandate 约束，须同时在 `Config/guard_selftests.json` 补一份坏样本，或写一份 `Scripts/rules/test_rubric_predicate_coverage.py` 自测。
- 新增 `Scripts/rules/test_rubric_predicate_coverage.py`。覆盖：字段谓词形状被编出、像素类 criterion 落入 `uncompiled`、front matter 缺 `criteria` 时明确拒绝、覆盖率下降时基线写入被拒。

阶段 10 的 `op_tool.py` 的 L0 挂点在本阶段接上 `CompiledRubric`，此前它对每个 obligation 返回「无可用谓词」。

新增的 Python 文件都不得含注释。

## 数据结构与形态

```python
FieldPredicate(field: str, operator: str, value: bool | int | str)

CompiledRubric(
    rubric_id: RubricID,
    predicates: tuple[FieldPredicate, ...],
    uncompiled: tuple[str, ...],
)

compile_rubric(rubric: Rubric) -> CompiledRubric
```

覆盖报告形状：

```text
{schema, rubricCount, criterionCount, compiledCount, byRubric: [{id, compiled, uncompiled: [原文]}]}
```

## 阶段验证方案

静态：

```sh
python3 Scripts/rules/run_verification.py --quick
python3 Scripts/rules/test_rubric_predicate_coverage.py
python3 Scripts/rules/check_rubric_predicate_coverage.py
python3 Scripts/rules/verify_guard_selftests.py
```

`check_rubric_predicate_coverage.py` 对全部 97 份 rubric 跑通并写出报告，是本阶段的完成判据。

运行时（模拟器 lane）：

```sh
python3 Scripts/regression/tools/server.py --once op \
  --plan .scratch/harness-tools/plan.json \
  --run-directory .scratch/harness-tools/run \
  --node <MainGate NodeID> --call <首个 CallID>
```

同一个节点在接上编译谓词前后各跑一次，返回的 verdict 必须一致，且第二次的 `signatures` 中出现 L0 层的命中记录。判读级别变了而结论不变，才说明谓词编对了。
