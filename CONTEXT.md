# Enchron 术语

Enchron 是一个产品上下文；PlaybackCore 是其中可独立测试的播放模块，不形成第二个产品或文档上下文。

## 产品知识

**Enchron Product Atlas**：从 Enchron 一手文档派生、面向人类理解与记忆的只读交互式产品图谱；它连接产品语义、状态、所有权、代码边界与验证依据，可以删除并重新构建，但不产生或修改产品事实。
_Avoid_：第二份产品规格、文档真相源、产品决策编辑入口、把文档文字换成网页卡片

## 产品与播放

**Enchron**：面向用户的 visionOS 媒体产品及其唯一代码仓库。

**Enchron App**：Enchron 产品本身，拥有来源、产品策略、界面与 visionOS 平台呈现，也是唯一的产品运行与集成验证入口。
_Avoid_：Verify App、Anchor App

**PlaybackCore**：Enchron 内负责媒体会话、sample、时间线、控制语义与 renderer graph 的独立模块。
_Avoid_：外部播放仓库、播放 App

**PlaybackRuntime**：Enchron App 将产品请求交给 PlaybackCore、并把核心事实投影给界面的应用边界。
_Avoid_：第二播放核心、播放状态机

**Playback Lifecycle**：PlaybackCore 发布的媒体会话状态，包括 idle、loading、ready、playing、paused、ended 与 failed。
_Avoid_：播放模式

**Playback Presentation**：视频当前稳定的产品呈现位置，只包括 Window、Docked 和 Panorama。
_Avoid_：Playback Lifecycle、播放模式

**Media Format**：Enchron 对媒体画面的解释方式，由 Projection 与 Stereo Layout 两个正交维度组成。它独立于媒体当前位于 Window、Docked 或 Panorama；从 Panorama 返回 Window 不会把 Media Format 重置为 Flat + Mono。
_Avoid_：Playback Presentation、Docking 状态、HDR 开关

**Media Format Preference**：用户为同一 Media Identity 明确选择并持久化的 Projection 与 Stereo Layout。它与 Persistent Viewing State 共用唯一的 Media Identity 与 Content Revision 判定；可以分别存储数据，但不得分别实现文件身份或内容变化算法。Docked 或其他 Playback Presentation 不属于该记录。
_Avoid_：把 Docked/Panorama 位置写入 Resume、内容变化后套用旧格式、复制第二套媒体版本判断、自动识别或推断 Projection/Stereo Layout

**Effective Media Format**：当前会话实际使用的 Media Format。通过 Content Revision 验证的 Media Format Preference 存在时采用用户选择；否则使用 Flat + Mono。Enchron 当前不自动识别、推断或应用 Projection 与 Stereo Layout。AIME 元数据只验证用户选择 Fisheye 的资格，不替用户作出选择。

**HDR Classification**：媒体与渲染链路的只读能力事实，例如 SDR、HDR10、HDR10+ 或 Dolby Vision。Enchron V1 不提供关闭 HDR 或把 HDR 手动切换为 SDR 的播放控件；除非未来正式拥有 tone mapping 产品能力，否则 HDR 只用于信息显示和渲染验证。
_Avoid_：HDR 开关、把标签选择当成 SDR 重映射、没有 tone mapping 却声称关闭 HDR

**System Volume Ownership**：Enchron 不提供 App 内 Volume 或 Mute 产品控件，也不保存 App 相对音量。播放保持正常基准增益，最终输出音量与静音由 visionOS、Digital Crown 和系统音频界面控制。PlaybackCore 若因 renderer 实现或测试保留底层增益能力，也不得因此形成 Enchron 产品 API。
_Avoid_：App 音量滑杆、App 静音状态、把 Core 测试能力当成产品要求

**Portal / Window**：用户所说的 Portal 返回状态在 Enchron 领域模型中仍是 Window Playback Presentation，不增加第四种 Presentation。界面文案和图标可以表达“返回窗口”。

**Window Playback Ornament**：附着在当前 Window Playback 系统窗口底边的 PlayerControls。它与所属窗口保持平行并略微位于其前方，随窗口一起移动，但不属于 Window 内容平面，也不是独立 Window。它的稳定外部宽度是 Window Playback 宽度范围的尺寸基准；Docked 与 Panorama 的 Player Control Dock 不使用这个术语。
_Avoid_：Window 内 overlay、RealityView attachment、独立 PlayerControls Window、与视频共面
_Avoid_：把 Portal 建模为独立于 Window 的播放状态

