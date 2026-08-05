# Enchron 共享真机场景

本目录登记已经逐条确认方向的物理 Vision Pro 共享真机场景。产品行为与通过条件由 Enchron 当前规格定义；执行与取证共同规则由 [`AGENTS.md`](AGENTS.md) 定义。本文件只连接用户行为、场景依赖、校准状态、自动化边界、人类感知边界和重新校准条件，不记录旧测试方法的迁移历史。

现有 XCTest 到这些场景的一次性迁移位于 [`MIGRATION.md`](MIGRATION.md)。Test Plan、诊断用例和测试基础设施入口不会因为已经存在或曾经通过而自动成为共享真机场景。

## 当前场景

### 本地媒体 Window 基础播放闭环

用户从正常 Media Library 通过公开媒体卡片打开一个固定登记的本地标准媒体，在 Window 中确认真实画面与声音开始，依次执行 Pause、Resume 和一次播放态 Seek，最后退出媒体并返回 Media Library。

- 校准状态：等待审查历史人类验收证据并明确可移交的机械条件。
- 固定媒体：`generated-sdr-avc-bframe-multiaudio-avsync-30s-v1`；项目生成的 H.264 SDR B-frame、双 AAC 音轨、闪光与音频脉冲同步标记媒体。
- 自动化边界：必须直接观察同一 Media Session 的 Playback Lifecycle、实际时间线、sample、renderer input、Window consumer、公开控件操作和退出清理；播放控制依次覆盖普通播放态 Seek、开头收束、结尾收束、Ended Surface 与 Replay。真正小于起点或大于结尾的请求由 PlaybackCore 快速合同测试证明，不通过屏幕外拖动模拟。这些事实不能替代画面内容与物理声音判断。
- 启动变体：另用能够确定性延迟首帧交付的测试来源执行独立测试方法，验证媒体打开期间沿用同一个系统 Window、同一个 Window Playback `RealityView` 从加载开始持续挂载、`LoadingSpinner` 在等待期间实际可见、Window Chrome 与 PlayerControls Ornament 尚未出现，以及首帧实际可见后 Spinner 消失并进入正常播放界面。加载阶段与首帧后的机械状态和截图共同判定；该变体在语义上仍属于本场景，不把普通基础播放人为放慢。
- 人类边界：校准实际画面、声音和操作反馈，并确认现有证据尚未表达的异常。
- 范围限制：这条确定性诊断媒体场景不证明真实世界媒体的整体画质、声音和观看感受；后者由独立、低频的人类感知抽验承担。

### 连续媒体 Session 隔离

用户从正常 Media Library 依次打开并关闭两个固定登记媒体；第二个媒体建立新的 Media Session，前一个媒体的播放表面、控制面、输出和资源不残留。

- 依赖：在本地媒体 Window 基础播放闭环建立可信判定后校准。
- 自动化边界：比较两次 Media Session 身份、consumer 与控制面清理、第二个媒体的独立持续输出，并保存每次打开与退出的直接证据。
- 人类边界：只有媒体组合触及新的画面、声音或格式感知条件时才重新请求人类验收。

### 登记媒体矩阵的 Window 播放覆盖

每个登记媒体从正常 Media Library 单独打开，在 Window 中按该媒体明确声明的格式与预期能力验证启动、首帧、持续输出、适用的声音或字幕结果以及退出清理。

- 依赖：复用本地媒体 Window 基础播放闭环已经校准的操作和判定。
- 数据边界：每个固定媒体声明容器、视频、音频、字幕及其它相关特征，并声明当前产品和设备组合的准确预期。支持的媒体必须形成真实输出；只有明确登记为当前设备不支持的组合才验证对应的准确预检失败。
- 执行边界：每个登记媒体是独立测试用例，失败或未评估不阻止其余媒体执行；整轮结束后按媒体身份汇总。不能用错误信息中笼统出现“unsupported codec”接受本应支持的媒体失败。
- 视觉证据：每个用例按动态视觉证据规则保留连续录制、可快速通览的多帧汇总图和关键清晰帧；声音、字幕和特定格式感知要求使用各自直接证据。
- 范围限制：设备生产 Media Library 中未登记媒体的遍历只用于按需探索与发现新的矩阵候选，不产生正式通过结论。

### 本地 Media Reference 删除与重新添加

用户在受控的空 Media Library 中通过系统文件选择器 Add Files，为固定本地来源创建 Media Reference 并打开播放；随后从 Enchron 删除该 Media Reference，确认来源文件仍由原系统位置拥有，再次添加同一来源并重新打开。

