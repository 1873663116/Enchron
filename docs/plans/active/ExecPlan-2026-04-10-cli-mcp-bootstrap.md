# ExecPlan: CLI + MCP Bootstrap

日期：2026-04-10

## 目标

为 Enchron 建立一套可复用的工程入口：

- 用 Bun 脚本固化高频稳定的 CLI 动作
- 保留原生 Xcode CLI 作为底层真实能力
- 接入并验证项目级 XcodeBuildMCP，用于 simulator / UI 自动化能力
- 更新文档，让后续 agent 明确何时优先脚本、何时优先 CLI、何时优先 MCP

## 范围

- 新增 `package.json` 与 Bun scripts
- 新增必要的辅助脚本
- 更新 `AGENTS.md` / `README.md` / `TESTING.md`
- 验证 CLI 脚本可运行
- 验证 XcodeBuildMCP 可连接并执行至少一项实际动作

## 非目标

- 不重构现有 Swift 模块
- 不替代真机验证流程
- 不把所有零散调试命令都封成脚本

## 实施步骤

1. 盘点现有构建、测试、脚本和 Xcode scheme 信息
2. 设计最小 Bun scripts 集合与底层 shell 脚本
3. 接入并验证 XcodeBuildMCP
4. 更新项目文档与 agent 约定
5. 执行自检并产出验证结论
