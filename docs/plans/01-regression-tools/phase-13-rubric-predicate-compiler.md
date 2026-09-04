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

## 与原清单的偏离

四处：

- **谓词从 criterion 的句子里抽，不要求整条 criterion 是一个断言。** 实测 97 份 rubric 的 199 条 criterion，长度中位数 327 字符，最短 77 字符，没有一条是裸的字段断言。要求整条匹配，编译器的产出恒为 0。改为在句子粒度上匹配已登记的断言形状。定稿时产出 48 个谓词覆盖 47 条 criterion，其中 30 个来自 `requireMatchedElement`——那是入参而非输出，恒为 `indeterminate`；移出字段表后实际产出 18 个谓词，覆盖 17 条 criterion。原清单举的例子（`mediaKind audioOnly`、`lifecycle Playing`、`controls=shown`）本来就是片段而不是整条 criterion。
- **含否定标记的句子不产谓词。** `negativeControls` 整段都是「…fails the bound case」的写法，`criteria` 里也有「no reading of mediaKind video is admissible」这类句子。从这些句子里抽片段会把断言的极性抽反，把一条禁止写成一条要求。判定读的是一张登记的否定词表，命中就整句跳过，不做进一步的语义推断。
- **报告的计数叫 `criteriaYieldingPredicates`，不叫「已覆盖」。** 一条产出谓词的 criterion 只是其中的字段断言被机械化了，同一条 criterion 的其余部分仍然由 Agent 判读。把这个数读成覆盖率会高估确定性判读的范围。
- **L0 挂点从计划里读 rubric，不读 Catalog。** `RubricEvaluationBinding`（`plan.py:796`）已经带着 `criteria` 的原文，因此 `op_tool.field_predicates` 直接编译它，不需要 op 再加载一次 Catalog。它逐条给出读数：字段相等是 `satisfied`，不等是 `violated` 并附上实际读到的值，这次调用没有报告该字段是 `indeterminate`——缺席的读数没有确立任何东西。

`Regression/oracle-protocol.md:15` 那句「the current Catalog has no such runtime Oracle」在阶段 19 按实际覆盖率改写：17 条 criterion 编出字段谓词，其余 182 条是自然语言判读，覆盖报告逐条列出。谓词的读数由 `op` 附在调用旁边供人看，不参与任何 obligation 结果，因此改写后的那一段不称它为「确定性判读」。

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