**Media Session**：一次 accepted open 到 close 或 failed 的唯一核心身份范围。

**Current Media Slot**：PlaybackCore 同时允许占用的唯一 Media Session 位置。

**Renderer Graph**：同一 Media Session 的 video renderer、audio renderer 与共享 synchronizer。

**Renderer Consumer Binding**：Enchron App 将当前 video renderer 交给唯一 RealityKit consumer 的可追溯绑定。

**Video Player Consumer**：Window、Docked 和 Panorama 统一使用的 RealityKit `VideoPlayerComponent` consumer；三个 Presentation 只改变 scene、transform 与 immersive mode。
_Avoid_：planar consumer、Window/Docked `VideoMaterial` 路径

## 来源与产品策略

**Media Library**：Enchron 管理的虚拟分类目录，只保存用户分类与 Media Reference；它不保存媒体字节，也不是一套文件管理系统。原始媒体始终由 visionOS 文件系统、Photos 或远程来源拥有。
_Avoid_：App 文件目录、本地文件系统、媒体文件存储、远程目录镜像

**Library Folder**：Media Library 中的用户分类容器，不对应系统文件夹。
_Avoid_：本地文件夹、Documents 文件夹

**Source Directory**：本地文件系统或远程来源实际拥有的目录。Enchron 只在来源浏览器中读取其结构；尤其对于远程来源，不创建、重命名、移动或删除 Source Directory。
_Avoid_：Library Folder、Enchron 管理的远程文件夹

**Local Source**：由 visionOS 文件系统或 Photos 拥有的媒体来源。Enchron 通过系统授权后的 bookmark 或 Photos identifier 保存地址，不接管媒体数据。

**Remote Source**：由 SMB 或 WebDAV 服务拥有的媒体与目录结构。Enchron 按来源原有结构进行只读浏览和播放，不提供远程文件或目录管理。服务器、协议、规范端口与账号命名空间共同参与远程身份；同一账号可以跨等价来源配置识别同一媒体，不同账号不得共享 Media Identity、观看状态、格式偏好或 Keychain 凭据。

**Media Reference**：指向系统文件、Photos 资源或远程媒体的持久引用；删除引用不删除来源。
_Avoid_：导入文件、文件副本

**Media Identity**：Enchron 用于识别同一底层媒体的稳定身份，与用户从哪个 Library Folder、Media Reference 或来源浏览入口打开它无关。具体身份算法属于实现约束，不以显示名称单独判断。

**Persistent Viewing State**：Enchron 为同一 Media Identity 只持久化可恢复位置或已看完状态，不建设通用观看历史、最近播放列表或可扩展的观看状态机。只有总时长不少于 15 分钟的媒体参与这套机制；较短媒体不持久化进度或已看完。可恢复位置还要求当前 Media Session 已真正开始、尚未接近结尾且 Content Revision 未变化。
_Avoid_：通用观看历史、最近播放能力、由 Media Library 决定保存规则

**有效播放时间**：同一 Media Session 中，Playback Lifecycle 为 playing 且媒体时间线实际前进的累计时间；暂停、缓冲和 seek 跳跃不计入。累计有效播放达到 15 秒后，当前会话才算真正开始，播放位置才可能成为 Playback Progress。
_Avoid_：App 打开时长、暂停停留时间、缓冲时间、seek 跨越的媒体时间

**足够长的内容**：已获得可靠总时长且时长不少于 15 分钟的媒体。只有足够长的内容才可能保存 Playback Progress；较短媒体仍能正常播放，但不产生 Resume 位置。
_Avoid_：通过文件大小、扩展名或名称推测时长、总时长未知时提前保存 Resume 位置

**接近结尾**：媒体剩余时间不超过总时长的 10% 与 5 分钟中的较小值，即 `remaining <= min(duration × 10%, 5 minutes)`。进入该区间后不再保存 Resume 位置，但仅凭进入该区间不标记为已看完。
_Avoid_：所有媒体统一使用固定分钟数、所有媒体统一使用固定百分比、接近结尾自动等同于已看完

