[← overview](overview.md)

# 验证约定

本文定义跨阶段共用的验证手段。各阶段自己的验证方案写在阶段分册的「阶段验证方案」一节。

## 静态门

每个阶段的静态验证都以这条命令开头：

```sh
python3 Scripts/rules/run_verification.py --quick
```

`--quick` 跑 `STRUCTURE_CHECKS` 中 `runs_in_quick_mode` 为真的检查加 PlaybackCore 全量测试加坏样本自测，跳过领域测试、源解析对拍、媒体发现能力矩阵与特性证据覆盖。合并前必须再跑一次不带 `--quick` 的全量：

```sh
python3 Scripts/rules/run_verification.py
```

`.github/workflows/verification.yml` 在 PR 上跑的就是不带参数的这一条。

## 自测的登记规则

`Scripts/rules/run_verification.py` 的 `discovered_test_checks()` 自动发现 `Scripts/rules/` 与 `Scripts/verification/` 下的全部 `test_*.py` 并逐个执行。本计划新增的每一份自测都按此命名，不需要登记进 `STRUCTURE_CHECKS`，也漏不掉。

新增 `verify_` 或 `check_` 前缀的检查器必须登记进 `STRUCTURE_CHECKS`，并受 `docs/CONTEXT.md` 的 Mutation Coverage Mandate 约束：一条坏样本、一份 `test_*.py` 自测，或一条写明理由的 `externalSubject` 声明，三者至少有一。本计划只在阶段 13 与阶段 18 新增检查器条目。

## 坏样本

`Config/guard_selftests.json` 以声明式文本变异描述坏样本：指定文件、要替换的原文、替换后的内容与期望的报错。`Scripts/rules/verify_guard_selftests.py` 在工作树副本上施加变异后跑那条规则，要求它拒绝且理由正确。本计划涉及坏样本的阶段：

- 阶段 1：`product-source-comments` 的 Python 分支。
- 阶段 13：`rubric-predicate-coverage` 的新条目。
- 阶段 18：`merge-evidence-tier` 增一条 `Apps/Enchron/Screens/` 被判为 W3 时必须失败。

## 模拟器 lane 的公共前置

阶段 6 起的每一条模拟器 lane 命令都假定以下三步已完成。

```sh
python3 Scripts/regression/runctl.py prepare-build \
  --artifact-root .scratch/harness-tools

python3 Scripts/regression/runctl.py freeze \
  --artifact-root .scratch/harness-tools \
  --simulator-target <模拟器 UDID> --device-target <真机 UDID> \
  --agent-model <模型> --output execution-input.json

python3 Scripts/regression/runctl.py compile \
  --reviews-root Regression/reviews \
  --execution-input .scratch/harness-tools/execution-input.json \
  --output .scratch/harness-tools/plan.json
```

模拟器 UDID 取自 `xcrun simctl list devices` 中的 Apple Vision Pro 条目。会话建立返回 `stage: ready` 才算成功，模拟器约 24 秒。同一目标在同一时刻只允许一个常驻 runner；开始新一轮之前先 `halt`，`remaining` 为空才算停净。

`xcrun simctl io` 的输出路径必须落在 `TMPDIR`，写仓库内路径会被拒为 `Operation not permitted`。

## 没有运行时证明的阶段

以下阶段不产出运行时证据，原因逐条写在各自的分册里：

- 阶段 1、3、5：只删代码或改源码文本，设备侧没有可证的行为变化。
- 阶段 7、8：纯决策逻辑，输入是 RunView，不触及设备。
- 阶段 19：只改自然语言。

阶段 2、4、14、18 的运行时验证不需要设备，跑的是 `runctl` 的编译路径或 `merge_evidence_tier.py` 的分类路径。

## 真机 lane 留到最后

以下三件事在模拟器 lane 无法证明，留到全部阶段完成后的一次真机 lane：

- 阶段 6 删掉的授权超时分支只在真机出现。模拟器 lane 只能证明正常路径没坏。
- 阶段 16 的人类层入口条件是同一节点连续两次 attempt 的 op 结果均为 harness 超时类，模拟器上难以稳定构造。
- 阶段 17 的人类收据路径需要一次真实的人类回归。

真机 lane 的一次完整验证按 `docs/MERGE_EVIDENCE.md` 的 W3 要求产出 Device Hub 产物目录，目录内含可解析的 `diagnostics.json` 与 App 侧 `spatialTap entity=<entity> ... accepted=true` 探针行。
