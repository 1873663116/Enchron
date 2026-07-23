---
name: maintain-enchron-product-atlas
description: 维护 Enchron 面向人类的只读 Product Atlas，审阅一手文档变化、更新 Registry、确定性生成网页并验证来源与 placement 结构。
---

# Maintain Enchron Product Atlas

本 Skill 只维护从一手文档派生的 Product Atlas，不作新产品决策，也不把现有代码反推成产品事实。

## 工作流

1. 读取仓库 `AGENTS.md`、`docs/product-atlas.md` 与 `docs/atlas/model.json`。
2. 运行 `python3 Scripts/product_atlas.py status`。对每个已变化来源分别运行 `python3 Scripts/product_atlas.py diff <source-id>`；脚本只提供事实，不判断语义影响。
3. 如果变化涉及产品事实，先确认对应一手文档已经更新。未确认的问题在 Registry 中保持 `decisionStatus: unresolved`。
4. 只在 `docs/atlas/model.json` 手工维护 Product State Registry、Product Action Registry、所有者、来源和视觉投影。HTML、CSS 与 JavaScript 不复制产品动作定义。
5. 依据行为的逻辑主语选择视觉表达。复用 `docs/product-atlas.md` 已定义的视觉原语，不把所有行为强制塞进同一种卡片或流程模板。
6. 运行：

   ```bash
   python3 Scripts/product_atlas.py build
   python3 Scripts/product_atlas.py verify
   ```

7. 在浏览器中检查产品世界、至少一条正常路径、一条异常或系统分支、窄屏布局、键盘焦点和 reduced motion。视觉检查不能由机械验证代替。
8. 完成语义审阅后，逐个运行 `python3 Scripts/product_atlas.py accept <source-id>`。没有 `accept-all`；不要接受尚未审阅的来源。
9. 再次运行 `build`、`verify` 与 `status`，报告未决、未实现、未验证以及仍旧变化的来源。

## 约束

- Atlas 的一手资料范围与产品术语以 `docs/product-atlas.md`、`CONTEXT.md`、`docs/product-requirements.md`、`ARCHITECTURE.md` 和模型中登记的 sources 为准，本文件不复制产品规则。
- 不自动解析 Markdown，不引入框架、服务器、数据库、图编辑器或通用状态机。
- `model.json` 是唯一手工维护的 Atlas 语义模型；`index.html` 是确定性生成物。
- Git blob baseline 只表示 Atlas 已审阅过某份来源内容。引用定位来源，不证明产品运行行为。
- 机械检查证明 Registry placement、状态、来源引用和生成结果没有断链，不证明浏览器投影完整，也不证明产品规格本身没有遗漏。
