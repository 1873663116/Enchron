[← overview](overview.md)

# 阶段 10：op 工具与 L1 像素启发

## 目标

`op` 执行编译计划中的一个 Operation Call，返回 verdict、结构化字段与截图。判读的 L1 层在本阶段落地：1×1 捕获失败、全黑、帧差三条像素启发。L0 字段谓词的求值挂点同时留出，谓词本身由阶段 13 的编译器提供；在那之前 L0 对每个 obligation 返回「无可用谓词」，由 L1 与 L2 兜底。

## 改动清单

- 新增 `Scripts/regression/tools/op_tool.py`。调用序：从计划中取 `AllowedOperationCall`，经 `Scripts/regression/core/runtime.py` 的 `MainRun` gateway 授权，交 `Scripts/verification/regression_operation_adapter.py` 执行，拿回结构化输出与截图；先查阶段 8 的 `lane_lock_state`，lane 锁住时在授权之前拒绝，返回待裁决的 NodeID。gateway 授权、`result://` 引用解析与调用计数全部沿用既有实现，工具不重复这些校验。
- 新增 `Scripts/regression/tools/pixel_heuristics.py`。三个判据。`capture_failed(image)` 判 1×1，尺寸就是判据，不是画面全黑（`.agents/skills/vp-e2e/SKILL.md` 的证据一节）。`all_black(image, threshold)` 判全黑。`frame_delta(a, b) -> float` 给相邻帧的差值，供 bundle 定位首个偏离帧。三者返回命中的签名 id，不返回结论；结论由 `Verdict` 承载。
- 新增 `Scripts/rules/test_regression_op_tool.py`。覆盖：lane 锁住时 op 在授权之前被拒且账本不增一条事件、越序调用被按名拒绝、调度器不提供该节点时被拒、1×1 截图命中 capture-failed 签名、全黑命中 all-black 签名、L0 无谓词时不伪装成通过。
- 新增 `Scripts/rules/test_regression_pixel_heuristics.py`。像素模块自成一体且不碰设备，自测埋进 op 工具的文件里会被淹没。覆盖五种 filter 的重建、四种通道数、每一类畸形 PNG 的拒绝，以及三条启发各自的边界。

四个新文件都不得含注释。

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

## 与原清单的偏离

六处，都是实现时撞上的事实：

- **`plan.json` 只写不读。** `plan.py` 有 `compiled_plan_payload`／`compiled_plan_bytes`，没有任何反向路径，仓库里也没有第二处把它读回 `CompiledRunPlan`。因此 overview 全量验证一节里的 `server.py --once op --plan plan.json` 目前无法成立。本阶段不补 loader——那是一个跨十余个嵌套类型、且必须让 `plan_digest` 精确往返的独立工程；`op` 改为接 `runctl compile` 的同一组入参就地编译。正确性不靠自觉：`open_run` 经 `_write_plan_once`（`runtime.py:1926`）把编译结果与 run 目录里既有的 `plan.json` 逐字节比对。这个缺口目前没有任何阶段认领，若编译耗时成为问题，plan loader 就是那件该做的事。
- **本阶段不提交证据。** op 授权并执行一个 call 就停。这样是安全的：`invoke_operation` 返回前已写入 `OPERATION_INVOKED` 与 `OPERATION_COMPLETED`，invocation 不是 uncertain，下一次 `open_run` 的恢复不会中断 lane；成功则 cursor 前进一格，lease 保持 ACTIVE，`accept_evidence` 在 cursor 走完之后仍然可用。`EvidenceEnvelope` 与 Oracle 判读留给后续阶段。
- **租约时长改为四小时。** `claim` 的默认值是 60 秒（`runtime.py:88`）。op 是一次调用一个进程的工具，60 秒必然过期，而 `capability.expired_lease` 会直接中断 lane。deadline 在 claim 时冻结，无法延长。
- **`_capability_for_lease` 公开为 `capability_for_lease`。** 只有第一次 `claim` 能拿到 capability，后续调用必须从 lease 视图重建，而 `authorize_operation` 会逐字段比对。在工具里抄一份重建逻辑就是复制 core 的规则，公开它更干净。
- **preparation transcript 摘要与被删实现不同形。** 被删的 `sidekick_runner` 把 `grantId`、`succeeded`、`operationResult` 与 `preparationId` 都摘进指纹，并按 preparation 分组；本模块的 receipt 字段集更窄，且按整个 lease 收集。核心只要求指纹是一个可解析的 Digest，`StateHandle.is_valid` 判有效性看的是 epoch 快照而不是指纹，因此这处差异只影响溯源信息的粒度。没有既有 run 目录需要兼容，形状由本阶段重新定义。
- **`LaneLock` 增加显式状态。** 原先只有 `locked: bool`，含义是「这条 lane 接不了新的 claim」——于是 lane 跑自己租约时也算锁住，同一租约的第二个 call 被自己的锁挡住。`locked` 分不出「等待裁决」与「正在干活」，而区分二者正是 op 需要的。`LaneLockState` 把 reason 里的散文变成代码可读的取值，`refuses_an_operation` 只在等待裁决、结果未定、lane 中断与整轮关闭时为真。
- **op 拒绝驱动 `operation:transition-trace.arm@1`。** 跑完 arm 就停会把设备留在已武装状态且没有配对的 disarm。被删的 sidekick_runner 用 `finally` 里的紧急 disarm 处理它；本阶段不重建那套清理，因此显式拒绝，而不是留一台武装着的设备。