- 固定媒体：复用 Window 基础播放闭环的 `generated-sdr-avc-bframe-multiaudio-avsync-30s-v1`。
- 自动化边界：验证公开 Add Files 路径、Media Reference 创建与删除、来源文件在系统文件选择器中仍可重新选择、再次添加成功，以及两次打开均达到已经校准的基础播放启动条件。
- 人类边界：只有系统文件选择器交互或媒体打开触及新的感知问题时请求复核。

### 从 Photos 建立 Media Reference 并首次播放

用户通过 Add from Photos 和系统 Photos Picker 选择预先准备的固定视频；Enchron 保存 Photos identifier 所表示的 Media Reference，随后从正常 Media Library 打开它并开始 Window 播放。

- 固定媒体与设备前置条件：物理 Vision Pro 的 Photos 中预先放置可稳定识别的登记视频，并具有能够完成系统 Photos 授权和选择器交互的测试状态；不得任意选择 Photos 中的第一个资源。
- 自动化边界：验证公开 Photos 授权、系统选择器、Media Reference 建立与正常 Media Library 打开，并复用已经校准的 Window 基础播放启动条件证明真实画面、连续时间推进和声音。不得只以 `playing` Accessibility value 代替实际输出。
- 执行边界：不得为了该场景清空设备上已有的整个 Enchron Media Library。固定 Photos 素材或可处理的授权前置条件缺失时，将本场景记录为前置条件不满足并继续完整轮换。
- 人类边界：首次校准系统选择器交互与实际播放；后续只有 Photos 系统流程或媒体感知条件变化时请求复核。

### Media Library Grid 自适应布局

用户在 Media Library 中查看不同数据规模与卡片种类的 Grid；卡片保持规定尺寸、对齐与间距，内容不会重叠，滚动后的排列保持稳定，并且实际渲染结果在物理 Vision Pro 中视觉正确。

- 独立数据用例：单个媒体；一至两个媒体与一个 Library Folder 组成的稀疏混合布局；包含多行媒体、Library Folder 和长标题的大量混合布局。三个用例使用确定性 Media Library 数据并分别执行，一个用例失败不阻止其余用例收集证据。
- 自动化边界：检查卡片外部尺寸、未被剩余空间拉伸、行列对齐、间距、重叠、自适应列数、滚动和懒加载后的稳定位置，以及长标题不会改变卡片几何；每个数据用例保存完整窗口截图。
- 综合判定：机械几何断言与截图视觉判断共同构成结论。几何断言全部满足但截图看起来错误时，场景仍然有问题；生成了截图也不能代替机械条件。首次由人类校准视觉结果，后续自动执行保存可比较证据并把无法可靠判断或疑似异常的截图交给人类。

### Media Library 当前层级搜索

用户在当前打开的 Library Folder 中输入搜索文本；Grid 只保留直接子 Library Folder 与 Media Reference 中显示名称匹配的项目，深层项目不被拉入当前结果，清空查询后恢复当前层级的完整内容。

- 依赖：复用 Grid 自适应布局的确定性混合数据，但作为独立场景执行。
- 匹配规则：查询去除首尾空白后，按本地化、不区分大小写的包含关系匹配。Library Folder 使用完整显示名，Media Reference 使用去掉文件扩展名后的显示名；隐藏路径、来源、codec 和其它 metadata 不参与。
- 自动化边界：从当前层完整内容开始，输入包含大小写变化与首尾空白的部分名称，验证匹配的直接文件夹和媒体保留、不匹配项目消失、深层同名项目不出现，并在清空查询后恢复完整结果集合。快速逻辑测试覆盖更多字符串组合。
- 视觉证据：真机操作保存连续录制、过滤前后多帧汇总图和清晰帧，并结合结果集合机械断言判断实际 Grid 变化。

### 层级浏览导航

用户在 Media Library 的 Library Folder 层级或来源浏览器的 Source Directory 层级中进入子层级，通过面包屑返回祖先，并使用后退与前进恢复浏览位置；往返只改变当前浏览位置，内容位置与媒体身份保持不变。

