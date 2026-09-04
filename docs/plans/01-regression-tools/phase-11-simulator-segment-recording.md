[← overview](overview.md)

# 阶段 11：模拟器分段录屏与异常抽帧

## 目标

模拟器 lane 按 Scenario 分段录屏，异常时即时抽帧。真机沿用 XCTest 会话录屏，`halt` 之后由 `Scripts/verification/extract_visionpro_ui_recording.py` 从 `.xcresult` 取回，异常包在会话结束后生成；本阶段不改真机路径。

## 改动清单

- 新增 `Scripts/verification/harness/recording.py`。`start_segment` 起一个 `xcrun simctl io <udid> recordVideo` 子进程，输出路径落在 `TMPDIR/enchron-segments/<udid>/`：写仓库内路径被拒为 `NSCocoaErrorDomain 513`（`.agents/skills/vp-e2e/references/simulator.md:84`）。`stop_segment` 用 `SIGINT` 结束录制并把文件搬到 `--output-directory` 下的证据目录。段的边界是 Scenario：一个 Scenario 一段，段名绑定 NodeID 与 attempt。
- `Scripts/verification/extract_visionpro_ui_recording.py`。位置参数由 `result_bundle` 改名为 `source`，目录仍走 `.xcresult` 取回路径，文件走新增的 `segment_sources`。抽帧逻辑（`--fixed-interval` 默认 5.0、`--scene-threshold` 默认 0.35）复用，默认值不变。报告里的 `resultBundle` 键随之改为 `source`，此前无任何读取方。
- 新增 `Scripts/rules/test_harness_recording.py`，27 条。
- `Scripts/rules/check_recording_extractor.py` 增加第五项 `segment`：`segment_sources` 把它收到的那一个文件交给同一个容器谓词，而不是相信调用方给的后缀。它的负样本除了 runner stdout 日志，还有一个截断的 `.mp4`——后缀与文件名都与真段相同，只有容器读不出来，因此按后缀或按文件名放行的实现过不了这一项。

两个新文件不含注释，被修改的抽帧器与看守同样受该规则约束。

## 数据结构与形态

```python
Segment(
    udid: str,
    node: str,
    attempt: int,
    scenario: str,
    path: Path,
    process: subprocess.Popen,
)

start_segment(udid: str, node: str, attempt: int, scenario: str) -> Segment
stop_segment(segment: Segment, destination: Path) -> Path
recorder_command(udid: str, path: Path) -> list[str]
segment_filename(node: str, attempt: int) -> str
segment_root(udid: str) -> Path
temporary_root() -> Path

ACTIVE_SEGMENTS: dict[str, Segment]
```

## 与原清单的偏离

十处，都是实测或对抗审查撞上的事实：