像素模块走纯标准库解码 PNG（`zlib` 加手写 unfilter），不引 Pillow：它落在 `Scripts/regression/` 下，`subprocess` 是 `harness_primitives_gate.py` 的禁用原语，排除了仓库里既有的 ffmpeg 路线；而 Pillow 与 numpy 虽然装着，仓库没有 `requirements.txt` 或 `pyproject.toml` 锁定它们，在回归主路径上引一个无人管理的依赖不划算。`all_black` 复刻 `playback_mode_matrix.py:887` 的完整判据，而不只是它的一个常数。那条路径先把 RGB 交给 ffmpeg，ffmpeg 按 limited-range BT.601 转换，纯黑在那里是 16 而不是 0；因此 `VISUAL_BLACK_YAVG = 18.0`（`:815`）是「地板加 2」，换算到全范围约等于 2.3。把 18.0 直接套在全范围亮度上会宽 7.7 倍——审查用仓库自己的设备取证 `docs/archive/acceptance/evidence/playback-seek-and-menu-surface-20260821/menu-after-popover-minimum-window.png` 复现了这个误判：一帧正在播放、菜单完整展开的画面被判成全黑。本模块因此先把亮度换算进 limited range，再同时施加均值上限 18.0 与峰值上限 `VISUAL_BLACK_YMAX = 40.0`（`:816`）。峰值那一项不是可选装饰：一帧几乎全黑但带一条纯白带的画面，均值仍在门槛之下，只有峰值能把它挡住。

`capture_failed` 的判据是尺寸而非内容，这条规则此前只在 `InteractiveDeviceUITests.swift:589` 的 `capturedScreenPNG()` 里以 Swift 实现，Python 侧一行没有。

亮度采样按固定步长抽取，步长会一直递增到与图宽互质为止。若步长与图宽有公因子，抽样列集合会塌缩成固定的几列，整幅图的其余列永远读不到——1600 宽的画面在步长 2 下只会读到偶数列，一帧竖条纹图案因此可能被整片判错。

## 阶段验证方案

静态：

```sh
python3 Scripts/rules/run_verification.py --quick
python3 Scripts/rules/test_regression_op_tool.py
python3 Scripts/rules/test_regression_pixel_heuristics.py
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
  --repository-root . --execution-input .scratch/harness-tools/execution-input.json \
  --catalog-root Regression --policy <policy> --reviews-root Regression/reviews \
  --blueprint <blueprint> \
  --run-directory .scratch/harness-tools/run \
  --node <MainGate NodeID> --call <首个 CallID> \
  --lane simulator --target <模拟器 UDID> --sidekick sidekick:op
```

选该 lane 的 MainGate Scenario 的首个 call：它按定义在其他 Scenario 之前运行，前置状态最少。返回值必须带非 1×1 的截图与非空结构化字段。随后在同一 lane 上故意让一个 call 失败并复跑，第二次调用应当被 lane 锁拒绝，这是护栏在真实设备上的唯一证明。