- 执行划分：Library Folder、SMB Source Directory 与 WebDAV Source Directory 是分别执行的独立上下文，不合并成长测试。
- Library Folder 用例：使用确定性虚拟层级验证进入、面包屑、后退、前进、当前 identity 链及直接内容恢复。
- Remote Source 用例：由 SMB 与 WebDAV 的真实协议场景复用同一套导航检查，以 Remote Source identity 和目录路径判断当前位置，并确认不出现创建、重命名、移动或删除 Source Directory 与远程媒体的操作。
- 自动化边界：机械状态与 Grid 内容集合、连续录制、多帧汇总图和关键清晰帧共同判断；重新展示同一媒体不得生成新的 Media Identity。

### Library Folder 管理

用户在 Media Library 中创建、嵌套和重命名虚拟 Library Folder，并在其中移动 Media Reference；用户确认移除非空文件夹后，整棵虚拟子树及其中引用消失，来源媒体保持不变。

- 依赖：使用已经校准的 Library Folder 层级浏览导航。
- 目录结构用例：创建根文件夹与子文件夹、重命名并在 App 重启后确认层级和名称持久存在；同一父级下去除首尾空白并忽略大小写后的重名被拒绝，原状态保留且出现可恢复提示，不同父级允许同名。
- 引用组织与删除用例：把固定 Media Reference 移入子文件夹，从新位置打开并保持 Media Identity；确认删除父文件夹后验证子树与引用消失、来源仍存在并可再次建立引用。
- 快速合同：名称清理、空名称、同级重名、不同父级同名、引用移动和递归删除集合由模型测试直接覆盖。

### Settings 分类导航与视觉组装

用户从 Main Window 进入 Settings，依次切换 Playback、Storage & Privacy 与 About；每次只有一个分类被选中，详情区域显示对应的生产设置内容，实际布局在物理 Vision Pro 中完整可读。

- 自动化边界：验证公开 Settings 入口、唯一选中分类、对应详情组、往返后的导航状态和基本 frame；保存完整操作录制、分类切换汇总图及每个分类的清晰帧，并结合机械断言与视觉判断结算。
- 行为边界：Resume Playback、End of Playback、Default Speed 与 Controls Auto-Hide 通过各自设置驱动场景变体验证实际产品结果。Thumbnail Cache 与 Playback Progress 清理进入对应数据场景；Privacy Notice、Version & Build、Support & Feedback 和 Open-source Licenses 的静态内容与局部动作由快速 UI 测试覆盖。
- 设置覆盖：设置驱动场景变体默认在物理 Vision Pro 上逐个覆盖全部产品选项。当前只有 Default Speed 的播放倍数按本目录 `AGENTS.md` 中已经确认的规则，在快速层穷举全部值后选择真机边界与代表值并跨轮次替换；Resume Playback、End of Playback、Controls Auto-Hide 和数据清理动作不使用该抽样例外。

### WebDAV 来源建立、浏览与播放

用户通过公开来源界面创建 WebDAV Remote Source，完成认证并浏览服务端原有 Source Directory，将固定远程媒体建立为 Media Reference，从正常 Media Library 打开并形成真实播放；重新启动 App 后，该来源配置与 Keychain 凭据仍能解析引用。

- 自动化边界：验证来源创建、实际协议认证、目录浏览、只读边界、Media Reference 建立、正常播放、App 重启后的解析，以及失败时准确且可恢复的反馈。表单字段存在性和基本输入校验由快速 UI 或模型测试承担。
- 证据边界：保存连续录制、阶段汇总图、关键清晰帧和协议/播放状态；任何附件、日志或截图不得包含明文凭据。

### SMB 来源建立、浏览与播放

用户通过公开来源界面创建 SMB Remote Source，指定服务器与 Share，完成认证并浏览服务端原有 Source Directory，将固定远程媒体建立为 Media Reference，从正常 Media Library 打开并形成真实播放；重新启动 App 后仍能解析引用。

- 独立认证用例：一条使用账号与密码连接固定 Share，并验证 App 重启后的 Keychain 解析；另一条使用允许匿名访问的固定 Share 通过 Guest 连接，不要求或保存用户密码。两个用例分别执行，一个失败不阻止另一个。
- 自动化边界：验证来源创建、实际 SMB 协议认证、Share 浏览、只读边界、Media Reference 建立、正常播放和 App 重启后的解析。Address 与 Share 必填、非 Guest 模式的账号密码要求以及 Connect 启用条件由快速表单测试承担。
- 证据边界：保存连续录制、阶段汇总图、关键清晰帧和协议/播放状态；任何附件、日志或截图不得包含明文凭据。

### 打开媒体时自动关联同目录独立字幕

用户从具有可枚举 Source Directory 的 Media Reference 打开媒体；当前 Media Session 从同目录取得名称匹配的独立字幕文件，将多个候选加入字幕轨列表，并保持 Subtitle Off，不替用户猜测选择。

