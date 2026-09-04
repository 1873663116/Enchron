[← overview](overview.md)

# 阶段 12：bundle 工具

## 目标

`bundle` 产出异常包并以 image 内容块随返回值进入 Agent 上下文。异常包是 L2 归因的唯一输入：Agent 只在异常包之后做归因。

## 改动清单

- 新增 `Scripts/regression/tools/bundle_tool.py`。五件产物。`beforeAfter` 取失败 call 前后两张截图。`contactSheet` 从阶段 11 的分段录屏抽帧拼图，帧序号从 0 起连续编号，这个编号就是裁决里 `firstDeviantFrame` 的取值域，阶段 8 的 `admit_verdict` 按拼图帧数判越界。`crops` 按 rubric 中出现的 identifier 定位关键区域并裁切。`fieldDiff` 比对本次结构化字段与该 obligation 上一次 `passed` 的字段，只列出有差异的键。`matchedSignature` 汇总阶段 10 的 L1 启发命中的签名 id。
- 新增 `Scripts/regression/tools/signatures.py`。签名注册表。每个签名一个稳定 id、一条判据描述与它归属的判读层。`Verdict.signature` 只接受表内的 id，注册表之外的自由文本不进账本。
- 新增 `Scripts/rules/test_regression_bundle_tool.py`。覆盖：拼图帧数与返回的 `frameCount` 一致、`fieldDiff` 在无上一次 `passed` 时返回全量而不是空、裁切区域越界时返回明确拒绝、image 内容块数量与 `beforeAfter` 加 `contactSheet` 加 `crops` 相符。

三个新文件都不得含注释。

## 数据结构与形态

```python
ExceptionBundle(
    before_after: tuple[ImageBlock, ImageBlock],
    contact_sheet: ImageBlock,
    frame_count: int,
    crops: tuple[ImageBlock, ...],
    field_diff: Mapping[str, tuple[Any, Any]],
    matched_signature: tuple[SignatureID, ...],
)
```

```text
bundle --run-directory --node <NodeID> --attempt <n>
  -> ExceptionBundle 的 JSON 投影 + images
```

## 阶段验证方案

静态：

```sh
python3 Scripts/rules/run_verification.py --quick
python3 Scripts/rules/test_regression_bundle_tool.py
python3 Scripts/rules/check_recording_extractor.py
```

运行时（模拟器 lane）：

```sh
python3 Scripts/regression/tools/server.py --once op \
  --plan .scratch/harness-tools/plan.json \
  --run-directory .scratch/harness-tools/run \
  --node <已知会失败的 NodeID> --call <CallID>

python3 Scripts/regression/tools/server.py --once bundle \
  --run-directory .scratch/harness-tools/run \
  --node <同一 NodeID> --attempt 1
```

选一个当前已知失败的节点，或用 `Config/guard_selftests.json` 的手法在工作树副本上构造一次失败。异常包返回的 `frameCount` 必须与拼图上可数的帧格一致，`firstDeviantFrame` 取 `frameCount` 时被 `admit_verdict` 拒绝，取 `frameCount - 1` 时接受。这一对调用是帧序号越界判定在真实录屏上的证明。
