# DesignPreview 组件标准化 — 执行计划 / 压缩后复活锚点

> **压缩后从这里接续。** 读这 4 处即可无损恢复上下文,无需重推讨论:
> 1. 本文件(计划 + 已锁决策)
> 2. `CONTEXT.md`(术语:标准件 / 变体 / 组件库 / 竞争重复 / 兄弟变体)
> 3. `docs/adr/0001-variant-recipes-in-static-factories.md`(变体配方 = 静态工厂,不放 token)
> 4. `docs/contracts/*.md`(19 份组件契约 = 实现规格)

## 当前进度
- **Step 1(清理重复组件/死件)已完成**——由并行 agent 在 `b0c1d2b` 完成并合并进 main。
- **契约定义阶段已完成**——19 份白话契约落在 `docs/contracts/`,全部决策已拍。
- **Phase 2 / A 批(结构性合并·删除·重命名)已完成**(Agent 自查,每步编译绿):
  - A.1 `VideoCardLarge`+`FolderCard` → `GridCard`(+ `.video`/`.folder` 工厂、锁宽高、删 `showsSupplementaryInfo`、元数据色统一 `.secondary`、补 a11y);运行态 Files 网格自查通过。
  - `FeaturedSceneCard` → `SceneCard`(纯重命名,参数面已就位)。
  - `MockToggle`/`BoundMockToggle` → `GlassToggle`/`BoundGlassToggle`(去 fake-UX 命名)。
  - `GlassCircleIconButton`:锁 `iconColor` + 加具名图标预设 `.back/.expand/.more/.close`(Label 仍保留 iconColor 供 SortMenuButton 复用)。
  - A.5 Sidebar 拆两角色:`SourceSidebar` 去泛型 `<Footer>`/删 `SourceSidebarCapabilities`/`showsStatusIndicators`、存储条内置 mock;新增 `CategorySidebar`(+`CategorySidebarItem`)入 `SharedComponents.swift`,从内联 `settingsSidebar` 抽取。调用点全改、孤儿清理。运行态 Files 的 SourceSidebar+存储条自查通过;**CategorySidebar 的 Settings 运行态截图被 `snapshot_ui` 工具崩溃挡住,待 Canvas 确认**。
  - **跳过(工程判断)**:`ViewMode` Int→enum(非阻塞建议,低价值高 churn);`FeaturedScene.mode/atmosphere`→enum(atmosphere 是自由文案,枚举化=过度设计)。
- **下一步 = B(逐件参数化)→ C(重组 DesignComps)→ D(SwiftLint 守卫 + 薄测试)。** 用户验收方式:不读代码,Agent 自查 + Canvas。

## 核心模型(一句话)
严格派:一个视觉角色 = 一个带参标准件,差异走**参数**或**具名变体工厂/预设**(`GridCard.video`)。`DesignTokens` 是纯值层(被组件消费),组件不是 token 的预设而是其使用者。组装时只调标准件改参数,**不许写自定义组件代码**。

契约模子(每份固定 7 段):0 角色 / 1 构造 / 2 变体 / 3 暴露参数 / 4 无障碍 / 5 锁死 / 6 决策。

## 已锁决策(不要重新讨论)
- **GridCard**:合并 `VideoCardLarge` + `FolderCard` → `GridCard` + `.video`/`.folder` 工厂;不暴露宽高;缩略图内容模型(icon 现 / image 将来)由变体内部钉死。
- **Sidebar 拆两个角色**:`SourceSidebar`(交互源列表,Files)写死全功能 + 内置存储条;**删** `SourceSidebarCapabilities` OptionSet 与泛型 `<Footer>`。`CategorySidebar`(新,静态分类器,Settings/Panel)**从内联 `settingsSidebar` 抽取**,暴露 items/selection/title/width/height/a11y。
- **List-group 不合并**:`SettingListGroup` 与 `FileListGroup` 共享内部件 `ListGroupRowShell`,各自独立。
- **SettingListGroup**:一套组件 + 尾部插槽(8 种 accessory 全用,不拆 N 个组件)。
- **按钮**:Label/Button 分层保留;锁 iconColor;加具名图标预设工厂(`.close`/`.expand`/`.back`);按钮家族变体全留。
- **Nav 控件**:加 `canGoBack`/`canGoForward`(禁用半区灰显且不可点)。
- **Scene**:`FeaturedSceneCard` → 重命名 `SceneCard`;动画态由 `SceneCardCarousel` 驱动,非暴露面。
- **PlayerControlDeck**:近零参数(仅 `timelineResetToken`),定死复合件。
- **PlayerSettingsPanel**:不是组件,是 `CategorySidebar` + `SettingListGroup` + 玻璃的**组装参考**,直接抄。
- **三个收尾**:`LoadingSpinner` 保留(未来加载态);`SearchInputCapsule` width 锁;`GlassCapsuleIconLabelButton` 保留。

## 验收策略(用户不读代码)
- **视觉 → Canvas / 组件库**:每个标准件 + 变体实例并排陈列,肉眼验收。主闸门。
- **「组装无自定义」→ SwiftLint 守卫**:禁止 `DesignComps/Pages/` 出现 `glassBackgroundEffect` / `clipShape` / 裸 `.padding(数字)` 等组件级原语。违反即红。
- **API 锁死 → 薄测试(TDD 精神)**:断言每件只暴露契约规定的参数 + 页面只调标准件;用户读**测试名**(英文人话)+ 信绿勾。
- **diagnose**:仅当真出 bug 时用。

## 实现阶段工作清单(Phase 2,按序)
**A. 结构性合并/删除/重命名**(依据各契约第 6 段)
- 合并 `VideoCardLarge`+`FolderCard` → `GridCard`(+ 工厂)
- `SourceSidebar`:删 OptionSet、删泛型 footer、存储条内置(mock)
- 抽取 `CategorySidebar`(从内联 `settingsSidebar`)
- 重命名 `FeaturedSceneCard` → `SceneCard`
- 按钮加具名图标预设工厂
- 小项:`ViewMode.selection` → enum;`FeaturedScene.mode/atmosphere` → enum;`MockToggle` 改名(如 `GlassToggle`)

**B. 逐件参数化**:每个标准件暴露面收敛到契约规定,其余锁死(私有默认 / token);变体做成静态工厂,组件库陈列各变体实例。

**C. 重组 DesignComps 页面**:把内联 UI 换成标准件调用,页面只剩布局+交互;`PlayerSettingsPanel` 抄组装参考。

**D. 加守卫与测试**:SwiftLint 规则 + 薄测试。

## 延后(独立轮次,不混进 Phase 2)
- **Token 清理**:Phase 2 之后再做(用户自记)。成员级死 token 扫描,跨模块(与主 app 共享 `DesignTokens`),单独评估。`LoadingSpinner` token 已确认保留。
- **内部简化评审**:`SourceSidebar` 1200 行能否瘦;Nav/ViewMode 双区胶囊脚手架抽共享内部件。判据 = 当前视觉效果为黄金基准(Canvas/截图),不改暴露面。

## 实现阶段验收闸门
build 绿 + Canvas 各变体视觉正确 + SwiftLint 守卫通过 + 薄测试绿;每件在组件库逐个肉眼确认。用户全程不读实现代码。