- 依赖：使用已经校准的本地媒体 Window 基础播放闭环。
- 用户行为边界：候选关联发生在打开媒体、建立当前 Media Session 时，不发生在 Media Library 浏览阶段。
- 媒体覆盖：至少覆盖普通文本字幕与带样式字幕；具体 SubRip、ASS 等格式属于媒体矩阵，不形成独立顶层用户场景。
- 自动化边界：验证当前 Session 的字幕轨列表、多个候选各自存在、初始 Off、播放不中断，以及候选来源归属当前 Session。

### 播放期间选择字幕与关闭字幕

用户在当前 Media Session 的 Subtitles 菜单中选择一个可用字幕轨、切换到另一字幕轨或选择 Off；视频、音频、Playback Presentation、媒体时间和 Media Session 保持连续。

- 依赖：字幕轨已经通过容器或同目录独立字幕来源进入当前 Media Session。
- 用户行为边界：容器内字幕轨与自动关联的同目录独立字幕轨进入同一个菜单；用户选择轨道时不需要区分来源，不按字幕文件格式复制用户旅程。
- 自动化边界：验证轨道身份、cue 与当前时间对应、Session 与播放连续性、Off 清除当前 cue，并使用截图区域或其它直接画面证据判断字幕是否实际显示。
- 人类边界：首次校准中文字符、样式、位置和可读性；Accessibility value 不能代替佩戴者可见像素。

### 重新打开媒体时恢复轨道选择

用户为当前媒体明确选择音轨以及某条字幕轨或 Off，关闭后重新打开相同 Media Identity 与 Content Revision 的媒体；新 Media Session 在完整轨道列表中按稳定轨道身份恢复仍然存在的选择。

- 自动化边界：验证关闭前后的 Media Session 不同、Content Revision 相同、恢复使用稳定轨道身份、第二音轨的实际独有输出、字幕实际画面或 Off 后 cue 与像素消失。
- 人类边界：首次校准不同音轨的可听输出和字幕画面；状态字段不能分别代替声音与像素。

### Window 与 Docked 完整往返

用户在 Window 播放期间选择 Docked；当前 Media Session 先暂停，visionOS 完成空间交接，同一个 renderer consumer 迁移到 Docked，目标视频表面与 Player Controls 可见可用并保持 Paused。用户在 Docked 明确点击 Play并确认连续画面与声音，再通过正式入口返回 Window；返回转换再次暂停，Window 恢复后保持 Paused，用户在 Window 明确点击 Play 并确认连续输出。

- 依赖：使用已经校准的本地媒体 Window 基础播放闭环。
- 自动化边界：验证暂停、同一 Session、唯一 consumer、源与目标不同时接受输入、目标 Scene/Environment/anchor/surface/controls 后置条件、无 Loading 或错误界面、目标显式 Play 前后输出事实。
- 人类边界：首次校准系统交接中是否存在明显黑帧、闪烁、重复界面或突兀视觉故障；不要求 Enchron 自有透明度曲线或固定淡入淡出时序。

### Window 播放输入归属

用户点击 Window 视频表面时，每次输入只切换一次 Window Chrome 与 Player Controls 显隐；用户操作 transport、顶部操作或展开面板时，只执行目标控件动作，不穿透到视频表面或额外改变控件显隐。

- 依赖：使用已经校准的本地媒体 Window 基础播放闭环。
- 自动化边界：完成视频表面 shown → hidden → shown，分别操作代表性的 transport、顶部操作和展开面板区域，检查目标 action、tap trace、controls visibility 和面板状态。
- 展开状态：Precision Timeline 展开后，视频表面输入隐藏整个 Player Controls，并结束这次临时展开状态；再次召唤控件时显示普通 Progress Bar。自动化保存从展开、隐藏到重新显示的连续录制、多帧汇总图和关键清晰帧。
- 变化影响：Window 层级、RealityView、overlay、ornament、顶部操作、展开面板或共享 Player Controls 变化时重跑。
- 输入所有权：Window 视频表面显隐输入由覆盖视频区域的不可见 SwiftUI 命中层拥有；Window 中禁用 RealityView Entity 的碰撞输入，避免与 SwiftUI overlay 争夺层级和 hit testing。Docked 与 Panorama 不挂载这层 SwiftUI 输入，继续由 RealityKit `InputTargetComponent`、`CollisionComponent` 和空间手势处理。

