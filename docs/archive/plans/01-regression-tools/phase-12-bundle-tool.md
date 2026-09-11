[← overview](overview.md)

# 阶段 12：bundle 工具

## 目标

`bundle` 产出异常包并以 image 内容块随返回值进入 Agent 上下文。异常包是 L2 归因的唯一输入：Agent 只在异常包之后做归因。

## 改动清单

- 新增 `Scripts/regression/tools/bundle_tool.py`。`beforeAfter` 取偏离 call 前后两张截图。`contactSheet` 把异常包持有的帧拼成一张图，帧序号从 0 起连续编号，这个编号就是裁决里 `firstDeviantFrame` 的取值域，阶段 8 的 `admit_verdict` 按拼图帧数判越界。`crops` 逐条说明为什么产不出而不是按猜的比例裁切。`fieldDiff` 给出偏离 call 的结构化字段。`matchedSignature` 汇总 L1 启发命中的签名 id。
- 新增 `Scripts/regression/tools/signatures.py`。签名注册表。每个签名一个稳定 id、一条判据描述与它归属的判读层。`Verdict.signature` 只接受表内的 id，注册表之外的自由文本不进账本。阶段 10 的两个 id 从这里取，注册表再加一条 `signature:frame-unchanged`。
- 新增 `Scripts/regression/tools/raster.py`。PNG 的解码从 `pixel_heuristics.py` 搬进来，另加编码、裁切、缩放与拼图。
- `Scripts/regression/tools/server.py`。`bundle` 从 `_pending` 换成实工具，`ExceptionBundle` 的每张图以 `ImageBlock` 随返回值发出。
- 新增 `Scripts/rules/test_regression_bundle_tool.py`（18 条）、`Scripts/rules/test_regression_raster.py`（25 条）、`Scripts/rules/test_regression_signatures.py`（6 条）。

新增文件都不含注释。

## 数据结构与形态

```python
BundleImage(caption: str, png: bytes)

ExceptionBundle(
    node: NodeID,
    attempt: int,
    call: CallID,
    before_after: tuple[BundleImage, ...],
    contact_sheet: BundleImage | None,
    frame_count: int,
    crops: tuple[BundleImage, ...],
    crop_refusal: str | None,
    field_diff: Mapping[str, tuple[Any, Any]],
    matched_signature: tuple[SignatureID, ...],
)

Signature(id: SignatureID, tier: AdjudicationTier, criterion: str)
```

```text
bundle --run-directory --node <NodeID> --attempt <n>
  -> ExceptionBundle 的 JSON 投影 + images
```

## 与原清单的偏离

九处：

- **`raster.py` 是第四个新文件。** `Scripts/regression/tools/` 被 `harness_primitives_gate.py` 禁用 `subprocess`，所以拼图与裁切不能走 ffmpeg，得有一个纯标准库的编码器。解码原本长在 `pixel_heuristics.py` 里，编码、裁切与拼图跟它是同一件事，一起搬进 `raster.py`；`pixel_heuristics.py` 只留判定签名的部分。`PixelHeuristicError` 随之改名为 `RasterError`，一个错误一个家。
- **`ExceptionBundle` 携带字节与说明，不携带 `ImageBlock`。** `ImageBlock` 是 `server.py` 的 MCP 编码形态，工具反过来导入 server 会把依赖方向倒过来。`op` 已经是这个分工：工具返回字节，server 包成内容块。
- **拼图的帧就是异常包自己持有的截图。** 没有任何阶段把阶段 11 的分段落进 run 目录，因此没有可抽帧的段。`frameCount` 报的是异常包实际持有的帧数，拼图上可数的帧格与它相等；段接进来之后帧源扩大，编号规则不变。
- **`crops` 逐条说明为什么产不出。** `matchedElement.frame` 的单位是点（`InteractiveDeviceUITests.swift:692`），截图是像素，而响应里没有任何字段记录屏幕的点尺寸，推不出点到像素的比例。按猜的比例裁切会把错误的区域配上裁决里的区域观察文字，这比不裁更糟。`crop_refusal` 把缺的那一项说出来，与 `docs/CONTEXT.md` 的 Unguarded Evidence Point 是同一种处理。
- **`fieldDiff` 总是给出全量字段。** 账本禁止同一个 obligation 在一个 lease 上被评估两次（`runview.py:1507`），而一个节点最多只有一个 lease，因此一次 run 内不存在「上一次 `passed`」可比。原清单的自测项「无上一次 `passed` 时返回全量而不是空」在当前模型下是唯一情形，不是边界情形。
- **偏离 call 就是最后一个完成的 call。** 一个 call 失败会结束该 lease，后面的 call 不再执行，所以「最后一个失败的 call」与「最后一个完成的 call」在账本里恒等。原先写的向前搜索删掉了。
- **`--attempt` 解释为该节点 lease 的序号。** 账本里没有 attempt 这个字段：`_claim_node` 要求节点处于 `PENDING`，而没有任何路径把节点写回 `PENDING`，因此一次 run 内一个节点只能被 claim 一次。越界的 attempt 被拒绝并说明这一点。**阶段 15 与阶段 16 建立在「同一节点连续两次 attempt」之上，当前状态机不允许，那两个阶段必须先解决重试如何进账本。**
- **`op_tool._screenshot` 公开为 `screenshot_bytes`。** 异常包与 op 用同一条规则从 Operation 输出里找截图路径，抄一份就会分叉。
- **`signature:frame-unchanged` 由 bundle 产出。** 阶段 10 的 `frame_delta` 返回一个比值，没有阈值就不是签名。前后两帧的比值低于 `UNCHANGED_FRAME_DELTA` 时记这条签名：这一步没有改变屏幕。

## 阶段验证方案

静态：

```sh
python3 Scripts/rules/run_verification.py --quick
python3 Scripts/rules/test_regression_bundle_tool.py
python3 Scripts/rules/test_regression_raster.py
python3 Scripts/rules/test_regression_signatures.py
python3 Scripts/rules/check_recording_extractor.py
```

运行时（模拟器 lane）。`op` 就地编译计划，不接 `--plan`：

```sh
python3 Scripts/regression/tools/server.py --once op \
  --repository-root . \
  --execution-input .scratch/harness-tools/execution-input.json \
  --catalog-root Regression --policy Regression/policy.json \
  --reviews-root Regression/reviews --blueprint Regression/blueprint.json \
  --run-directory .scratch/harness-tools/run \
  --node <已知会失败的 NodeID> --call <CallID> \
  --lane simulator --target <模拟器 UDID> --sidekick sidekick:one

python3 Scripts/regression/tools/server.py --once bundle \
  --run-directory .scratch/harness-tools/run \
  --node <同一 NodeID> --attempt 1
```

选一个当前已知失败的节点，或用 `Config/guard_selftests.json` 的手法在工作树副本上构造一次失败。异常包返回的 `frameCount` 必须与拼图上可数的帧格一致，`firstDeviantFrame` 取 `frameCount` 时被 `admit_verdict` 拒绝，取 `frameCount - 1` 时接受。这一对调用是帧序号越界判定的证明。