**已看完**：总时长不少于 15 分钟的媒体自然播放结束后保存的 Persistent Viewing State。再次打开时从头播放且不询问 Resume；用户清除该媒体或全部播放进度时同时清除已看完状态。不足 15 分钟的媒体不持久化已看完。
_Avoid_：仅因 seek 或退出时接近结尾而标记、把结尾位置保存为 Resume、自动按时间过期

**Ended Surface**：自然播放结束且 End Behavior 不触发 Play Next 或 Repeat One 时，当前 Media Session 与 Playback Presentation 继续存在，但视频画面为纯黑，不自动显示结束信息或播放控件。用户召唤播放控件后，主播放按钮显示 Replay；控件隐藏后再次召唤仍保持 Replay，直到用户重播、seek 离开结尾或退出当前媒体。
_Avoid_：保留最后一帧、自动结束画面、自然结束后自动关闭 Media Session 或 Playback Presentation

**After Seek Behavior**：每个 seek 命令必须明确完成后保留播放意图或暂停，不由 PlaybackCore 猜测来源控件。Progress Bar 与前后跳转保持原 playing/paused 意图；Precision Timeline seek 与逐帧始终停在目标位置。Ended 没有 playing 意图，因此从 ended 通过任一可用 seek 离开结尾后保持暂停。seek 到结尾本身进入 ended、纯黑并显示 Replay，但不构成自然播放结束。
_Avoid_：所有 seek 一律播放、所有 seek 一律暂停、从 ended 推断 playing、Core 依赖进度条或时间轴等 UI 概念、把进度条称作粗略进度条

**Ended Transport Availability**：Ended 时 Replay 可用；后退、向结尾之前拖动进度条、向结尾之前操作精确时间轴和上一帧可用。这些 seek 从 Ended 离开结尾后都保持暂停。已经位于结尾时，前进跳转与下一帧禁用。离开结尾后不再是 ended，但继续使用同一 Media Session。
_Avoid_：可点击但无效果的前进按钮、seek 后重开媒体、把 ended 当成已关闭 Session

**Collapsed Playback Deck**：未展开 Advanced Settings 或 Precision Timeline 时的播放控制面板。Settings 与 More 分置两端，后退 15 秒、Play/Pause/Replay、前进 15 秒组成居中的 transport group。Settings 展开 Advanced Settings；More 打开离散播放选项菜单；双击 Progress Bar 的圆形 scrubber 打开 Precision Timeline。
_Avoid_：在 Deck 中加入 Docking/Panorama 入口、改变固定控制顺序、把 Settings 与 More 合并

**Progress Bar**：Playback Deck 中按媒体总时长显示与调节当前位置的常规进度控件。Enchron 另有 Precision Timeline；两者是不同控件，不使用“粗略进度条”一词。

**Precision Timeline**：Advanced Settings 展开状态中的精确时间定位控件，支持精确 seek 与逐帧操作，完成后保持暂停。

**Playback Progress**：Persistent Viewing State 中属于 Media Identity 的可恢复位置，而不属于 Media Reference。相同底层媒体从不同 Library Folder、Media Reference 或来源浏览入口打开时共享一份进度。Media Library 只能读取用于展示的投影，不拥有或修改保存策略。
_Avoid_：每个 Library Reference 各自记录进度、以显示名称判断同一媒体、Media Library 写入进度

**Resume Decision**：当 Resume Policy 要求询问且存在有效 Playback Progress 时，只提供 Resume 与 Start Over。用户选择媒体已经表达打开意图，因此询问不提供 Cancel，也不能通过该询问返回浏览器。
_Avoid_：Cancel、Back-to-Browser、把 Resume 询问当成是否打开媒体的确认

**Viewing Progress Indicator**：媒体卡片进入 Gaze/Hover 状态时，在底边按已保存的 `position / duration` 绘制的图形投影。它表达上次已知观看进度，不承诺当前媒体已经通过 Content Revision 的最终 Resume 验证。文件夹进入后异步批量取得投影并缓存；Gaze/Hover 本身只读取内存，不触发持久化、媒体解析或网络查询。
_Avoid_：把指示器当成已验证的 Resume 承诺、用固定假定时长计算比例、在 Gaze/Hover 事件中启动 I/O