### Window 与 Panorama 完整往返

用户在 Window 播放期间选择固定的 Projection 与 Stereo Layout 并 Apply；当前 Media Session 先暂停，visionOS 完成空间交接，同一个 renderer consumer 迁移到黑色周围环境中的 Panorama，目标视频投影与 Player Controls 可见可用并保持 Paused。用户在 Panorama 明确点击 Play 并确认连续输出与投影方向，再返回 Window；Window 恢复后保持 Paused，用户明确点击 Play 并确认连续输出。

- 依赖：使用已经校准的本地媒体 Window 基础播放闭环。
- 自动化边界：复用暂停、同一 Session、唯一 consumer、输入归属、目标显式 Play 与返回的共同转换合同；另外验证黑色周围环境、surface content type、实际 immersive/viewing/spatial mode 以及固定媒体的投影和方向标记。
- Video Format 提交边界：在正式 Apply 前先打开面板并修改 Projection 或 Stereo Layout 草稿，确认仍在原 Window 且播放不受影响；Cancel 后重新打开，确认恢复此前已提交选择。随后选择固定格式并 Apply，只有这一步请求 Panorama。快速状态测试完整覆盖草稿、Cancel、外部关闭、切换菜单与 Apply。
- 人类边界：首次校准球面方向、比例、视场和明显视觉故障；不要求 Enchron 自有透明度曲线、source removal 间隔或固定淡入淡出时序。

### 活动 Environment 下的 Panorama 往返

用户在 Window 播放时已有活动 Enchron Environment 与 Environment Effect；进入 Panorama 后停止显示当前 Environment，只呈现 Panorama 的黑色周围环境，并保存进入前的 Environment Context；返回 Window 后恢复同一个 Environment 与 Effect。

- 自动化边界：复用基本 Panorama 往返的转换能力，只额外验证 Panorama 中 Environment Context 为 none、skybox 不活动、返回目标身份与 Effect、Progressive Immersion Amount、同一 Media Session 以及返回后的恢复。
- 变化影响：Environment、Panorama、Immersive Space residency、Panorama Return Environment Context 或系统恢复逻辑变化时重跑。

### 活动 Environment 下的 Docked 临时 Effect

用户在 Window 播放时已有活动 Enchron Environment 与 Environment Effect；Docking 继承当前 Environment 身份，并使用用户在 Docking 菜单中为本次 Docked 明确选择的临时 Effect。返回 Window 后恢复进入前的 Environment 与 Effect，临时选择不写回独立活动 Environment。

- 固定组合：进入前为 Night，用户选择 Dock with Day，Docked 使用同一 Environment 的 Day，返回 Window 后恢复 Night。
- 自动化边界：复用基本 Docked 往返的转换能力，只额外验证 Environment 身份继承、临时 Effect、Environment Card residency、Progressive Immersion Amount、同一 Media Session 和返回恢复。

### Default Environment 的 Docked Effect 往返

用户在没有活动 Environment 的 Window 中选择 Docked Day 或 Night；Docking 临时使用 Default Environment 与所选 Environment Effect，返回 Window 后 Environment Context 恢复为 none。两种 Effect 不改变当前 Media Session、renderer consumer 或视频表面。

- Environment：当前由使用 Skybox 占位内容的稳定 identity 承担 Default Environment；未来只替换显示内容和资源。
- 自动化边界：验证 Default Environment 身份、所选 Effect、Scene 与视频表面结构、同一 Media Session、返回后 Environment Context 为 none。
- 人类边界：首次确认 Day 与 Night 的实际内容和视觉区别；当前测试 Skybox 及其 opacity 只作为临时资源诊断，不构成产品合同。

### Docked Placement 按 Environment 持久化

用户在一个 Environment 中调整 Screen Size、Distance 与 Elevation；关闭媒体并建立新 Media Session，或终止 Enchron App 进程并重新启动后，再次进入同一 Environment 的 Docked 时恢复该摆位。进入另一个 Environment 时使用其独立摆位；同一 Environment 的 Day 与 Night 共享摆位。

- Environment 集合：当前四个稳定 identity 暂以 Skybox、淡红、淡绿和淡蓝内容区分，每个 identity 均有 Day 与 Night；未来替换正式内容与名称时保留 identity。
- 自动化边界：验证公开 Slider、实际 Entity transform、跨 Media Session 恢复、跨 App 进程恢复、不同 Environment 隔离、Day/Night 共享以及 Restore Defaults 恢复当前 Environment 推荐值。
