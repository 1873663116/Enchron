---
name: maintain-enchron-product-knowledge
description: 校准 Enchron 的产品决策与规范文档、当前实现、运行验证证据以及面向人类的 Product Atlas；适用于审阅跨层变化、修正文档漂移、更新 Atlas Registry 和判断规范、实现、证据与 Atlas 的状态分歧。
---

# Maintain Enchron Product Knowledge

产品知识的权威关系、状态含义、分歧落点与证据条件以 `docs/product-atlas.md` 为准。本 Skill 只规定如何发现变化、作出有范围的判断、更新相应载体并完成 Atlas 验收。

## 校准工作流

### 1. 建立审阅范围

读取仓库 `AGENTS.md` 规定的当前文档，并读取 `docs/product-atlas.md` 与 `docs/atlas/model.json`。通过任务目标、当前变更和来源引用确定本次涉及的产品行为、所有者和验证层，不扫描全仓后猜测产品语义。

先对已确定的任务路径运行：

```bash
git status --short -- <task-paths...>
git diff -- <task-paths...>
```

只有需要校准 Atlas 时才运行 `python3 Scripts/product_atlas.py status`，并对每个已变化的登记来源分别运行：

```bash
python3 Scripts/product_atlas.py diff <source-id>
```

Git 与 Atlas 工具只提供变化事实，不判断变化的产品含义，也不建立全仓代码基线。脏工作树中的其他变化不自动进入本次判断范围。

### 2. 按声明性质确定权威与动作

逐项判断变化属于哪一种情况：

| 情况 | 处理 |
|---|---|
| 新的或修改后的产品决策已经确认 | 先使规范文档准确表达目标行为，再更新 Atlas 的产品状态、动作和 `decisionStatus`；代码可以暂时保持未实现或部分实现。 |
| 代码实现已有规范 | 对照任务范围内的生产代码和测试更新 `delivery.implementation`；只有规范中描述“当前实现”的内容已经失真时才修改相应文档，不重写仍然有效的目标规范。 |
| 代码出现规范没有确认的产品行为 | 不创建 Atlas 正式动作。先在本次交付报告中列出分歧；需要跨任务保留时，先写入拥有该产品事实的权威文档之显式未决部分，Atlas 才能把它投影为未决缺口。 |
| 代码与规范冲突 | 同时报告规范要求与任务范围内观察到的实现，不让一方静默覆盖另一方；跨任务保留方式与上一项相同。 |
| 纯重构或内部实现变化 | 验证边界与行为未变时，不修改产品规范和 Atlas 产品语义；只处理确实失真的架构或实现状态说明。 |
| 测试或验证发生变化 | 测试源码只说明检查意图和可机械执行的合同；只有当前产品树上的实际运行结果及所需 artifact 才更新 `verification` 和证据文档。 |

Skill 可以修改规范、架构或验收文档，但每项修改必须有明确目的。不得因为代码 diff 存在就顺便改文档，也不得用代码覆盖尚未改变的规范。

### 3. 校准 Product Atlas

只在 `docs/atlas/model.json` 手工维护 Product State Registry、Product Action Registry、所有者、来源、`decisionStatus`、`implementation`、`verification` 和视觉投影。HTML、CSS 与 JavaScript 不复制产品动作定义。

已经确认的动作即使实现落后，也只通过 `delivery.implementation` 表达，不为“尚未实现”伪造产品异常分支。V1 的 Atlas 工具不能机械证明 implementation assessment；本次交付报告必须列出该判断实际检查的生产代码与测试路径、已知缺口和未检查范围。

非 `notEvidenced` 的 `delivery.verification` 必须同步维护 `evidenceRefs`。每项引用只包含 `sourceId`、`heading` 与 `scope`；`scope` 写清当前证据实际证明的行为和层级。证据文件必须先登记为 source，完成逐来源审阅并在最终验证前 `accept`。规范文档、架构说明和验证规则只能定义要求，不能作为运行证据。

依据行为的逻辑主语选择视觉表达。复用 `docs/product-atlas.md` 定义的视觉原语，不把所有行为强制塞进同一种卡片或流程模板。

### 4. 构建与验收

需要预览时先运行：

```bash
python3 Scripts/product_atlas.py build
```

这一步只生成预览，不声称 Atlas 已通过验证。在浏览器中检查产品世界、至少一条正常路径、一条异常或系统分支、窄屏布局、键盘焦点和 reduced motion。视觉检查不能由机械验证代替。

完成语义审阅和必要的视觉审阅后，对每份已变化或新登记的来源逐个运行：

```bash
python3 Scripts/product_atlas.py accept <source-id>
```

没有 `accept-all`。`accept` 只表示该来源变化已经完成语义审阅及必要校准，不表示相关产品行为已经实现或通过验证；不得接受仍未审阅的来源。

接受完成后再执行最终检查：

```bash
python3 Scripts/product_atlas.py build
python3 Scripts/product_atlas.py verify
python3 Scripts/product_atlas.py status
```

最终报告：

- 已确认但尚未实现或仅部分实现的产品事实；
- 已实现但尚无当前验证证据的行为；
- 实现与规范之间仍未解决的分歧；
- implementation assessment 实际检查的生产代码、测试路径与未检查范围；
- 仍旧变化或尚未接受的来源。

## 约束

- 不作未经用户或权威记录确认的新产品决策。
- 不自动解析 Markdown，不引入框架、服务器、数据库、图编辑器或通用状态机。
- 不为代码和测试建立第二套 Atlas baseline；代码变化通过任务范围和 Git diff 审阅。
- 不因 Atlas v1 缺少 implementation path 字段而把代码路径塞进 `sourceRefs` 或 `evidenceRefs`；本轮实现判断的路径依据留在交付报告。