**Content Revision**：由具体来源为 Media Identity 提供的不透明内容版本凭据，用于判断保存 Playback Progress 后媒体内容是否被替换。本地文件、Photos、SMB 与 WebDAV 可以使用各自可获得的文件标识、内容版本、ETag、大小和修改时间组合；不要求读取并哈希完整媒体。只有当前 Content Revision 与保存时相同才允许 Resume；发生变化或无法可靠取得时不提供 Resume，但不阻止从头播放。
_Avoid_：只比较显示名称、为 Resume 扫描完整媒体、无法验证时乐观套用旧进度

**Add to Library**：创建 Media Reference，不复制、移动或修改媒体来源。
_Avoid_：导入

**Playback Collection**：用户选择媒体时，该媒体所在的 Library Folder 或 Source Directory。它定义本次连续播放可以包含的媒体范围；不根据名称相似性跨容器自动合并。Library Folder 是虚拟分类；Source Directory 是来源拥有的真实目录，二者不因此成为同一种所有权。

**Playback Queue**：从 Playback Collection 中按名称自然升序生成、并在用户开始播放时固定的媒体序列。媒体库之后的搜索、浏览排序或内容变化不改变当前 Playback Queue；用户从另一个集合或另一媒体重新开始播放时建立新队列。
_Avoid_：当前媒体库视图顺序、随浏览排序实时变化的队列、按相似名称跨文件夹拼接

**名称自然升序**：按名称从低到高排列，并将名称中的数字作为数值比较，使 `Episode 2` 排在 `Episode 10` 之前。选集菜单与 Play Next 固定使用此顺序，不提供独立排序方式。

**Play Next**：在当前固定 Playback Queue 中打开当前媒体之后的媒体；不重新读取媒体库页面的排序或筛选状态。

**Queue Presentation Compatibility**：Episodes 或 Play Next 打开新媒体时重新应用该媒体自己的 Media Format Preference。Docked 与 Flat 兼容，Panorama 与 panoramic format 兼容；不兼容时先返回 Window，再按新格式决定是否进入 Panorama。这个连续呈现行为不把 Docked 写成媒体偏好。

visionOS 管理外面的 System Surroundings；Enchron 打开自己的 Immersive Space，并在里面显示 Enchron Environment。

**System Surroundings**：由 visionOS 管理的用户周围视觉环境，包括 Reality Passthrough 与 Apple System Environment。Enchron 不拥有、识别或持久化其中具体的系统状态。
_Avoid_：Enchron Environment、Apple Immersive Space、由 Enchron 恢复具体 Apple System Environment

**Enchron Immersive Space**：Enchron 使用 visionOS `ImmersiveSpace` Scene 打开的无窗口边界空间，是承载 Enchron Environment 与空间播放呈现的平台容器，不是 Environment 身份。
_Avoid_：Apple System Environment、Enchron Environment、第四种 Playback Presentation

**Immersive Space Open Cycle**：同一个 Enchron Immersive Space 从 Scene 确认出现到确认消失之间的连续生命周期。Environment、Docked 与 Panorama 是这个 Open Cycle 内可以变化的空间内容；它们的切换不重新打开 Scene，也不重置用户当前的 Progressive Immersion Amount。Scene 消失即结束当前 Open Cycle，后续恢复或产品入口重新打开时形成新的 Open Cycle。
_Avoid_：一次 Playback Presentation、一次 Media Session、把 Environment/Docked/Panorama 切换当成新的 Open Cycle、把 Digital Crown 调到最小值当成关闭 Scene

**Progressive Immersion Amount**：Enchron Immersive Space 统一采用 Progressive immersion 时，由 visionOS 持有并允许用户通过 Digital Crown 在 `0.3...1.0` 内调节的当前沉浸量。Enchron 只观察该系统事实并在当前 App 进程内记住最近值；同一 Immersive Space Open Cycle 内切换 Environment、Docked 或 Panorama 不改变它。Environment 或 Docked 新开空间时使用最近值，没有最近值时使用系统默认；Panorama 新开空间时从 `1.0` 开始，但已经打开的空间进入 Panorama 时保持当前值。
_Avoid_：Playback Presentation、Environment Effect、App 内滑杆、跨进程偏好、Panorama 始终强制为 `1.0`、把 `.mixed` 或 `.full` 当成 Enchron 的空间内容状态

