[← overview](overview.md)

# 阶段 10：op 工具与 L1 像素启发

## 目标

`op` 执行编译计划中的一个 Operation Call，返回 verdict、结构化字段与截图。判读的 L1 层在本阶段落地：1×1 捕获失败、全黑、帧差三条像素启发。L0 字段谓词的求值挂点同时留出，谓词本身由阶段 13 的编译器提供；在那之前 L0 对每个 obligation 返回「无可用谓词」，由 L1 与 L2 兜底。

## 改动清单

- 新增 `Scripts/regression/tools/op_tool.py`。调用序：从计划中取 `AllowedOperationCall`，经 `Scripts/regression/core/runtime.py` 的 `MainRun` gateway 授权，交 `Scripts/verification/regression_operation_adapter.py` 执行，拿回结构化输出与截图；先查阶段 8 的 `lane_lock_state`，lane 锁住时在授权之前拒绝，返回待裁决的 NodeID。gateway 授权、`result://` 引用解析与调用计数全部沿用既有实现，工具不重复这些校验。
- 新增 `Scripts/regression/tools/pixel_heuristics.py`。三个判据。`capture_failed(image)` 判 1×1，尺寸就是判据，不是画面全黑（`.agents/skills/vp-e2e/SKILL.md` 的证据一节）。`all_black(image, threshold)` 判全黑。`frame_delta(a, b) -> float` 给相邻帧的差值，供 bundle 定位首个偏离帧。三者返回命中的签名 id，不返回结论；结论由 `Verdict` 承载。
- 新增 `Scripts/rules/test_regression_op_tool.py`。覆盖：lane 锁住时 op 在授权之前被拒、1×1 截图命中 capture-failed 签名、全黑命中 all-black 签名、L0 无谓词时不伪装成通过。

三个新文件都不得含注释。

## 数据结构与形态

```text
op --plan <CompiledRunPlan> --run-directory --node <NodeID> --call <CallID>
  -> {verdict: Verdict, fields: Mapping[str, Any], signatures: tuple[SignatureID, ...]}
   + images: 本次调用的截图
```

```python
capture_failed(image: ImageBlock) -> SignatureID | None
all_black(image: ImageBlock, threshold: float) -> SignatureID | None
frame_delta(before: ImageBlock, after: ImageBlock) -> float
```

## 阶段验证方案

静态：

```sh
python3 Scripts/rules/run_verification.py --quick
python3 Scripts/rules/test_regression_op_tool.py
python3 Scripts/rules/verify_operation_evidence_payloads.py
python3 Scripts/rules/verify_regression_oracle_producers.py
```

运行时（模拟器 lane）：

```sh
python3 Scripts/regression/tools/server.py --once session \
  --mode agent --device <模拟器 UDID> --stage ensure \
  --execution-input .scratch/harness-tools/execution-input.json \
  --output-directory .scratch/<日期>-harness-tools/evidence

python3 Scripts/regression/tools/server.py --once op \
  --plan .scratch/harness-tools/plan.json \
  --run-directory .scratch/harness-tools/run \
  --node <MainGate NodeID> --call <首个 CallID>
```

选该 lane 的 MainGate Scenario 的首个 call：它按定义在其他 Scenario 之前运行，前置状态最少。返回值必须带非 1×1 的截图与非空结构化字段。随后在同一 lane 上故意让一个 call 失败并复跑，第二次调用应当被 lane 锁拒绝，这是护栏在真实设备上的唯一证明。
