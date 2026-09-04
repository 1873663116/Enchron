[← overview](overview.md)

# 阶段 19：文档同步

## 目标

把前 18 个阶段改掉的语义写回权威文档。本阶段只改自然语言，不改代码，因此涉及的文件数超过通常的两到三个。

修改 `.agents/skills/vp-e2e/` 下的文件前，先调用 **writing-for-agents** 技能并研读其技能机制章节；全部文本适用 **technical-writing** 与 **unslop**。

## 改动清单

- `.agents/skills/vp-e2e/SKILL.md`。删「不许中途收工」一节（:70-72），它描述的 Main 调度与 Sidekick 执行已在阶段 3 删除。改「Launch」一节的 `ensure-session` 示例：`--derived-data-path` 参数在 `Scripts/verification/interactive_visionpro_ui.py` 中已不存在，实际必需的是 `--execution-input` 或 `ENCHRON_EXECUTION_INPUT`。「Helpers」一节（:116）增工具集入口 `Scripts/regression/tools/server.py`。
- `Regression/README.md`。系统关系图（:9-26）删 Main、lease、Sidekick 三个节点及其边，改为 Operation 工具直连账本。对象职责清单（:36-37）删 `Main` 与 `Sidekick` 两条，改为工具集与账本的职责描述。「运行与证据不变量」（:181-189）中依赖 lease 的三条改写。「核心公开接口」（:192-200）删 `open_run` 的 MainRun 描述中与 lease 相关的部分。「实施关口」（:206）的顺序描述更新。
- `Regression/oracle-protocol.md`。「Run Agent Oracles」一节改为判读三级：L0 字段谓词由阶段 13 的编译器生成，L1 像素启发，L2 Agent 只在异常包之后做归因。:15 那句「the current Catalog has no such runtime Oracle」按阶段 13 的实际覆盖率改写：存在字段谓词实现的 criterion 走确定性路径，编不出的仍然是自然语言判读，并指向覆盖报告。
- `Regression/execution-protocol.md`。「Resolve the current driver」一节增 `Scripts/regression/tools/server.py`。「Authorize each call」一节的授权主体从 Main 改为 op 工具经 gateway 授权，授权内容不变。
- `docs/CONTEXT.md`。「验证」一节增四条术语：账本锁、异常包、判读三级、人类层。每条按该文既有体例写：一句定义，加一句它不是什么。

## 数据结构与形态

无新类型。本阶段只改自然语言。

## 与原清单的偏离

四处：

- **`Regression/README.md` 的改动比清单大。** 清单点名了系统关系图、对象职责、运行与证据不变量、核心公开接口与实施关口五处，实际还有六处散落的 `Main` 与 `Sidekick` 句子（:93、:133、:137、:153、:157、:159、:161、:163、:171、:175）。留下任何一处，读者会以为调度层还在。现在这两个词在该文件里出现零次。
- **`.agents/skills/vp-e2e/SKILL.md` 的「不许中途收工」改写而不是删除。** 清单说删掉这一节，但它承载的一条约束仍然成立：每个节点都要有机器终态，未结节点不能出收据。删掉整节会连这条一起丢掉。改写后的一节说的是同一件事，只是执行者从 Main 换成了 `receipt` 工具，终态清单也补上了 `failed(known)` 与 `deferred(human)`。
- **`Regression/` 下的三份文档是生成物，源在 `Config/regression/catalog-root/`。** 直接改 `Regression/README.md`、`execution-protocol.md`、`oracle-protocol.md` 会让 `test_regression_catalog_materialized` 红：`materialize_catalog_v2.py` 把它们按 `copyDocuments` 里记录的 digest 逐份比对。改动落在源目录，再刷新 `Config/regression/catalog-v2.json` 里那三条 digest 与整份 blueprint 的 `contentDigest`。这道门是对的——生成物只有一个真相源。
- **`ensure-session` 示例同时补上返回 stage 的取值。** 清单只要求把 `--derived-data-path` 换成 `--execution-input`。示例下方那句「只有返回 `stage: ready` 才算建立成功」在读者不知道另外四种 stage 时是悬空的，因此把五种取值一并写出。

## 顺带修掉的一处产品缺陷

`missingFirstDisplayedFrameFailsWithoutGuessingTheCause` 在整轮运行里间歇性变红，读到的 `snapshot.lastFailure` 是 `nil`。不是测试写松了：`recordFailure`（`SampleBufferPlaybackSession+Diagnostics.swift:723`）先 `updateLifecycle(.failed)`，再写 `debugStore.recordFailure`。任何等待 `.failed` 再去读 `lastFailure` 的观察者都可能落在这两步之间读到空值，App 自己的诊断面也一样。机器有负载时窗口变宽，这就是它在门禁与 CI 同时跑时才红的原因。失败记录改为先写、生命周期后发布，连跑三轮干净。

## 阶段验证方案

静态：

```sh
python3 Scripts/rules/run_verification.py --quick
python3 Scripts/rules/verify_documentation_references.py
python3 Scripts/rules/verify_scripts_inventory.py
```

`verify_documentation_references.py` 校验文档中引用的路径真实存在，是删掉三个模块之后文档没留悬空引用的判据。`verify_scripts_inventory.py` 要求每个脚本名在仓库别处被引用，是新增工具入口已被文档收编的判据。

改动后逐条核对 `technical-writing` 审查清单第 8 项：文档中引用的所有路径、符号名称与代码片段在当前 commit 上真实存在。

运行时：无。本阶段不改代码。