**Environment Context**：当前没有活动观影场景，或某个 Environment 及其 Environment Effect 已经打开。它独立于 Media Session 与 Playback Presentation：用户可以在 Media Library 阶段先打开 Environment，退出当前媒体也不会自动关闭它。
_Avoid_：只有播放视频后才存在的场景状态、退出媒体时自动关闭 Environment、把 Environment Context 并入 Playback Presentation

**Environment**：Enchron 正式交付的一个观影场景身份，可以在没有打开媒体时独立活动。Environment 与其 Environment Effect 是两个正交概念；同一场景的 Day/Night 特效不形成两个 Environment。每个 Environment 拥有一个语义一致的 Playback Surface Anchor 和一份相对摆位。Enchron V1 交付一个 Environment 及其 Day/Night 两个 Environment Effect；当前内容和名称仍可使用占位符。
_Avoid_：把昼夜特效建模成两个 Environment、把原型标签当成多个产品场景、按 Environment 与 Environment Effect 组合复制用户摆位

**Environment Effect**：同一 Enchron Environment 内部可切换的视觉特效状态，V1 只有 Day 与 Night；它不改变 Environment 身份，并与同一 Environment 的其他 Effect 共享 Playback Surface Anchor 语义和用户摆位。
_Avoid_：Environment Appearance、独立场景身份、Default Environment 的组成部分、独立摆位身份、Docking 菜单中的 Environment 列表

**Environment Card**：用户浏览、打开或关闭 Enchron Environment，并调节其 Environment Effect 的独立 Volume；Environment Tab 是它在 Window 界面中的入口。系统中只存在一个 Environment Card 实例，它不属于 Playback Deck、Media Session 或 Playback Presentation，也不是 Panorama 的控制界面。
_Avoid_：把 Day/Night 拆成两张 Environment Card、重复创建多个 Environment Card Volume、在卡片内提供替代系统 Window Bar 的返回按钮、从 Panorama 打开 Environment Card

**Environment Card Residency**：同一个 Environment Card singleton Window 当前为 closed、正在 opening，或已经 open 的空间事实。它由空间体验 owner 独立持有，并由 Window Scene 的出现与消失事件结算；重复入口只聚焦现有实例，不创建第二个 Card，也不改变 Playback Presentation。
_Avoid_：AppModel 的第二个布尔标记、用 Card residency 推断 Playback Presentation、把聚焦现有 Card 当成新建实例

**Default Environment**：当用户没有活动 Enchron Environment 时，Docking 临时打开的特定 Environment 身份。它只选择 Environment，不包含 Day/Night 等 Environment Effect。
_Avoid_：Default Environment Appearance、Environment 与 Effect 的组合预设

**Docking Target Resolution**：Docking 不选择 Environment 身份。存在活动 Environment 时继承该身份；不存在时临时使用 Default Environment。Docking 二级菜单选择的 Day 或 Night 只属于本次 Docked Presentation，不修改独立活动 Environment 的 Environment Effect；返回 Window 或退出媒体后恢复进入 Docked 前的 Environment Context。未来增加 Environment 时仍遵守此规则，避免列出 Environment × Environment Effect 的组合。
_Avoid_：在 Docking 菜单中浏览全部 Environment、为每个 Environment 展开全部 Environment Effect、Docking 隐式选择非活动且非默认场景、把 Docked Environment Effect 写回活动 Environment、退出 Docked 后保留临时 Environment Effect

**Playback Surface Anchor**：Reality Composer Pro Environment 对 Docked 视频基准位置与朝向的唯一场景定义；产品调整只表达相对该 anchor 的变换。
_Avoid_：world 原点绝对坐标、运行时自定屏幕位置、Docking Region

**Screen Size**：Docked Video Entity 相对一米基准高度的 uniform scale，以百分比向用户呈现；宽度由 RealityKit 根据视频宽高比生成。
_Avoid_：屏幕宽度、非等比缩放、Window 尺寸、Panorama 尺寸

**Docked Placement**：Docked 的用户调节由 Screen Size、Distance 与 Elevation 组成。Distance 是用户到屏幕的半径，当前 Environment 推荐默认值为 4 米；Elevation 以用户为球心、以当前 Distance 为半径，让屏幕沿垂直圆弧向上或向下旋转，并在所有位置始终朝向用户。恢复默认值将其还原到 Environment 推荐摆位；这些设置按 Environment 保存并由 Day/Night Environment Effect 共享。
_Avoid_：把 anchor 局部 Z offset 当成用户距离、把旧版 depth/vertical offset 直接迁移成新语义、世界坐标 Y 平移
_Avoid_：把 Elevation 实现成世界坐标 Y 平移、旋转后不再朝向用户、为 Day/Night 分别保存摆位、保存 Docked Presentation 本身