- **段名把冒号编码成双连字符。** NodeID 的形状是 `node:<slug>(:<slug>)*`（`Scripts/regression/core/ids.py:83`），而 ffmpeg 把相对路径中第一个 `/` 之前的冒号读成协议前缀：在段所在目录下 `ffprobe node:playback:seek-1.mp4` 报 `Protocol not found`，`./node:playback:seek-1.mp4` 与绝对路径则正常。抽帧器的调用方是人和 Agent，谁都可能先 `cd` 进证据目录，因此段名里不留冒号。编码用 `--` 而不是 `-`：slug 的形状 `[a-z0-9]+(?:-[a-z0-9]+)*` 不含连续连字符，所以 `node:a-b:c` 与 `node:a:b-c` 不会塌缩到同一个名字。
- **`Segment` 带 `udid`。** 「同一台设备上一段没结束就不许起下一段」这条规则要有地方落。`ACTIVE_SEGMENTS` 以 udid 为键，`stop_segment` 得知道该销哪一格，段本身就是某台设备的录像。
- **`node` 与 `scenario` 是 `str` 而不是 `NodeID` 与 `ScenarioID`。** `harness` 包以 `Scripts/verification` 为导入根，`regression.core` 以 `Scripts` 为根；为了两个 `NewType`（运行时就是 `str`）让 `recording.py` 同时依赖两个根，是把包边界换成一行类型注解。包里其余十三个模块都没有这条边。
- **起录后确认录制真的开始。** simctl 在开始录制的瞬间就创建 0 字节的输出文件，结束时才写入内容——这给了一个不必解析 stderr 的就绪信号。`start_segment` 用 `harness.waits.wait_for` 轮询该文件，并在轮询中检查子进程是否已经退出；退出即取回它自己的 stderr 报出来。没有这一步，一个被拒绝的录制会返回一个看似正常的 `Segment`，直到 `stop_segment` 才发现没有字节。
- **两个函数只抛一种失败。** `wait_for` 超时抛的是 `InstrumentFault`，而拒绝与空段抛 `RecordingError`；同一个 `start_segment` 抛两种类型会让调用方漏接其中一种。超时被转换成 `RecordingError` 并把 `InstrumentFault` 挂在 `__cause__` 上。本模块不进 `INSTRUMENT_KINDS`：录屏是取证通道，不是 `RecoveryPolicy` 会重试的观测。
- **argv 由 `recorder_command` 单独产出。** 自测替换这一个函数，用一段模仿 simctl 的 Python 占位程序跑真实的 `Popen`、真实的 `SIGINT` 与真实的落盘，同时另有一条断言把真实 argv 逐项钉死。若在自测里替换 `subprocess.Popen`，被验证的就只剩替身。
- **段按设备分目录。** `TMPDIR` 在 macOS 上是 per-user 而不是 per-process，`ACTIVE_SEGMENTS` 只在进程内。两台设备跑同一个 NodeID 的 attempt 1 时（fan-out 下 attempt 编号按节点计，两台设备都从 1 开始），两个录制器写同一个路径：先起的那个的文件被后起的 `_clear` 删掉，`await_recorder` 的就绪信号被对方的 0 字节文件满足，最后两次 `stop_segment` 都报成功而证据目录里只有一个文件。段落进 `TMPDIR/enchron-segments/<udid>/` 之后，文件名仍然只绑定 NodeID 与 attempt。
- **归档拒绝覆盖。** `shutil.move` 的目标是完整文件路径而不是目录，它自带的「目标已存在」保护因此从不触发：同盘走 `os.rename`、跨盘走 `copy2`，两条都直接盖掉。重复跑同一个节点会把上一次的证据换掉并返回成功。现在同名已存在就拒绝。
- **`stop_segment` 按身份而不是按键释放设备。** 原先 `ACTIVE_SEGMENTS.pop(udid)` 会把当前正在录的那一段从表里摘掉，即使传进来的是一段早就停掉的旧段。一个 `finally` 里的重复 stop 就足以让在录的录制器永远收不到 `SIGINT`，并让第三个录制器在同一台设备上起来。现在传进来的段不是该设备正在录的那一段就直接拒绝。
- **`TMPDIR` 落在仓库内直接拒绝。** `Scripts/verification/enchron_artifact_paths.sh:10` 把 `TMPDIR` 指向 `.scratch/Temporary`，四个脚本 source 它。在那套环境下 simctl 会拒绝写入，报的是子进程的 `NSCocoaErrorDomain 513`。`temporary_root` 自己先拒绝，把约束说在它成立的地方。

`start_segment` 在起录前清掉同路径的残留：simctl 拒绝写入已存在的路径（`NSPOSIXErrorDomain 17`，`cannot save recorded video output into a file that already exists`），因此一次崩溃留下的旧段会让后续每一次同 NodeID 同 attempt 的录制失败。清理认 `lexists` 而不是 `exists`，否则一个断链的符号链接留在原地，simctl 仍然报 17；路径上是目录时明确拒绝，而不是让 `unlink` 抛出裸 `PermissionError`。

对抗审查在已启动的模拟器上核实了两件本可以成为缺陷的事：`xcrun` 是 exec 而不是 fork，`Popen` 拿到的 pid 就是 simctl 本身，`SIGINT` 直达；整个录制期间 simctl 只往 stderr 写 131 字节且都在起录时写完，因此不读 stderr 不会把管道写满。

## 阶段验证方案

静态：

```sh
python3 Scripts/rules/run_verification.py --quick
python3 Scripts/rules/test_harness_recording.py
python3 Scripts/rules/check_recording_extractor.py
```

运行时（模拟器 lane）。段的起停不依赖计划编译，直接对着一台已启动的模拟器验证：

```sh
python3 - <<'PY'
import sys, time
from pathlib import Path
sys.path.insert(0, "Scripts/verification")
from harness.recording import start_segment, stop_segment

segment = start_segment("<模拟器 UDID>", "node:playback:seek", 1, "scenario:playback:seek")
time.sleep(4)
print(stop_segment(segment, Path(".scratch/<日期>-harness-tools/evidence/segments")))
PY

python3 Scripts/verification/extract_visionpro_ui_recording.py \
  .scratch/<日期>-harness-tools/evidence/segments/node--playback--seek-1.mp4 \
  .scratch/<日期>-harness-tools/evidence/frames
```

证据目录下应有一个非空 `.mp4` 分段，抽帧命令从它产出多张帧。分段与帧的存在就是本阶段的判据。

实测：4 秒的段 10309440 字节，`recording-index.json` 报 `origin=simulator segment`、3840×2160、h264，抽出两帧；两帧交给阶段 10 的 `all_black` 与 `capture_failed` 都不触发。
