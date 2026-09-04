[← overview](overview.md)

# 阶段 6：删授权超时分支与两行分流

## 目标

删掉「等佩戴者完成自动化授权或密码确认」这条路径。该真机没有密码，这条分支的两次重试与最终的 `authorizationTimeout` 只会把一个未定性的会话建立失败误报为需要人介入。

## 改动清单

- `Scripts/verification/interactive_visionpro_ui.py`。删 `AUTOMATION_AUTHORIZATION_SIGNATURE`（:910）；删 `ensure_session` 中读 runner 日志尾部匹配该签名的分支（:1337）、日志未命中签名时的诊断文案（:1377）与两次尝试之后的 `stage: authorizationTimeout` 返回（:1418-1432）；删 `_attach_failure` 中 `stage == "authorizationTimeout"` 到 `kind = "authorization-required"` 的映射（:1556-1558）。会话建立失败在删除后统一落到 `readyTimeout`，由 `diagnostics.md` 中「尚未定性的会话建立失败」那一行分流。行号以当前 commit 为准，本分支的注释清理刚刚移动过这个文件。
- `Scripts/verification/harness/failures.py`。从 `INSTRUMENT_KINDS`（:11-24）删 `"authorization-required"`（:20）。
- `Scripts/verification/harness/CONTRACT.md`。:36 的仪器故障 kind 清单与 :52 的 kind→class 映射各删一处 `authorization-required`。
- `.agents/skills/vp-e2e/references/diagnostics.md`。删表格第 9 行（真机锁定）与第 10 行（`Timed out while enabling automation mode.` 授权超时）。第 11 行「尚未定性的会话建立失败」中「未命中时，对照授权时间节律排除授权解释」一句同步删掉，改为直接进入升级调查。

修改 `.agents/skills/vp-e2e/` 下的文件前，先调用 **writing-for-agents** 技能并研读其技能机制章节。

## 数据结构与形态

`ensure_session` 删除后的返回 stage 取值：

```text
adopted | ready | halt | readyTimeout
```

`_attach_failure` 删除后的 kind 取值：

```text
response-timeout | runner-gone | session-lost | app-not-running | app-crashed
```

## 阶段验证方案

静态：

```sh
python3 Scripts/rules/run_verification.py --quick
python3 Scripts/rules/check_interactive_halt_wake.py
python3 Scripts/rules/verify_controller_invocations.py
python3 Scripts/rules/verify_documentation_references.py
```

运行时（模拟器 lane）：

```sh
python3 Scripts/verification/interactive_visionpro_ui.py \
  --device <模拟器 UDID> --developer-dir "$(xcode-select -p)" \
  --execution-input .scratch/harness-tools/execution-input.json \
  --output-directory .scratch/<日期>-harness-tools/evidence \
  ensure-session

python3 Scripts/verification/interactive_visionpro_ui.py \
  --device <模拟器 UDID> halt
```

`ensure-session` 返回 `stage: ready`（模拟器约 24 秒），`halt` 返回空 `remaining`。这一对命令覆盖被改动的两个函数各自的正常路径。授权超时分支只在真机出现，模拟器 lane 无法复现它，因此本阶段的运行时证据只能证明删除没有破坏正常路径；真机上的证明留到阶段 19 之后的整轮真机 lane。
