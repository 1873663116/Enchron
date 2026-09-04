[← overview](overview.md)

# 阶段 11：模拟器分段录屏与异常抽帧

## 目标

模拟器 lane 按 Scenario 分段录屏，异常时即时抽帧。真机沿用 XCTest 会话录屏，`halt` 之后由 `Scripts/verification/extract_visionpro_ui_recording.py` 从 `.xcresult` 取回，异常包在会话结束后生成；本阶段不改真机路径。

## 改动清单

- 新增 `Scripts/verification/harness/recording.py`。两个函数。`start_segment(udid, scenario_id) -> Segment` 起一个 `xcrun simctl io <udid> recordVideo` 子进程，输出路径必须落在 `TMPDIR`：写仓库内路径会被拒为 `Operation not permitted`（`.agents/skills/vp-e2e/references/simulator.md`）。`stop_segment(segment) -> Path` 结束录制并把文件搬到 `--output-directory` 下的证据目录。段的边界是 Scenario：一个 Scenario 一段，段名绑定 NodeID 与 attempt。
- `Scripts/verification/extract_visionpro_ui_recording.py`。当前只接受 `.xcresult` 作为 `result_bundle` 位置参数（:354）。扩为同时接受一个 `.mp4` 分段路径，抽帧逻辑（`--fixed-interval` 默认 5.0、`--scene-threshold` 默认 0.35）复用，不改默认值。
- 新增 `Scripts/rules/test_harness_recording.py`。覆盖：段路径落在 `TMPDIR`、段名绑定 NodeID 与 attempt、`stop_segment` 之后文件存在且非空、同一 Scenario 起第二段前上一段已结束。

`Scripts/rules/check_recording_extractor.py` 是既有的 Structure Check，看守抽帧器；扩参数后跑它确认约束仍成立。

两个新文件不得含注释，被修改的抽帧器同样受该规则约束。

## 数据结构与形态

```python
Segment(
    node: NodeID,
    attempt: int,
    scenario: ScenarioID,
    path: Path,
    process: subprocess.Popen,
)

start_segment(udid: str, node: NodeID, attempt: int, scenario: ScenarioID) -> Segment
stop_segment(segment: Segment, destination: Path) -> Path
```

## 阶段验证方案

静态：

```sh
python3 Scripts/rules/run_verification.py --quick
python3 Scripts/rules/test_harness_recording.py
python3 Scripts/rules/check_recording_extractor.py
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

python3 Scripts/verification/extract_visionpro_ui_recording.py \
  .scratch/<日期>-harness-tools/evidence/segments/<NodeID>-1.mp4 \
  .scratch/<日期>-harness-tools/evidence/frames
```

跑完一个 Scenario 后，证据目录下应有一个非空 `.mp4` 分段，抽帧命令从它产出多张帧。分段与帧的存在就是本阶段的判据。