**Docked**：Enchron App 将当前 renderer 放入所选 Reality Composer Pro 场景的 Playback Presentation。

**Panorama**：Enchron App 使用 `VideoPlayerComponent` immersive viewing behavior 呈现当前 renderer 的 Playback Presentation。

**Panorama Format Selection**：Window 的 Panorama 二级菜单正交选择 Projection 与 Stereo Layout。Projection 提供 180°、360° 与 Fisheye；Stereo Layout 提供 Mono、Side-by-Side 与 Top-Bottom。用户完成两个维度的选择后点击 Apply，成功应用完整 Media Format 并进入 Panorama；菜单不因单个轴的选择而提前提交。Fisheye 只有来源已携带 Apple Immersive Media Experience（AIME）投影事实时才可应用，不能由用户选择伪造。
_Avoid_：遗漏 Mono、把 Projection 与 Stereo Layout 合并为组合枚举、单个轴变化时提交不完整格式、无 AIME 事实时强制 Fisheye

**Persisted Panorama Reopen**：相同 Media Identity 的 Content Revision 未变化且存在用户保存的 panoramic Media Format Preference 时，再次打开媒体在完成 Resume Decision 后自动进入该 Panorama 格式。自动恢复只来自用户保存的选择；Docked 不自动恢复。Panorama 转换失败时保留同一 Media Session 并回退 Window。
_Avoid_：再次要求点击 Panorama、根据内容检测自动进入、恢复 Docked、转换失败时关闭媒体

**Reset to Flat + Mono**：Panorama Advanced Settings 中撤销当前媒体 Media Format Preference 的操作。成功后事务式切换为 Flat + Mono、返回 Window，并恢复 Docking 与首次 Panorama 格式入口。它不清除 Persistent Viewing State。
_Avoid_：仅返回 Window却保留偏好、把 Flat 混入首次 Panorama 投影选项、同时清除观看进度

**Window Presentation Actions**：只在 Window 视频界面上提供退出当前媒体、进入 Docked 的二级菜单入口，以及展开 Panorama 格式选择的入口。Docked 与 Panorama 入口不属于 Playback Deck。

**Docked Presentation Actions**：Docked 的 Video Entity 或 Mesh 不承载可点击按钮。召唤 Playback Deck 后只提供播放控制和返回 Window；不提供直接退出当前媒体的 Back。

**Panorama Presentation Actions**：召唤 Playback Deck 后提供播放控制、返回 Window，以及直接退出当前媒体并回到 Window Media Library 的 Back。退出媒体不主动关闭已经存在的 Environment Context。

**Presentation Transition**：从一个稳定 Playback Presentation 到另一个稳定 Presentation 的暂态。它绑定发起时的 Media Session；原先 Playing 时在平台效果前暂停，暂停失败则平台效果不开始并回滚。平台效果结算后按 owner 的策略恢复；若效果已经提交而恢复播放失败，保留已提交的 Presentation 并显式记录失败，不能伪装成平台回滚。原先 Paused、Ready 或 Ended 时不改变播放状态。

**Spatial Platform Effect**：空间体验所有者要求 App 平台层执行的 visionOS 或 RealityKit 操作，例如打开 Immersive Space、聚焦 Window、切换 immersion style 或绑定当前 Scene 的播放表面。同一时刻只有一个待执行效果；每个请求具有稳定身份，平台层只有在当前存在可执行 SwiftUI Scene action 的根时才认领，否则请求继续留在 owner，待可执行根再次出现后处理。空间体验所有者忽略重复或迟到结果，并独自决定提交或回滚 Presentation Transition；平台层不决定目标 Presentation，也不直接改写 Environment Context。

