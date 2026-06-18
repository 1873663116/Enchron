# ADR-0006：用例表冲突治理 · 双上下文术语分层 · 前缀 SCEN→ENV

- 状态：已接受
- 日期：2026-06-18
- 决策者：项目负责人（经一轮 grill-with-docs 采访 + 逐 UC 冲突审计）

## 背景

`docs/use_cases.md` 整体由 agent 从旧生产管线带出后写成，负责人只「大致审了一遍」。本轮做命名规范化时发现三层问题叠加：

1. 命名分散在代码 / `docs/contracts/` / `CLAUDE.md` 复用清单 / `use_cases.md` 四层、互相漂移，且**无判据**裁决「某个词进哪个术语表」；复用清单还点名了 7 个已不存在的组件（`VideoCardLarge`/`FolderCard`/`SceneCardMedium`…），正诱发「找不到→仿写相似版本」的反模式。
2. ADR-0005 的 Scene→Environment 改名未收尾；其第 3 点「前缀沿用 `SCEN`」与负责人手改后的 `UC-ENV-NN` 冲突，且该次手改很可能是一次 `scen→ENV` 替换的连带误伤（同次还把 mpv 真实键 `hdr-scene-threshold-*` 污染成 `hdr-ENVe-threshold-*`、把 SwiftUI `Scene` 误写成 `ENVe`）。
3. 一轮逐 UC 审计发现 `use_cases.md` 与 DesignComps 实际渲染大量漂移：枚举值过期、状态标错（未验证 vs 未实现）、大片 `Settings→Advanced` 面被「内部机制不进表」盖住、以及若干「表里有 / 设计稿无」与「设计稿有 / 表里无」的缺口。

核心担忧：表带着未被充分核对的 agent 假设。

## 决策

1. **双上下文术语分层**：根 `CONTEXT.md` = 全局领域语言，`DesignPreview/CONTEXT.md` = 组件语言；新建根 `CONTEXT-MAP.md` 承载发现入口 + 三问判据（跨模块领域事实 → 根；视觉角色 / 屏幕 / tab / 面板分类 → design；纯渲染文案 → 哪个都不进、贴 `accessibilityIdentifier`）。铁律：同名不双定义，领域占词、组件用复合名并交叉引用领域词。
2. **前缀 SCEN→ENV**：用例表 Environment 章前缀由 `SCEN` 改 `ENV`，**推翻 ADR-0005 第 3 点「沿用 SCEN」**。理由：IDs 本轮才建、外部引用极少，churn 成本现在最低；前缀与领域词 Environment 一致，消除「前缀 ≠ 概念」的长期 papercut。ID 仍永不复用、不承载语义。
3. **用例表冲突治理（无默认权威）**：`use_cases.md` 是 agent 写、负责人粗审，**不是可信权威**；DesignComps 同样是负责人意志。两者冲突时**无默认赢家**——即使宪法写「与代码冲突默认表为准」，在 ledger↔comp 冲突上亦让位。流程：① 全部 surface 出来；② 明确的 agent 笔误 / 自相矛盾 / 两边都占位的，决策时写明理由 + 留否决；③ 真·意图分歧路由负责人裁决。覆盖度审查中，「冲突」即负责人意志待表达处。
4. **Scene→Environment 收尾**：DesignPreview 领域义标识符（`DesignPreviewTab.environment`、`isEnvironmentTransitionInFlight`、`PlayerPanelSettingsCategory.environmentSetting`、`FeaturedEnvironment.environmentNumber`、Settings `Default/Reset Environment` 等）改齐；**不动** SwiftUI `some Scene`/`windowScene`/`.scene(.bottom)`、`SceneFeature*` 资源名、跨仓 `AnimationToken.scene*`。修复 `use_cases.md` 那次 `scen→ENV` 误替换的污染（`hdr-scene-threshold-*`、SwiftUI `Scene`、改名说明句——已对 mpv 源 `~/Applications/mpv/xr-fork/verify-visionos` 核实回填）。

## 后果

- 组件真名以**代码为唯一真相**，契约（`docs/contracts/`）、`CLAUDE.md`/`AGENTS.md` 复用清单、`DesignPreview/CONTEXT.md` 全部对齐过去。
- 本轮裁决的产品方向分歧（记录以备追溯，细则落 `use_cases.md` 各行）：
  - 播放面板 Advanced 画面区 = **libplacebo 官方参数全集**（保留附录方向；消费级调色 comp 待按附录重建——较大工程）
  - 倍速 **0.25×–5.0×**；进沉浸 **二态 Off/On**；Auto-Hide 单 picker 含 Never；本地导入入口 = 主区 **Manage 按钮**；源圆点 = **活跃源指示**；Play Mode = 三开关；Feedback = 展示邮箱可复制；清缓存 = 瞬时反馈
  - `FILE-10` 拆 `超时` + `认证失败`；`Settings→Advanced` 按「用户可观察」划线（带确认 / 持久副作用的动作升正式 UC，纯只读诊断记一条）
  - 蓝图态（空 / 加载 / 错误 / resume / failed-to-load）本轮补 comp；续播 / 加载簇注「视觉壳已就位」更正为未建
- 多个 comp 因负责人选了表 / 规格侧而需回头重建（见 `use_cases.md` 标注）。

## 关联

- ADR-0003（用例表立档）、ADR-0005（功能簇 + Scene→Environment；其第 3 点前缀决策被本 ADR 第 2 点推翻）。
- `CONTEXT-MAP.md`（新）、根 `CONTEXT.md`、`DesignPreview/CONTEXT.md`。
- mpv 真实键核实源：`~/Applications/mpv/xr-fork/verify-visionos/Sources/App/TuningPanel.swift`。
