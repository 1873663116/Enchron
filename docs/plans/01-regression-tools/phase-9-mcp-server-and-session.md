[← overview](overview.md)

# 阶段 9：MCP server 骨架与 session 工具

## 目标

把工具集以 MCP 暴露。本阶段落地 server 骨架与五个工具的注册表，其中只有 `session` 有实现；`op`、`bundle`、`ledger`、`receipt` 注册为占位并返回明确的未实现拒绝，供后续阶段逐个填充。`session` 本阶段只做 `--mode agent`，即 `ensure` 与 `halt` 两个 stage 的转发。

## 改动清单

- 新增 `Scripts/regression/tools/server.py`。MCP server 入口。注册五个工具的名字、参数 schema 与返回形状。提供 `--once <tool>` 的单次调用模式，用于自测与命令行验证，不经 MCP 传输。工具返回值分两部分：JSON 结构化字段，与可选的 image 内容块清单。image 块由 `bundle` 与 `op` 产出，server 只负责按 MCP 内容块格式编码。
- 新增 `Scripts/regression/tools/session_tool.py`。`ensure` 与 `halt` 两个 stage 转发到 `Scripts/verification/interactive_visionpro_ui.py` 的 `ensure_session` 与 `halt_session`，原样返回其 stage 字段。转发而不是重实现：会话建立的单 runner 约束、DerivedData 复用与进程作用域解析都在控制器里，复制一份会分叉。
- 新增 `Scripts/rules/test_regression_tool_server.py`。覆盖：五个工具都在注册表里、未实现工具返回拒绝而不是异常、`session ensure` 与 `halt` 的参数面、image 内容块的编码形状。

`Config/harness_primitives_allowlist.json` 增 `Scripts/regression/tools/server.py`：它是新的设备驱动入口，受 `Scripts/rules/harness_primitives_gate.py` 管辖。

三个新文件都不得含注释。

## 数据结构与形态

```text
session --mode agent|human --device <UDID> --stage ensure|halt
  -> {stage: adopted|ready|halt|readyTimeout, sessionID, elapsedSeconds}

tool registry: {session, op, bundle, ledger, receipt}
tool result: {json: Mapping[str, Any], images: tuple[ImageBlock, ...]}
ImageBlock(media_type: str, data: bytes, caption: str)
```

`--mode human` 在阶段 16 实现，本阶段接受该取值并返回未实现拒绝。

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
