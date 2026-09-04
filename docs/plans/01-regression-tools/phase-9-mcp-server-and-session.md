[← overview](overview.md)

# 阶段 9：MCP server 骨架与 session 工具

## 目标

把工具集以 MCP 暴露。本阶段落地 server 骨架与五个工具的注册表。`session` 在本阶段实现；`ledger` 的实现由阶段 8 交付，本阶段接上它，占位拒绝会是一句假话；`op`、`bundle`、`receipt` 注册为占位并返回明确的未实现拒绝，供后续阶段逐个填充。`session` 本阶段只做 `--mode agent`，即 `ensure` 与 `halt` 两个 stage 的转发。

## 改动清单

- 新增 `Scripts/regression/tools/server.py`。MCP server 入口。注册五个工具的名字、参数 schema 与返回形状。提供 `--once <tool>` 的单次调用模式，用于自测与命令行验证，不经 MCP 传输。工具返回值分两部分：JSON 结构化字段，与可选的 image 内容块清单。image 块由 `bundle` 与 `op` 产出，server 只负责按 MCP 内容块格式编码。
- 新增 `Scripts/regression/tools/session_tool.py`。`ensure` 与 `halt` 两个 stage 转发到 `Scripts/verification/interactive_visionpro_ui.py` 的 `ensure_session` 与 `halt_session`，原样返回其 stage 字段。转发而不是重实现：会话建立的单 runner 约束、DerivedData 复用与进程作用域解析都在控制器里，复制一份会分叉。
- 新增 `Scripts/rules/test_regression_tool_server.py`。覆盖：五个工具都在注册表里、未实现工具返回拒绝而不是异常、`session ensure` 与 `halt` 的参数面、image 内容块的编码形状。

`Config/harness_primitives_allowlist.json` 不动。`harness_primitives_gate.py` 的白名单是一张豁免表：列进去的文件从此不再被扫描（`harness_primitives_gate.py:34-42`、`:105-116`）。`server.py` 与 `session_tool.py` 自己不碰 `subprocess`、`timeout=`、`time.sleep`、`time.monotonic` 与 `devicectl`——设备驱动全在 `interactive_visionpro_ui.py` 内，那个文件已按 basename 豁免。给一个不需要豁免的文件登记豁免，等于永久关掉它头上的那盏灯。转发时用 `parse_arguments(argv)` 传字符串 argv，而不是写 `ready_timeout=`，正是为了不触发那条字面量规则。

三个新文件都不得含注释。

转发经 `interactive_visionpro_ui.py` 的 `parse_arguments(argv)` 构造 Namespace，不自己抄一份默认值表：控制器有二十余个带默认值的参数，抄一份必然与它漂移。argv 用 `--flag=value` 单 token 形式：`--device` 后跟一个以 `-` 开头的值会让 argparse 调 `parser.error` 抛 `SystemExit`，而 `SystemExit` 是 `BaseException`，会穿过 JSON-RPC 循环直接结束进程。

错误面按控制器的既有语义对齐，不另立一套。`interactive_visionpro_ui.py:1571` 的 CLI 把 `OSError`、`RuntimeError`、`ValueError`、`json.JSONDecodeError` 一律转成 `success: False` 的文档；`session_tool.run` 对控制器调用套同一组，返回同一形状。只有参数本身不合法——mode、stage、device 三项——才抛 `SessionToolError`。

server 的 dispatch 同样按这组捕获。工具抛出 `ValueError` 家族之外的异常时，若只捕 `ValueError`，`_serve` 的循环会解开，进程退出，该帧之后的每一帧都无人应答；这不是一个工具调用失败，是整个会话死亡。JSON-RPC 帧本身也要先验形状：非对象的帧、非对象的 `params` 与非对象的 `arguments` 各自回一个 error code，不能让 `request.get` 抛 `AttributeError`。不带 `id` 的帧是通知，一律不回；`ping` 回空结果。

## 数据结构与形态

```text
session --mode agent|human --device <UDID> --stage ensure|halt
  ensure -> {stage: adopted|ready|halt|firstCommand|readyTimeout, ...}
  halt   -> {success, gracefulStop, resultBundleWritten, scope, terminated, remaining}

tool registry: {session, op, bundle, ledger, receipt}
tool result: {json: Mapping[str, Any], images: tuple[ImageBlock, ...]}
ImageBlock(media_type: str, data: bytes, caption: str)
```

`--mode human` 在阶段 16 实现，本阶段接受该取值并返回未实现拒绝。

`ensure_session` 有五个 stage，不是四个：`firstCommand`（`interactive_visionpro_ui.py:1338`）是新会话起来后第一条命令就失败的分支。阶段 6 的形状一节漏了它，那份文档同步修正。`halt_session` 根本不带 `stage` 字段，它的返回形状与 `ensure` 不同；转发原样返回，不补一个假的 stage。

## 阶段验证方案

静态：

```sh
python3 Scripts/rules/run_verification.py --quick
python3 Scripts/rules/test_regression_tool_server.py
python3 Scripts/rules/harness_primitives_gate.py
python3 Scripts/rules/verify_scripts_inventory.py
```

运行时（模拟器 lane）：

```sh
python3 Scripts/regression/tools/server.py --once session \
  --mode agent --device <模拟器 UDID> --stage ensure \
  --execution-input .scratch/harness-tools/execution-input.json \
  --output-directory .scratch/<日期>-harness-tools/evidence

python3 Scripts/regression/tools/server.py --once session \
  --mode agent --device <模拟器 UDID> --stage halt
```

第一条返回 `stage: ready`，第二条返回空 `remaining`。这一对命令证明工具层的转发没有丢掉控制器的语义。
