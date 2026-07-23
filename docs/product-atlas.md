# Enchron Product Atlas

Enchron Product Atlas 是面向人类理解与记忆的只读交互式产品图谱。它从 Enchron 一手文档派生，不产生、修改或覆盖产品事实。

## 信息层级

Atlas 以用户体验与产品状态为主视图。状态变化、不变量、领域所有权、编译边界和验证依据从可见产品行为逐层展开；普通 API、类型和文件不属于默认视觉内容，除非它们本身构成产品或架构合同。

完整覆盖指每项正式产品语义都能找到对应的状态、关系、所有者与依据，不指复制全部文档文字或展示全部代码元素。

Atlas 的产品世界由大致对应真实 Enchron 界面的解释性界面组成。它保留 Media Library、Window Playback、Docked、Panorama、Environment Card 与 Settings 等产品表面的空间关系和正式操作，但不追求像素还原，也不执行真实产品行为。

第一层空间布局按实际 visionOS Scene 容器组织：Main Window 承载 Media Library、Settings 与 Window Playback；Environment Card 使用独立 Volume；Enchron Immersive Space 承载 Enchron Environment、Docked Video Surface 与 Panorama；Player Controls Window 承载空间播放控制。Home View、System Surroundings 与 Apple System Environment 位于 Enchron 容器之外，作为 visionOS 管理的外部世界。

每个解释性操作都映射到 `Product Action Registry` 中的稳定动作身份。Registry 记录动作所在界面、可用条件、触发结果、失败结果、所有者、文档来源和 Atlas 呈现位置；同一正式动作可以在多个解释性界面中出现。机械验证检查每个动作具有有效 placement、placement 指向已登记的 surface/region，并检查来源与状态引用；浏览器验收负责确认这些 placement 是否真的形成清晰、完整的解释性投影。机械验证不声称证明运行时页面已经展示了每个动作。

`Product State Registry` 与 `Product Action Registry` 是 Atlas 的唯一语义模型。解释性界面只投影选定的产品状态和可用动作，不分别复制状态说明；动作演示只改变 Atlas 的讲解状态，不执行真实 App 行为。模型必须排除互相矛盾的状态组合。

点击解释性操作后，Atlas 先识别该行为真正改变或保持的逻辑主语，再选择能够直接解释它的图形。操作前、过渡、操作后与异常分支仍需完整覆盖，但不得被强制塞进一套统一卡片或面板；发生变化的关系本身应成为主要视觉内容，文字只承担名称、必要条件、原因、所有者、验证与来源。

正常路径默认展开。失败、系统中断和其他边界条件以始终可见的分支入口折叠展示，并由 `Product Action Registry` 登记和验证；视觉折叠不得成为语义遗漏或隐藏入口。

每段行为讲解都以稳定的责任层表达用户、Enchron 与 visionOS 的因果关系。继续深入时，Enchron 展开为 Media Library、Playback、Presentation 与 Environment 等领域所有者，再展开为 Target、Module、平台 API 与验证入口；不得在产品层直接堆叠代码名称，也不得只用颜色代替责任关系。

## 视觉语言

Atlas 使用 visionOS 风格的空间产品蓝图：通过克制的玻璃感、层次和稳定空间关系帮助记忆，但不复刻真实 App，不退化为传统工程流程图或卡片仪表盘。中文承担解释，正式英文术语保留为稳定名称；视觉美感服务于产品关系和状态变化，不用装饰掩盖信息。

Atlas 不把同一种排版当作所有事实的默认答案。Window 与 Docked 之间的转换以同一 Media Session 和 renderer consumer binding 的空间迁移表达；Panorama 以 Projection 与 Stereo Layout 的正交坐标和显示几何展开表达；Home View 恢复以 App Process、Immersive Space 与仅内存恢复意图的不同生命周期表达。其他内容依据其因果结构选择轴、序列、关系图、生命周期线、状态差分或分支；只有缺少更具解释力的结构时才使用普通列表。

正式实现可以复用连续身份路径、转换路径、生命周期线、状态轴、空间表面、分支与来源标记等视觉原语，但不得为了复用组件而把不同逻辑压成同一种页面模板。不看说明文字时，读者至少应该能够指出什么保持不变、什么发生变化、谁造成变化，以及失败或系统中断通向哪里。

## 事实与交付状态

Atlas 默认展示已经确认的目标产品模型，并分别表达：

- 产品事实是否已经确认；
- 产品事实是否已经实现；
- 已实现行为是否已经验证。

设计、实现和验证不得合并为一个完成状态。尚未决策的内容必须显式呈现为缺口，不得由现有代码反向推定为产品事实。

## 权威与维护

Atlas 手工维护，不自动解析 Markdown，也不作为产品决策编辑入口。每个重要节点和关系必须引用对应的一手文档；修改产品事实时先修改一手文档，再更新 Atlas。

Git 历史保存每个仓库版本对应的 Atlas。Atlas 的已审阅来源清单记录相关一手文件的 Git blob hash；维护工具比较该基线与当前内容，提示发生变化的来源、diff 和可能受影响的节点，但不自动修改 Atlas 语义。

机械脚本负责取得 Git 状态、blob hash、diff，验证 Registry 的 placement、状态和来源结构，并确定性生成网页；仓库专属 Skill 负责判断语义影响、更新视觉关系，并通过浏览器检查实际解释性投影。