**Spatial Recovery Intent**：Home View 或其他系统行为非预期关闭 Enchron Immersive Space 后，仅存在于当前 App 进程内存中的恢复事务值。它保存仍然有效的 Docked 或 Panorama、Media Session 身份与关闭前是否 Playing；owner 保持原稳定 Presentation，要求 App 暂停原 session 并显式重建同一空间呈现，成功后只有原先 Playing 才恢复播放。旧 session 的 intent/result 不作用于新媒体；失败时清除 intent、一次性收敛到 Window 且不自动重试。主动返回 Window、停止播放、Environment preview/Card 和 Window residency 不创建该 intent。它不是第四种 Playback Presentation，也不写入 Resume、UserDefaults、SceneStorage、数据库或文件。

## 验证

**无人值守 Vision Pro XCTest 宿主**：完成一次性系统授权与预检后，使 Vision Pro 保持可运行状态并持续执行 Enchron 真机 XCTest 的测试环境；宿主可用性本身不构成产品通过证据。
_Avoid_：CI runner、产品运行环境、测试已通过

**真实用户旅程 E2E**：从正常 Enchron App 用户状态出发，所有来源创建、媒体选择和播放操作都经过公开产品界面完成的端到端验证。
_Avoid_：autoplay 注入、直接调用 ViewModel、单按钮冒烟测试

**真实 UI 输入**：由 Computer Use 或操作系统鼠标、键盘、滚动与拖动事件经过正常 hit testing 触发生产 UI action 的用户输入；自动化只能替代用户执行输入，不能替代产品 UI 或业务入口。
_Avoid_：Accessibility action 直调、测试 command、内部状态注入

**协议远程源 E2E**：通过生产 SMB 或 WebDAV adapter 完成来源创建、浏览、读取与播放的端到端验证；协议服务器可以与 Enchron App 位于同一台 Mac。
_Avoid_：跨设备网络 E2E、直接文件读取、远程协议单元测试

**跨设备网络 E2E**：协议服务器位于另一台设备或独立网络环境中的远程源端到端验证，用于补充本机协议远程源 E2E 无法证明的网络行为。
_Avoid_：loopback 测试、本机共享、协议远程源 E2E

**PlaybackCore 单元与合同验证**：不依赖产品播放界面的核心合同、媒体容器与媒体 Sample 验证。

**visionOS 产品集成验证**：visionOS Enchron App 使用生产 `PlaybackRuntime`、真实 Renderer、RealityKit 渲染接收方和同一 Media Session，证明产品接入、空间呈现与持续输出符合合同。

**Vision Pro 真机验收**：在物理 Vision Pro 上验证硬件解码、HDR/EDR、音频、空间呈现、性能与最终交互。

**空间呈现结构验证通过**：Playback Presentation 的 Scene、播放表面、Renderer 绑定、RealityKit 实际呈现模式与 Media Session 连续性全部符合产品合同。
_Avoid_：视觉正确、模式切换成功

**空间呈现感知验收通过**：用户实际看到的视频位置、尺度、投影、左右眼方向、视场与空间舒适度符合产品定义；即使代码结构检查通过，这项验收仍需单独执行。
_Avoid_：结构成功、无报错、renderer ready

**RealityKit 渲染结果验证通过**：在规定摄像机位置与朝向下，RealityKit 输出满足测试媒体中预先定义的方向和几何标记。
_Avoid_：Vision Pro 真机体验通过、仅有结构正确

**Vision Pro 真机体验验收通过**：真实佩戴者确认空间尺度、头部运动响应、舒适度、HDR/EDR 与沉浸感符合产品要求。
_Avoid_：RealityKit 离屏渲染结果通过、AirPlay 画面正确

**Diagnostic Media**：通过真实产品播放路径进入 RealityKit、并以方向、几何、双眼与时间标记提供机器视觉 oracle 的专用验收媒体。
_Avoid_：普通电影画面、UI fixture、静态占位图

**真实世界媒体**：来自实际制作或发行流程、用于观察格式兼容性和真实观看表现的媒体；它补充 Diagnostic Media，但不单独提供确定性的机器视觉 oracle。
_Avoid_：Diagnostic Media、生成 fixture、静态占位图

**Visual Oracle**：根据 Diagnostic Media 的语义标记、方向与几何关系判断渲染结果的机器合同；逐像素参考图只作为诊断附件。
_Avoid_：像素完全一致、无黑屏即正确、普通截图目测

**DesignPreview**：生产组件的代码化陈列入口，不拥有产品导航或业务状态。

**Product Runtime Observability**：由 OSLog、signpost、Xcode、LLDB、Console、Instruments 与测试产出的可关联运行事实。
