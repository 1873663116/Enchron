# Enchron v3 — 全覆盖 E2E QA 测试计划

> 生成时间: 2026-04-02 (v3 Round 4)
> 数据源: feature-inventory-v3.md (82 功能点) + Requirements.md + HelloWorld UX 审计
> 测试素材: 12 个文件 (T0.3 已 ffprobe 验证)
> 路径总数: 59 条 (原 55 + 对抗性审查新增 4)
> 覆盖: 81/82 功能点 (排除 1 个 ⚪ 真机限定: F9.4)
> 对抗性审查: 2026-04-02 通过三阶段裁决 (Codex 6 挑战, 采纳 4, 驳回 2)

---

## 测试素材清单

| 素材 | 用途 | 容器/编码 |
|------|------|-----------|
| SDR-test.mkv | SDR/MKV 播放 | MKV / HEVC / BT.709 |
| HDR10-test.MP4 | HDR10 播放 | MP4 / HEVC / BT.2020 PQ |
| dolby-vision-test.mp4 | DV 播放 | MP4 / HEVC+DV |
| 180-vr-test.mp4 | 180° VR | MP4 / HEVC / 180° |
| 360-test-nasa-wind-tunnel.webm | 360° 全景 | WebM / VP9 / 360° |
| SDR-test-sample.mov | MOV 容器 | MOV / HEVC / SDR |
| SDR-test-sample.avi | AVI 容器 | AVI / H.264 / SDR |
| SBS-stereo3d-test.mp4 | SBS 立体 | MP4 / H.264 / 3840x1080 |
| OU-stereo3d-test.mp4 | OU 立体 | MP4 / H.264 / 1920x2160 |
| fisheye-test.mp4 | 鱼眼投影 | MP4 / H.264 / 1920x1920 |
| HLG-test.mp4 | HLG 色彩 | MP4 / HEVC / BT.2020 HLG |
| HDR10plus-test.mp4 | HDR10+ 色彩 | MP4 / HEVC / BT.2020 PQ+MDM |

---

## 验证类型说明

- **Simulator**: 可在 Apple Vision Pro Simulator 上通过 /qa skill 执行
- **Structure**: 代码路径验证 + 单元测试确认（Simulator 无法执行真实交互）
- **Human-only**: 必须真机验证（标注原因），Simulator 阶段仅做结构确认

---

## A. 启动与导航 (3 条)

### QA-A01: 应用启动首屏显示
- **Features**: F2.1, F2.2, F2.9
- **Preconditions**: 首次安装 / 清除数据后启动
- **Steps**:
  1. 在 Simulator 中启动 Enchron
  2. 观察首屏 UI 加载
  3. 检查导航栏结构
- **Expected Results**:
  - Step 1: 应用无崩溃启动，Splash/Launch 过渡完成
  - Step 2: 显示主 UI 面板（Shared Space 模式），包含场景选择区域和文件浏览区域
  - Step 3: 左侧 NavigationStack 导航栏可见，包含数据源列表（至少 "本地文件" 入口）；场景选择面板显示 3 个环境选项（暗黑影院/星空夜景/日落自然）
- **Verification**: Simulator

### QA-A02: 场景选择面板交互
- **Features**: F2.2
- **Preconditions**: 应用已启动，在主面板
- **Steps**:
  1. 点击 "暗黑影院" 场景按钮
  2. 观察 ImmersiveSpace 打开请求
  3. 点击 "星空夜景" 按钮切换
  4. 点击 "日落自然" 按钮切换
- **Expected Results**:
  - Step 1: 按钮视觉反馈（高亮/选中态），触发 ImmersiveSpace 打开流程
  - Step 2: Simulator 中 ImmersiveSpace 打开（若 Simulator 支持）或代码路径确认 openImmersiveSpace 被调用
  - Step 3: 环境切换不退出沉浸空间（switchEnvironment 调用），按钮选中态更新为 "星空夜景"
  - Step 4: 同上，选中态更新为 "日落自然"
- **Verification**: Simulator + Structure（Simulator 沉浸空间渲染受限，需结构确认切换逻辑）

### QA-A03: NavigationStack 文件浏览导航
- **Features**: F2.6, F2.9
- **Preconditions**: 应用已启动，本地文件源可用
- **Steps**:
  1. 在导航栏点击 "本地文件" 数据源
  2. 观察文件列表加载
  3. 点击排序选项切换为 "按大小"
  4. 点击升降序切换
  5. 点击一个子文件夹进入
  6. 点击返回按钮回到上级
- **Expected Results**:
  - Step 1: 右侧面板显示本地文件列表，文件名、大小、日期可见
  - Step 2: 视频文件显示缩略图或图标，非支持格式文件不显示
  - Step 3: 列表重新排序，最大文件排在顶部（降序）或底部（升序）
  - Step 4: 列表顺序翻转
  - Step 5: NavigationStack push 进入子文件夹，导航栏显示路径层级
  - Step 6: NavigationStack pop 回到上级，列表恢复之前的排序状态
- **Verification**: Simulator

---

## B. 文件源管理 (4 条)

### QA-B01: 本地文件浏览与选择
- **Features**: F1.1, F2.8
- **Test Material**: SDR-test.mkv
- **Preconditions**: SDR-test.mkv 存在于 /Users/xiongzhipeng/Movies/
- **Steps**:
  1. 导航到包含 SDR-test.mkv 的目录
  2. 点击 SDR-test.mkv
  3. 观察视频详情页
- **Expected Results**:
  - Step 1: 文件列表中 SDR-test.mkv 可见，显示文件名 + 大小 + 日期
  - Step 2: 跳转到 VideoDetailView，显示视频元数据（分辨率、编码、时长）
  - Step 3: 详情页包含 "播放" 按钮、轨道选择区域（音轨/字幕），DecidePlaybackModeUseCase 自动选择窗口模式（因为是平面 SDR 视频且未进入沉浸空间）
- **Verification**: Simulator

### QA-B02: SMB 数据源添加与浏览
- **Features**: F1.3, F2.5
- **Preconditions**: 无 SMB 服务器配置
- **Steps**:
  1. 在导航栏找到 "添加 SMB" 入口
  2. 点击进入 DataSourceConfigView
  3. 填写服务器地址 (smb://test.local)、用户名、密码
  4. 点击 "连接" / "保存"
- **Expected Results**:
  - Step 1: 菜单中 "Add SMB" 选项可见且可点击
  - Step 2: 配置页面显示地址输入框、用户名输入框、密码输入框（密码为 SecureField）
  - Step 3: 输入字段接受文本输入，无崩溃
  - Step 4: 尝试连接 → 因无真实服务器，应显示连接错误提示（非崩溃）；配置保存到 Keychain（持久化层）
- **Verification**: Simulator（连接失败是预期行为，验证 UI 流程和错误处理）

### QA-B03: WebDAV 数据源添加
- **Features**: F1.4, F2.5
- **Preconditions**: 无 WebDAV 配置
- **Steps**:
  1. 在导航栏找到 "添加 WebDAV" 入口
  2. 进入 DataSourceConfigView
  3. 填写 WebDAV URL + 凭证
  4. 点击连接
- **Expected Results**:
  - Step 1: "Add WebDAV" 选项可见
  - Step 2: 配置页面显示 URL 输入框 + 用户名 + 密码
  - Step 3: 字段可输入
  - Step 4: 连接失败时显示错误提示，不崩溃
- **Verification**: Simulator

### QA-B04: Apple Photos 视频访问
- **Features**: F1.2
- **Preconditions**: Simulator 中有模拟的 Photos 数据（或代码路径验证）
- **Steps**:
  1. 在导航栏找到 Photos/相册 入口
  2. 点击进入
  3. 观察视频列表
- **Expected Results**:
  - Step 1: Photos 数据源入口可见
  - Step 2: 触发 PHPhotoLibrary 权限请求（首次），或显示已授权的视频列表
  - Step 3: 视频列表按创建日期排序，每项显示缩略图 + 时长；点击后通过 PHAsset export 到临时文件，然后进入 VideoDetailView
- **Verification**: Structure + Human-only（Simulator PHPhotoLibrary 行为受限）
- **Human-only reason**: Simulator 无真实 Photos 库数据

---

## C. 窗口模式播放 (5 条)

### QA-C01: SDR MKV 窗口模式完整播放路径
- **Features**: F1.6, F1.9, F3.1, F3.12, F3.13, F1.20
- **Test Material**: SDR-test.mkv
- **Preconditions**: 未进入沉浸空间
- **Steps**:
  1. 导航到 SDR-test.mkv → 点击进入详情页
  2. 点击 "播放" 按钮
  3. 视频开始后，点击暂停按钮
  4. 点击播放恢复
  5. 点击快进 +10s 按钮
  6. 点击快退 -10s 按钮
  7. 等待视频播放至结束（或 seek 到末尾附近）
- **Expected Results**:
  - Step 1: VideoDetailView 显示元数据；HDR 类型标签区域不显示（SDR 内容）；DecidePlaybackModeUseCase 选择 .window 模式
  - Step 2: 视频窗口出现，MTKView 渲染画面，音频输出正常；播放按钮变为暂停图标
  - Step 3: 画面冻结在当前帧，暂停图标变为播放图标
  - Step 4: 画面恢复播放，图标恢复为暂停图标
  - Step 5: 进度条跳跃约 10s，画面对应更新
  - Step 6: 进度条回退约 10s
  - Step 7: 见 QA-I03（播放结束行为）
- **Verification**: Simulator

### QA-C02: HDR10 MP4 窗口模式播放 + HDR 标签
- **Features**: F1.5, F1.10, F1.20, F5.1, F5.3
- **Test Material**: HDR10-test.MP4
- **Preconditions**: 未进入沉浸空间
- **Steps**:
  1. 导航到 HDR10-test.MP4 → 进入详情页
  2. 观察 HDR 标签显示
  3. 点击播放
  4. 观察播放控制栏 HDR 标签
- **Expected Results**:
  - Step 1: VideoDetailView 显示元数据（4K HEVC 等）
  - Step 2: MediaProfile.inferHDRType 检测为 .hdr10，详情页或控制栏显示 "HDR10" 标签
  - Step 3: 视频播放启动，EDRMetadataDescriptor 使用 .pq 色彩曲线；画面色彩呈 HDR 宽色域（Simulator 上 tone-mapped 显示）
  - Step 4: 播放控制栏显示 "HDR10" 文字标签，非 HDR 内容时此标签不出现
- **Verification**: Simulator + Structure（Simulator 上 HDR 显示受限，需结构确认 EDR pipeline）

### QA-C03: Dolby Vision 播放 + HDR10 兼容回退
- **Features**: F1.12, F5.3
- **Test Material**: dolby-vision-test.mp4
- **Preconditions**: 未进入沉浸空间
- **Steps**:
  1. 导航到 dolby-vision-test.mp4 → 进入详情页
  2. 观察 HDR 类型检测结果
  3. 播放视频
- **Expected Results**:
  - Step 1: 详情页显示 HEVC 编码 + DV 相关信息
  - Step 2: inferHDRType 检测为 .dolbyVision，标签显示 "DOLBY VISION"；由于 Apple 无公开 DoVI EDR API，内部降级为 HDR10 兼容模式渲染
  - Step 3: 视频正常播放，hwdec=videotoolbox 硬件解码生效，无崩溃；画面颜色应为 HDR 色域（tone-mapped on Simulator）
- **Verification**: Simulator + Structure

### QA-C04: MOV 容器格式播放
- **Features**: F1.7
- **Test Material**: SDR-test-sample.mov
- **Preconditions**: 未进入沉浸空间
- **Steps**:
  1. 导航到 SDR-test-sample.mov → 播放
  2. 观察是否正常解码
- **Expected Results**:
  - Step 1: 文件在文件列表中可见（FileFilter 接受 .mov 后缀）
  - Step 2: 视频正常播放（HEVC 解码），画面渲染正确，音频正常；无格式识别错误
- **Verification**: Simulator

### QA-C05: AVI 容器格式播放
- **Features**: F1.8
- **Test Material**: SDR-test-sample.avi
- **Preconditions**: 未进入沉浸空间
- **Steps**:
  1. 导航到 SDR-test-sample.avi → 播放
  2. 观察解码和渲染
- **Expected Results**:
  - Step 1: 文件在文件列表中可见（FileFilter 接受 .avi）
  - Step 2: 视频正常播放（H.264 解码），画面清晰无花屏，音频同步
- **Verification**: Simulator

---

## D. 沉浸影院模式 (5 条)

### QA-D01: 进入沉浸空间并播放视频
- **Features**: F3.2, F6.1, F6.7
- **Test Material**: SDR-test.mkv
- **Preconditions**: 应用在 Shared Space 模式
- **Steps**:
  1. 在场景选择面板点击 "暗黑影院"
  2. 等待 ImmersiveSpace 打开
  3. 导航选择 SDR-test.mkv → 播放
  4. 观察视频在虚拟屏幕上渲染
- **Expected Results**:
  - Step 1: openImmersiveSpace 调用触发，.immersionStyle 为预设值（.full 或 .mixed）
  - Step 2: ImmersiveSpace 打开成功；EnvironmentDomeEntity 加载暗黑影院环境。**已知缺陷 F6.1-F6.3**: 环境为纯色 UnlitMaterial（白 0.02），非 Skybox 纹理，视觉效果低于设计目标。CinemaEnvironment.skyboxAssetName 定义了纹理名但从未加载
  - Step 3: DecidePlaybackModeUseCase 检测到已在沉浸空间 → 选择 .immersive 模式；VirtualScreenEntity 实例化
  - Step 4: 视频帧通过 Metal 纹理桥接渲染到虚拟屏幕上；屏幕位置为默认值（distance/height/angle 初始值）。**已知缺陷 F3.2 (P0)**: `PanoramaLayerBridge.attachVideoLayer()` 仅在 `.panorama` 模式调用，`.immersive` 模式未接入 bridge，虚拟屏幕 textureResource 为 nil — **预期 FAIL（无视频画面）**
- **Verification**: Simulator + Structure（Simulator 沉浸空间渲染效果受限）

### QA-D02: 虚拟屏幕距离和高度调节
- **Features**: F3.18, F3.19
- **Preconditions**: 已在沉浸空间中播放视频
- **Steps**:
  1. 找到屏幕位置控制面板（Ornament 或 Settings 子面板）
  2. 调节 "远近距离" slider（向远端拖动）
  3. 调节 "垂直高度" slider（向上拖动）
  4. 退出播放，重新进入播放
- **Expected Results**:
  - Step 1: 控制面板中包含 distance slider 和 verticalOffset slider，各有标签和当前数值显示
  - Step 2: VirtualScreenEntity 的 z 轴位置远离用户（数值增大），slider 值在 clamping 范围内（如 2m~20m）
  - Step 3: VirtualScreenEntity 的 y 轴位置上移，slider 值在 clamping 范围内
  - Step 4: 重新播放后，屏幕位置恢复到 Step 2/3 设置的值（ScreenPositionStoring 持久化生效，v2 R7 修复验证）
- **Verification**: Structure + Human-only（slider 交互在 Simulator 上需键盘模拟）
- **Human-only reason**: 精确的空间位置视觉确认需真机

### QA-D03: X 轴视角旋转（躺姿适配）
- **Features**: F3.17
- **Preconditions**: 已在沉浸空间中播放视频
- **Steps**:
  1. 找到 viewAngle 控件
  2. 旋转到约 45° 角
  3. 观察虚拟屏幕倾斜
- **Expected Results**:
  - Step 1: 屏幕位置控制面板中 viewAngle slider 或旋转控件可见
  - Step 2: slider 值更新为约 45°
  - Step 3: VirtualScreenEntity 绕 X 轴旋转，画面向上倾斜（适配仰卧姿势）
- **Verification**: Structure + Human-only
- **Human-only reason**: 空间旋转视觉效果需真机

### QA-D04: 环境切换（不退出沉浸空间）
- **Features**: F6.4, F6.1, F6.2, F6.3
- **Preconditions**: 已在沉浸空间 "暗黑影院" 中
- **Steps**:
  1. 不退出沉浸空间，切换到 "星空夜景"
  2. 切换到 "日落自然"
  3. 切换回 "暗黑影院"
- **Expected Results**:
  - Step 1: switchEnvironment(to: .starryNight) 调用成功；EnvironmentDomeEntity 材质颜色变化（深蓝色）；**不触发** dismissImmersiveSpace / openImmersiveSpace 循环。**已知缺陷 F6.1-F6.3**: 所有环境均为纯色 UnlitMaterial，非 Skybox 纹理
  - Step 2: 材质变为暗棕色（日落）；虚拟屏幕位置不变（屏幕位置独立于环境）—— 但 per-environment 位置记忆意味着位置**可能**变化（看 F3.20 设计）
  - Step 3: 恢复白色 0.02（暗黑影院）；如果 F3.20 per-env 记忆生效，屏幕位置应恢复到 "暗黑影院" 环境的上次保存值
- **Verification**: Structure（Simulator 上颜色变化可能不可见，需代码路径确认）

### QA-D05: 虚拟屏幕平面/曲面切换
- **Features**: F6.5, F6.6
- **Preconditions**: 已在沉浸空间中播放视频
- **Steps**:
  1. 打开 Settings 或屏幕形状切换控件
  2. 切换屏幕形状为 "曲面"
  3. 观察虚拟屏幕几何体变化
  4. 退出应用重启
  5. 重新进入沉浸空间播放
- **Expected Results**:
  - Step 1: SettingsView 或控制面板中有 screenShape 切换（flat/curved）
  - Step 2: VirtualScreenEntity mesh 从 flat 变为 curved；UI 反馈选中态为 "曲面"
  - Step 3: 渲染画面在曲面上弯曲显示（Simulator 上可能需结构确认）
  - Step 4-5: **已知缺陷 F6.6**：当前 AppModel.screenShape 不持久化，重启后恢复默认 flat。此项预期 FAIL
- **Verification**: Structure（F6.6 已知 FAIL）

---

## E. 全景模式 (5 条)

### QA-E01: 360° 全景视频播放
- **Features**: F1.17, F3.3, F1.21
- **Test Material**: 360-test-nasa-wind-tunnel.webm
- **Preconditions**: 应用已启动
- **Steps**:
  1. 导航选择 360-test-nasa-wind-tunnel.webm
  2. 观察投影类型自动检测
  3. 播放视频
  4. 观察全景渲染
- **Expected Results**:
  - Step 1: 文件可见且可选择
  - Step 2: ProjectionDetection 检测为 equirectangular/360° 投影；DecidePlaybackModeUseCase 选择 .panorama 模式
  - Step 3: 自动触发 openImmersiveSpace（全景模式），**不加载虚拟场景**（节省性能，Requirements 2.3 规定）
  - Step 4: PanoramaSphereEntity 全球体渲染，用户被视频包裹；可通过头部转动查看不同方向（Simulator 上通过鼠标/键盘模拟）
- **Verification**: Simulator + Structure

### QA-E02: 180° VR 视频播放
- **Features**: F1.18, F3.3
- **Test Material**: 180-vr-test.mp4
- **Preconditions**: 应用已启动
- **Steps**:
  1. 导航选择 180-vr-test.mp4
  2. 观察投影类型检测
  3. 播放并观察渲染范围
- **Expected Results**:
  - Step 1: 文件可见可选择
  - Step 2: ProjectionDetection 检测为 180° VR 投影；如果 FOV 消歧生效（F1.21 已知缺陷：hardcoded nil 默认 360°），应识别为 180°。**已知缺陷**：可能误判为 360°
  - Step 3: 若正确识别 180°：PanoramaSphereEntity 使用半球体 mesh（UV [0.25, 0.75]），前方半球有画面，后方无画面。若误判 360°：**FAIL — F1.21 bug active**，180° 内容需要正确的半球体投影，全球体渲染导致画面严重拉伸变形，用户体验不可接受
- **Verification**: Simulator + Structure

### QA-E03: 鱼眼投影视频播放
- **Features**: F1.19, F3.3
- **Test Material**: fisheye-test.mp4
- **Preconditions**: 应用已启动
- **Steps**:
  1. 导航选择 fisheye-test.mp4
  2. 观察投影类型检测
  3. 播放并观察渲染
- **Expected Results**:
  - Step 1: 文件可见可选择
  - Step 2: ProjectionDetection 检测到 fisheye 投影类型（基于分辨率 1920x1920 正方形 + v360 元数据）
  - Step 3: Metal compute shader fisheye_remap（VideoShaders.metal:59）被调用确认（结构路径验证：shader 函数存在 + 投影类型为 fisheye 时被 dispatch）；视觉质量评估 deferred to Human-only 真机验证
- **Verification**: Structure + Human-only（shader 调用链为结构验证，校正视觉质量需人眼确认）
- **Human-only reason**: 鱼眼校正的视觉效果（畸变程度、接缝连续性）超出 Simulator 截图和结构验证能力

### QA-E04: 投影类型手动覆盖
- **Features**: F1.22
- **Test Material**: SDR-test.mkv (平面视频)
- **Preconditions**: SDR-test.mkv 正在窗口模式播放
- **Steps**:
  1. 打开播放控制菜单中的 "投影覆盖" 选项
  2. 选择 "360° 全景"
  3. 观察模式切换
  4. 恢复为 "自动检测"
- **Expected Results**:
  - Step 1: PlaybackMenuView 或设置面板中有投影类型下拉/选择器，列出自动/窗口/360°/180°/SBS/OU/鱼眼
  - Step 2: effectiveProjectionType 覆盖为 .equirectangular360；触发播放模式重新评估
  - Step 3: 自动触发 ImmersiveSpace → 全景模式；SDR 平面视频被强制贴到球体上（画面变形是预期的，因为内容不是全景）
  - Step 4: 恢复自动检测 → ProjectionDetection 重新识别为平面 → 退出全景模式 → 回到窗口模式
- **Verification**: Simulator + Structure

### QA-E05: 全景模式下无虚拟场景
- **Features**: F3.3 (Requirements 2.3 规定)
- **Test Material**: 360-test-nasa-wind-tunnel.webm
- **Preconditions**: 已在某个虚拟场景（如暗黑影院）的沉浸空间中
- **Steps**:
  1. 在沉浸空间中导航选择 360° 视频
  2. 观察模式切换
- **Expected Results**:
  - Step 1: 选择 360° 视频后，DecidePlaybackModeUseCase 选择 .panorama
  - Step 2: 模式从 .immersive（虚拟屏幕）切换到 .panorama（全景球体）；EnvironmentDomeEntity 被移除或隐藏（全景模式不加载虚拟场景）；VirtualScreenEntity 被移除，PanoramaSphereEntity 出现
- **Verification**: Structure

### QA-E06: 沉浸空间中投影覆盖（对抗性审查新增）
- **Features**: F1.22, F3.4
- **Test Material**: SDR-test.mkv (平面视频)
- **Preconditions**: 已在沉浸空间中播放 SDR-test.mkv（.immersive 模式，VirtualScreenEntity 可见）
- **Steps**:
  1. 在沉浸空间播放界面打开投影覆盖选项
  2. 选择 "360° 全景"
  3. 观察模式从 .immersive 切换到 .panorama
  4. 选择 "自动检测" 恢复
  5. 观察模式从 .panorama 切换回 .immersive
- **Expected Results**:
  - Step 1: PlaybackMenuView 投影类型选择器可用（沉浸空间中不禁用）
  - Step 2: effectiveProjectionType 覆盖为 .equirectangular360
  - Step 3: DecidePlaybackModeUseCase 重新评估 → .panorama；VirtualScreenEntity + EnvironmentDomeEntity 被移除/隐藏；PanoramaSphereEntity 创建并渲染（画面变形是预期，因内容非全景）；ImmersiveSpace 不退出重进（空间内模式切换）
  - Step 4: ProjectionDetection 重新识别为 flat → .immersive 模式
  - Step 5: PanoramaSphereEntity 移除；VirtualScreenEntity + EnvironmentDomeEntity 恢复；无残留 entity；播放位置不中断
- **Verification**: Structure + Simulator
- **新增原因**: 对抗性审查 Challenge 6 — 补充从沉浸模式起点的投影覆盖路径（v2 R14 修复验证）

---

## F. 3D 立体视频 (3 条)

### QA-F01: SBS 左右格式 3D 立体视频
- **Features**: F1.15
- **Test Material**: SBS-stereo3d-test.mp4
- **Preconditions**: 应用已启动
- **Steps**:
  1. 导航选择 SBS-stereo3d-test.mp4
  2. 观察投影类型检测
  3. 播放视频
  4. 观察渲染模式
- **Expected Results**:
  - Step 1: 文件可见可选择（3840x1080 分辨率，约 2:1 宽高比提示 SBS）
  - Step 2: ProjectionDetection 检测为 SBS（基于分辨率宽高比 + 元数据）；stereoCropMode 设置为 leftEye 或类似值
  - Step 3: 播放启动，DecidePlaybackModeUseCase 判断 SBS → 选择 .window 或 .immersive（取决于当前空间状态）
  - Step 4: **已知限制**：当前实现为左眼单目裁剪（非真正立体渲染）。预期画面为左半部分内容，画幅正常（不是 2:1 拉伸）。右半部分不显示
- **Verification**: Simulator + Structure

### QA-F02: OU 上下格式 3D 立体视频
- **Features**: F1.16
- **Test Material**: OU-stereo3d-test.mp4
- **Preconditions**: 应用已启动
- **Steps**:
  1. 导航选择 OU-stereo3d-test.mp4
  2. 观察检测
  3. 播放
- **Expected Results**:
  - Step 1: 文件可见可选择（1920x2160 分辨率，约 1:1.125 高宽比提示 OU）
  - Step 2: ProjectionDetection 检测为 OU（基于分辨率 + 元数据）；stereoCropMode 设置
  - Step 3: 播放启动，画面为上半部分内容（左眼），画幅正常（16:9）。下半部分不显示。**同 SBS，当前为单目裁剪**
- **Verification**: Simulator + Structure

### QA-F03: SBS 视频在沉浸空间中的虚拟屏幕播放
- **Features**: F1.15, F3.2
- **Test Material**: SBS-stereo3d-test.mp4
- **Preconditions**: 已在沉浸空间中（暗黑影院）
- **Steps**:
  1. 在沉浸空间中选择 SBS-stereo3d-test.mp4 → 播放
  2. 观察渲染到虚拟屏幕
- **Expected Results**:
  - Step 1: DecidePlaybackModeUseCase 检测 SBS + 已在沉浸空间 → 选择 .immersive 模式
  - Step 2: VirtualScreenEntity 上渲染左眼裁剪后的画面；Metal 纹理桥接正常工作；画面不拉伸。**已知缺陷 F3.2 (P0)**: 同 QA-D01，`.immersive` 模式 bridge 未接入 — **预期 FAIL（虚拟屏幕无画面）**
- **Verification**: Structure

---

## G. 播放控件 (7 条)

### QA-G01: 可变播放速度
- **Features**: F3.14
- **Test Material**: SDR-test.mkv
- **Preconditions**: 视频正在播放
- **Steps**:
  1. 打开播放速度菜单
  2. 选择 0.5x
  3. 选择 2.0x
  4. 选择 5.0x
  5. 恢复 1.0x
- **Expected Results**:
  - Step 1: 速度菜单显示 PlaybackSpeed.allCases：0.25x, 0.50x, 0.75x, 1x, 1.25x, 1.50x, 1.75x, 2.0x, 3.0x, 5.0x
  - Step 2: 音频降速（pitch 变低），进度条推进速度减半；UI 显示当前速度 "0.5x"
  - Step 3: 音频加速，进度条推进速度加倍；UI 显示 "2.0x"
  - Step 4: 进度条快速推进，音频可能静音（取决于 mpv 配置）；UI 显示 "5.0x"
  - Step 5: 恢复正常播放；UI 不再显示速度标签（或显示 "1.0x"）
- **Verification**: Simulator

### QA-G02: 音轨选择
- **Features**: F3.15
- **Test Material**: SDR-test.mkv（需确认是否含多音轨）
- **Preconditions**: 视频正在播放
- **Steps**:
  1. 打开 PlaybackMenuView 音轨面板
  2. 查看可用音轨列表
  3. 若有多音轨，切换到非默认音轨
- **Expected Results**:
  - Step 1: 音轨面板可见，列出当前视频的所有音频轨道（至少 1 个）
  - Step 2: 每个音轨显示：轨道 ID、语言（如有）、编码格式
  - Step 3: 切换后音频输出变化（若多轨不同内容），mpv aid 属性更新
- **Verification**: Simulator（若素材含多音轨）/ Structure（若单音轨则验证 UI 展示）

### QA-G03: 字幕选择与 CJK 渲染
- **Features**: F3.16, F5.4
- **Test Material**: SDR-test.mkv（需确认是否含字幕轨）
- **Preconditions**: 视频正在播放
- **Steps**:
  1. 打开字幕面板
  2. 查看可用字幕轨列表
  3. 选择一个字幕轨
  4. 观察字幕渲染
- **Expected Results**:
  - Step 1: 字幕面板可见，列出字幕轨道 + "关闭" 选项
  - Step 2: 每个字幕轨显示：语言、格式（SRT/ASS 等）
  - Step 3: 选择后 mpv sid 属性更新
  - Step 4: 字幕文字出现在视频画面上；blend-subtitles=yes 生效（GPU 合成）；若含 CJK 字符，Noto Sans SC 字体正确渲染（无豆腐块）；ASS 特效（颜色/位置/动画）保留
- **Verification**: Simulator + Human-only（CJK 渲染和 ASS 特效需视觉确认）
- **Human-only reason**: 字体渲染质量和特效完整性需人眼评估

### QA-G04: 二级时间轴 / 精细 Scrubber
- **Features**: F3.10
- **Test Material**: SDR-test.mkv
- **Preconditions**: 视频正在播放，标准控制栏可见
- **Steps**:
  1. 点击进度条区域
  2. 观察 UI 切换到二级进度条模式
  3. 左右滑动时间轴
  4. 点击视频画面空白区域
- **Expected Results**:
  - Step 1: 触发模式切换
  - Step 2: 标准播放控件隐藏，DetailedTimeline 出现；时间轴展示更精细的时间刻度；固定中心指针显示当前播放位置
  - Step 3: 时间轴可左右平移，播放位置随之变化；时间精度更高（秒级或帧级）
  - Step 4: 退出二级进度条模式；所有播放器 UI 隐藏（全屏呈现视频）
- **已知缺陷 F3.10 (P2)**: DetailedTimelineGeometry 计算模型完整（196行），但**无任何 SwiftUI View 消费它**。DetailedTimelineView 不存在 — **预期 FAIL（二级时间轴无法触发）**
- **Verification**: Structure（已知 FAIL）

### QA-G05: 逐帧步进
- **Features**: F3.21
- **Test Material**: SDR-test.mkv
- **Preconditions**: 视频已暂停
- **Steps**:
  1. 点击 "前进一帧" 按钮
  2. 观察画面变化
  3. 点击 "后退一帧" 按钮
  4. 观察画面变化
- **Expected Results**:
  - Step 1: 前进一帧按钮可见且可点击
  - Step 2: 画面精确前进一帧（进度条时间微增，约 1/fps 秒）
  - Step 3: 后退一帧按钮可见且可点击
  - Step 4: 画面精确后退一帧（进度条时间微减）
- **Verification**: Simulator

### QA-G06: 选集 / 当前文件夹视频列表
- **Features**: F3.11
- **Test Material**: /Users/xiongzhipeng/Movies/ 下多个视频
- **Preconditions**: 正在播放 SDR-test.mkv
- **Steps**:
  1. 在播放界面打开 "选集" / PlaylistMenuView
  2. 观察视频列表
  3. 选择另一个视频（如 HDR10-test.MP4）
- **Expected Results**:
  - Step 1: PlaylistMenuView 可见，展示当前文件夹下所有视频文件
  - Step 2: 列表包含 Movies 目录下所有可播放视频（12 个测试素材），当前播放的 SDR-test.mkv 有高亮标记
  - Step 3: 当前视频停止，HDR10-test.MP4 开始播放；无需退出播放界面回到文件浏览
- **Verification**: Simulator

### QA-G07: 播放进度条拖拽 Seek
- **Features**: F3.12 (进度条基础交互)
- **Test Material**: SDR-test.mkv
- **Preconditions**: 视频正在播放
- **Steps**:
  1. 拖拽进度条到视频 50% 位置
  2. 观察画面跳转
  3. 拖拽到视频开头附近
- **Expected Results**:
  - Step 1: 进度条响应拖拽，显示预览时间标签
  - Step 2: 松手后视频 seek 到约 50% 位置，画面更新，音频同步
  - Step 3: 视频回到开头附近位置
- **Verification**: Simulator

---

## H. 手势交互 (4 条)

> **注意**: visionOS 手势在 Simulator 上行为受限。以下路径以结构验证为主，
> 确认代码接线完整。真实手势交互需 Human-only 验证。

### QA-H01: 单次捏合 → 召唤主菜单
- **Features**: F3.5, F3.6
- **Preconditions**: 视频正在沉浸空间中播放，UI 已隐藏
- **Steps**:
  1. 执行单次捏合手势（Simulator: 空格键 + 点击）
  2. 等待 200ms 消歧窗口
  3. 观察 UI 响应
- **Expected Results**:
  - Step 1: 手势事件进入 DisambiguateGestureUseCase
  - Step 2: 200ms 内无第二次捏合、无持续保持 → 识别为 singlePinch
  - Step 3: PlayerControlSurface 接收到 singlePinch 事件 → 主菜单/播放控件显示（showControls = true）
- **Verification**: Structure + Human-only
- **Human-only reason**: Simulator 的手势模拟不完全等同 visionOS 捏合

### QA-H02: 快速双次捏合 → 播放/暂停
- **Features**: F3.5, F3.7
- **Preconditions**: 视频正在播放
- **Steps**:
  1. 快速执行两次捏合（间隔 < 200ms）
  2. 观察播放状态变化
  3. 再次双击
- **Expected Results**:
  - Step 1: DisambiguateGestureUseCase 识别为 doublePinch
  - Step 2: 播放 → 暂停（图标变化，画面冻结）
  - Step 3: 暂停 → 恢复播放
- **Verification**: Structure + Human-only
- **Human-only reason**: 200ms 消歧窗口精度需真实手势

### QA-H03: 捏合长按 → 2.0x 倍速
- **Features**: F3.5, F3.8
- **Preconditions**: 视频正在 1.0x 播放
- **Steps**:
  1. 执行捏合并保持 > 200ms
  2. 观察播放速度变化
  3. 松开手势
- **Expected Results**:
  - Step 1: DisambiguateGestureUseCase 识别为 longPress（longPressThreshold = 0.2s）
  - Step 2: 播放速度切换到 2.0x（mpv speed 属性 = 2.0），UI 可能显示 "2.0x" 临时提示
  - Step 3: 松开后速度恢复 1.0x
- **Verification**: Structure + Human-only
- **Human-only reason**: 长按时长判断需真实手势

### QA-H04: 捏合拖拽 → 进度条拖拽
- **Features**: F3.5, F3.9
- **Preconditions**: 视频正在播放
- **Steps**:
  1. 捏合后向右拖拽 > 8pt
  2. 观察进度变化
  3. 释放
- **Expected Results**:
  - Step 1: DisambiguateGestureUseCase 识别为 drag（dragDistanceThreshold = 8pt）
  - Step 2: 视频进度随拖拽方向实时变化（向右 = 快进，向左 = 快退）
  - Step 3: 释放后从当前位置继续播放
- **已知缺陷 F3.9 (P1)**: MainView.swift:136 对 `.drag` case 执行 `break`（空操作），手势检测到但未接线到进度条 — **预期 FAIL（拖拽无效果）**
- **Verification**: Structure + Human-only（已知 FAIL）
- **Human-only reason**: 拖拽距离计算需真实手势

---

## I. 状态管理 (5 条)

### QA-I01: 播放进度记忆与恢复弹窗
- **Features**: F4.4, F4.5
- **Test Material**: SDR-test.mkv
- **Preconditions**: 首次播放
- **Steps**:
  1. 播放 SDR-test.mkv，推进到约 50% 位置
  2. 停止播放（退出到文件浏览）
  3. 再次选择 SDR-test.mkv 进入详情页
  4. 观察恢复播放选项
- **Expected Results**:
  - Step 1: 正常播放
  - Step 2: PlaybackLaunchCoordinator persist-on-teardown 将进度写入 SwiftDataStore
  - Step 3: VideoDetailView 检测到已有播放记录
  - Step 4: 显示 "从上次位置继续" 恢复按钮（ResumePolicy 生效），按钮显示上次进度时间；点击后从 50% 位置恢复播放（非从头开始）
- **Verification**: Simulator

### QA-I02: "记住我的选择" 设置
- **Features**: F4.6
- **Preconditions**: 恢复弹窗正在显示
- **Steps**:
  1. 进入 Settings → 找到 resume behavior 设置
  2. 切换为 "总是从上次位置继续"（跳过弹窗）
  3. 退出播放后重新选择同一视频
- **Expected Results**:
  - Step 1: SettingsView 中有 resume behavior 下拉菜单，选项包括 "每次询问" / "总是继续" / "总是从头"
  - Step 2: UserDefaultsStore 保存偏好
  - Step 3: 直接从上次位置恢复播放，无弹窗
- **Verification**: Simulator

### QA-I03: 播放结束行为（停留最后帧 + 重播图标）
- **Features**: F4.9
- **Test Material**: SDR-test.mkv
- **Preconditions**: 视频正在播放
- **Steps**:
  1. Seek 到视频末尾附近
  2. 等待视频播放完成
  3. 观察结束状态
  4. 点击重播图标
- **Expected Results**:
  - Step 1: Seek 成功
  - Step 2: mpv keep-open 生效，画面停留在最后一帧
  - Step 3: 播放控制栏自动显示；播放按钮变为重播图标（循环箭头）；进度条显示 100%
  - Step 4: 从头开始重新播放（seek 到 0:00）
- **Verification**: Simulator

### QA-I04: 自动下一集
- **Features**: F4.10
- **Test Material**: SDR-test.mkv → HDR10-test.MP4（按文件名排序的下一个）
- **Preconditions**: playbackEndBehavior 设置为 playNext
- **Steps**:
  1. 在 Settings 中设置播放结束行为为 "自动下一个"
  2. 播放 SDR-test.mkv
  3. Seek 到末尾，等待播放完成
  4. 观察自动切换
- **Expected Results**:
  - Step 1: SettingsView playbackEndBehavior 选择 "playNext"
  - Step 2: 正常播放
  - Step 3: 视频播放完毕
  - Step 4: nextFileProvider 自动取得文件夹中按名称排序的下一个视频文件，新视频自动开始播放；播放界面无需用户操作即更新为新视频信息
- **Verification**: Simulator

### QA-I05: 文件列表播放进度提示
- **Features**: F2.7, F4.7
- **Test Material**: SDR-test.mkv（已有播放记录）
- **Preconditions**: SDR-test.mkv 已播放到约 50% 后退出
- **Steps**:
  1. 导航到包含 SDR-test.mkv 的文件列表
  2. 观察文件条目下方的进度提示
- **Expected Results**:
  - Step 1: 文件列表正常加载
  - Step 2: SDR-test.mkv 条目下方显示播放进度提示（如 "已观看 50%" 或进度条）；SwiftDataStore 中的进度数据已查询并展示在 UI 上。**已知缺陷 F4.7**：文件列表 UI 可能未实现进度条显示
- **Verification**: Simulator（预期可能 FAIL）

---

## J. 错误处理 (3 条)

### QA-J01: 网络缓冲动画
- **Features**: F4.1
- **Preconditions**: 正在播放网络流视频（或模拟缓冲状态）
- **Steps**:
  1. 检查代码中是否存在 buffering 状态监听
  2. 检查 UI 中是否有 ProgressView / 转圈动画组件
  3. 模拟 mpv 进入 buffering 状态
- **Expected Results**:
  - Step 1: PlaybackEvent 或 PlaybackState 应有 .buffering 状态枚举
  - Step 2: PlayerControlsView 或 overlay 层应有 ProgressView（系统转圈）与 buffering 状态绑定
  - Step 3: 当 buffering = true 时，转圈动画显示在视频中央
  - **已知缺陷 F4.1**：预期 FAIL — 无缓冲指示器实现
- **Verification**: Structure（网络缓冲需真实网络环境触发）
- **Phase 2 升级注释**: F4.1 实现后，本路径应升级为运行时 E2E（含网络故障注入：throttle/drop/restore），验证 UI 状态转换时序

### QA-J02: 网络断开错误提示
- **Features**: F4.2
- **Preconditions**: 正在播放网络视频
- **Steps**:
  1. 检查 PlaybackEvent.failed(.runtime) 的 UI 处理代码
  2. 确认错误提示 Alert/Toast 实现
  3. 确认是否有 "重试" 按钮
- **Expected Results**:
  - Step 1: 存在 PlaybackEvent.failed case 的 View 处理逻辑
  - Step 2: 错误发生时弹出提示框，显示错误信息（非空白或崩溃）
  - Step 3: **已知缺陷 F4.2**：有错误提示但无 "重试" 按钮。用户需手动退出并重新播放
- **Verification**: Structure

### QA-J03: 后台静默重连
- **Features**: F4.3
- **Preconditions**: 网络视频播放中断
- **Steps**:
  1. 检查代码中是否存在网络恢复监听
  2. 检查是否有自动重连/重试逻辑
  3. 检查是否有重连状态 UI 反馈
- **Expected Results**:
  - Step 1: 应有 Network reachability 监听 + 恢复时自动 reload
  - Step 2: 应有 retry with backoff 逻辑
  - Step 3: 应有 "正在重连..." 状态提示
  - **已知缺陷 F4.3**：预期全部 FAIL — 无自动重连逻辑
- **Verification**: Structure
- **Phase 2 升级注释**: F4.3 实现后，本路径应升级为运行时 E2E（含网络恢复场景），验证 retry backoff + 恢复后播放连续性

---

## K. HDR / 色彩管理 (4 条)

### QA-K01: HLG 色彩空间检测与播放
- **Features**: F1.13
- **Test Material**: HLG-test.mp4
- **Preconditions**: 应用已启动
- **Steps**:
  1. 导航选择 HLG-test.mp4 → 进入详情页
  2. 观察 HDR 类型检测
  3. 播放视频
- **Expected Results**:
  - Step 1: 文件可见可选择
  - Step 2: inferHDRType 检测到 transfer=arib-std-b67 → 识别为 .hlg；详情页/控制栏显示 "HLG" 标签
  - Step 3: 视频正常播放，HLG 色彩管线生效（EDRMetadataDescriptor 使用 HLG 曲线）；Simulator 上画面为 tone-mapped SDR 显示
- **Verification**: Simulator + Structure

### QA-K02: HDR10+ 色彩空间检测与播放
- **Features**: F1.11
- **Test Material**: HDR10plus-test.mp4
- **Preconditions**: 应用已启动
- **Steps**:
  1. 导航选择 HDR10plus-test.mp4 → 进入详情页
  2. 观察 HDR 类型检测
  3. 播放视频
- **Expected Results**:
  - Step 1: 文件可见可选择
  - Step 2: inferHDRType 检测到 transfer=smpte2084 + mastering display metadata → 识别为 .hdr10Plus 或至少 .hdr10（因素材使用静态 MDM 近似真 HDR10+）
  - Step 3: 视频正常播放，HDR 管线生效
- **Verification**: Simulator + Structure

### QA-K03: HDR/SDR 实时切换按钮
- **Features**: F5.2
- **Test Material**: HDR10-test.MP4
- **Preconditions**: HDR 视频正在播放
- **Steps**:
  1. 在播放控制栏查找 HDR/SDR 切换按钮
  2. 点击切换到 SDR 模式
  3. 观察色彩变化
  4. 切换回 HDR 模式
- **Expected Results**:
  - Step 1: 控制栏中应有 HDR/SDR toggle 按钮（仅在 HDR 内容时显示）
  - Step 2: 切换到 SDR → mpv 执行 tone-mapping 到 sRGB/BT.709
  - Step 3: 画面色彩范围收窄，高光细节压缩
  - Step 4: 恢复 HDR 直通，画面恢复宽色域
  - **已知缺陷 F5.2**：预期 FAIL — 未找到实时切换 toggle 实现
- **Verification**: Structure

### QA-K04: SDR 视频无 HDR 标签
- **Features**: F5.1 (反面验证)
- **Test Material**: SDR-test.mkv
- **Preconditions**: SDR 视频正在播放
- **Steps**:
  1. 在播放控制栏查找 HDR 标签
  2. 在详情页查找 HDR 标签
- **Expected Results**:
  - Step 1: 播放控制栏不显示任何 HDR 标签（HDR10/DOLBY VISION/HLG 均不出现）
  - Step 2: 详情页不显示 HDR 标签；HDR/SDR 切换按钮不显示（非 HDR 内容时隐藏）
- **Verification**: Simulator

---

## L. 设置与偏好 (4 条)

### QA-L01: 恢复播放策略设置持久化
- **Features**: F7.1
- **Preconditions**: 应用已启动
- **Steps**:
  1. 打开 Settings
  2. 修改 "恢复播放策略" 为 "总是从头播放"
  3. 退出 Settings
  4. 重新打开 Settings
- **Expected Results**:
  - Step 1: Settings 页面正常打开
  - Step 2: 下拉菜单切换成功，UserDefaultsStore 写入偏好
  - Step 3: 返回主界面
  - Step 4: "恢复播放策略" 仍显示为 "总是从头播放"（持久化验证）
- **Verification**: Simulator

### QA-L02: 播放结束行为设置持久化
- **Features**: F7.2
- **Preconditions**: 应用已启动
- **Steps**:
  1. 打开 Settings
  2. 修改 "播放结束行为" 为 "自动重播"
  3. 关闭重开 Settings
- **Expected Results**:
  - Step 1: Settings 页面显示
  - Step 2: 选择 "repeat"，UserDefaultsStore 写入
  - Step 3: 设置保持为 "自动重播"
- **Verification**: Simulator

### QA-L03: 默认播放速度设置
- **Features**: F7.3
- **Preconditions**: 应用已启动
- **Steps**:
  1. 打开 Settings
  2. 将默认播放速度 slider 调到 1.5x
  3. 退出 Settings
  4. 播放一个视频
- **Expected Results**:
  - Step 1: Settings 显示
  - Step 2: slider 值更新为 1.5x，UserDefaultsStore 写入
  - Step 3: 返回主界面
  - Step 4: 新视频启动后默认以 1.5x 速度播放（UI 显示 "1.5x"）
- **Verification**: Simulator

### QA-L04: 已连接服务器管理与删除
- **Features**: F7.4
- **Preconditions**: 有已保存的 SMB/WebDAV 配置
- **Steps**:
  1. 在文件浏览导航栏查看已保存的数据源
  2. 长按/右键或找到删除选项
  3. 删除一个已保存的服务器配置
  4. 确认列表更新
- **Expected Results**:
  - Step 1: 已保存的 SMB/WebDAV 配置显示为 chip/按钮在导航栏
  - Step 2: 删除选项可见（swipe-to-delete 或 context menu）
  - Step 3: 确认删除后，配置从 Keychain/持久化层移除
  - Step 4: 导航栏不再显示已删除的服务器
- **Verification**: Simulator

### QA-L05: 远程缓存清理 UI 检查（对抗性审查新增）
- **Features**: F7.5
- **Preconditions**: 应用已启动
- **Steps**:
  1. 打开 Settings
  2. 搜索缓存清理相关 UI（"清除缓存"、"Clear Cache" 等）
  3. 检查 FileBrowsing 模块中是否有远程流缓存管理入口
- **Expected Results**:
  - Step 1: Settings 页面正常打开
  - Step 2: 应有一个显式的远程缓存清理按钮/选项
  - Step 3: 点击后执行清理操作，显示成功提示
  - **已知缺陷 F7.5**: 预期 FAIL — 未找到显式的远程流缓存清理 UI
- **Verification**: Structure（代码审计 SettingsView 和 FileBrowsing）

### QA-L06: 关于页面检查（对抗性审查新增）
- **Features**: F7.6
- **Preconditions**: 应用已启动
- **Steps**:
  1. 打开 Settings
  2. 搜索 "关于" / "About" / 版本信息入口
  3. 检查是否有应用版本号、构建号显示
- **Expected Results**:
  - Step 1: Settings 页面正常打开
  - Step 2: 应有 "关于" 或 "About" 导航项
  - Step 3: 显示应用名称、版本号 (Bundle.main.infoDictionary)、构建号
  - **已知缺陷 F7.6**: 预期 FAIL — 未找到 About 页面
- **Verification**: Structure（代码审计 SettingsView）

---

## M. 辅助功能与平台合规 (4 条)

### QA-M01: 交互目标尺寸 ≥ 60pt (EH-02)
- **Features**: F8.1
- **Preconditions**: 应用已启动
- **Steps**:
  1. 检查 PlayerControlsView 中所有按钮的 frame 尺寸
  2. 检查 FileBrowserView 中文件列表行的 tap target
  3. 检查 SettingsView 中所有交互控件
- **Expected Results**:
  - Step 1: 播放/暂停、快进/快退、速度、音轨、字幕 等按钮的 tap target ≥ 60pt
  - Step 2: 文件列表行高 ≥ 60pt
  - Step 3: 设置中的 toggle/slider/picker ≥ 60pt tap target
- **Verification**: Structure（代码审计 frame/padding 值）

### QA-M02: Ornament 位置合规 (WN-04/WN-05)
- **Features**: F8.5
- **Preconditions**: 应用在 Shared Space 模式
- **Steps**:
  1. 检查使用 .ornament modifier 的所有 View
  2. 确认锚定位置（bottom-trailing 或 trailing）
  3. 确认 ornament 不遮挡主内容
- **Expected Results**:
  - Step 1: 找到所有 ornament 使用点
  - Step 2: 锚定位置符合 visionOS HIG WN-04（ornament 不浮在窗口上方或左侧）和 WN-05（ornament 与窗口边缘对齐）
  - Step 3: ornament 内容不与窗口主内容重叠
- **Verification**: Structure + Human-only（视觉位置需真机确认）
- **Human-only reason**: Ornament 的精确空间位置需 3D 环境观察

### QA-M03: VoiceOver 可访问性标签覆盖
- **Features**: F8.4
- **Preconditions**: 代码审计模式
- **Steps**:
  1. 在 PlayerControlsView 中搜索 accessibilityLabel/accessibilityHint
  2. 在 FileBrowserView 中搜索
  3. 在 SettingsView 中搜索
  4. 在 VideoDetailView 中搜索
- **Expected Results**:
  - Step 1: 每个可交互按钮（播放/暂停/快进/快退/速度/音轨/字幕/逐帧步进）有 accessibilityLabel
  - Step 2: 文件列表行有 accessibilityLabel（文件名 + 大小等）
  - Step 3: 设置项有 accessibilityLabel
  - Step 4: 详情页按钮和信息区域有 accessibilityLabel
  - **已知缺陷 F8.4**：预期部分 FAIL — 未系统性审计 accessibilityLabel 覆盖
- **Verification**: Structure

### QA-M04: WorldTrackingProvider 接线检查（对抗性审查新增）
- **Features**: F8.3
- **Preconditions**: 代码审计模式
- **Steps**:
  1. 搜索 WorldTrackingProvider 或 ARKitSession 在 SpatialScene 模块中的使用
  2. 确认内容是否固定在世界空间（非跟随头部）
  3. 检查 .fixedToWorld 或等效锚定方式
- **Expected Results**:
  - Step 1: 找到 WorldTrackingProvider 或等效的世界空间锚定机制
  - Step 2: 虚拟屏幕、环境穹顶等 entity 使用世界空间坐标（非头部跟随）
  - Step 3: 确认 entity 位置不随用户头部运动而移动
- **Verification**: Structure + Human-only（世界空间固定的视觉效果需真机确认）
- **Human-only reason**: 空间锚定行为需 3D 环境中实际移动头部验证

---

## 覆盖矩阵

| 功能 ID | QA 路径 | 验证类型 |
|---------|---------|----------|
| F1.1 | QA-B01 | Simulator |
| F1.2 | QA-B04 | Structure + Human-only |
| F1.3 | QA-B02 | Simulator |
| F1.4 | QA-B03 | Simulator |
| F1.5 | QA-C02 | Simulator |
| F1.6 | QA-C01 | Simulator |
| F1.7 | QA-C04 | Simulator |
| F1.8 | QA-C05 | Simulator |
| F1.9 | QA-C01 | Simulator |
| F1.10 | QA-C02 | Simulator + Structure |
| F1.11 | QA-K02 | Simulator + Structure |
| F1.12 | QA-C03 | Simulator + Structure |
| F1.13 | QA-K01 | Simulator + Structure |
| F1.14 | — | 需 8K 素材（推迟） |
| F1.15 | QA-F01, QA-F03 | Simulator + Structure |
| F1.16 | QA-F02 | Simulator + Structure |
| F1.17 | QA-E01 | Simulator + Structure |
| F1.18 | QA-E02 | Simulator + Structure |
| F1.19 | QA-E03 | Structure + Human-only |
| F1.20 | QA-C01, QA-C02 | Simulator |
| F1.21 | QA-E02 | Structure（已知缺陷） |
| F1.22 | QA-E04, QA-E06 | Simulator + Structure |
| F1.23 | — | MVP 外（图片浏览推迟） |
| F2.1 | QA-A01 | Simulator |
| F2.2 | QA-A02 | Simulator + Structure |
| F2.3 | — | ⚪ MVP 外 |
| F2.4 | — | ⚪ MVP 外 |
| F2.5 | QA-B02, QA-B03 | Simulator |
| F2.6 | QA-A03 | Simulator |
| F2.7 | QA-I05 | Simulator |
| F2.8 | QA-B01 | Simulator |
| F2.9 | QA-A01, QA-A03 | Simulator |
| F3.1 | QA-C01 | Simulator |
| F3.2 | QA-D01, QA-F03 | Simulator + Structure |
| F3.3 | QA-E01~E05 | Simulator + Structure |
| F3.4 | QA-E04, QA-E05 | Structure |
| F3.5 | QA-H01~H04 | Structure + Human-only |
| F3.6 | QA-H01 | Structure + Human-only |
| F3.7 | QA-H02 | Structure + Human-only |
| F3.8 | QA-H03 | Structure + Human-only |
| F3.9 | QA-H04 | Structure + Human-only |
| F3.10 | QA-G04 | Simulator |
| F3.11 | QA-G06 | Simulator |
| F3.12 | QA-C01, QA-G07 | Simulator |
| F3.13 | QA-C01 | Simulator |
| F3.14 | QA-G01 | Simulator |
| F3.15 | QA-G02 | Simulator / Structure |
| F3.16 | QA-G03 | Simulator + Human-only |
| F3.17 | QA-D03 | Structure + Human-only |
| F3.18 | QA-D02 | Structure + Human-only |
| F3.19 | QA-D02 | Structure + Human-only |
| F3.20 | QA-D04 | Structure |
| F3.21 | QA-G05 | Simulator |
| F4.1 | QA-J01 | Structure（已知 FAIL） |
| F4.2 | QA-J02 | Structure |
| F4.3 | QA-J03 | Structure（已知 FAIL） |
| F4.4 | QA-I01 | Simulator |
| F4.5 | QA-I01 | Simulator |
| F4.6 | QA-I02 | Simulator |
| F4.7 | QA-I05 | Simulator（预期 FAIL） |
| F4.8 | — | Structure（内部清理机制，用户不可见） |
| F4.9 | QA-I03 | Simulator |
| F4.10 | QA-I04 | Simulator |
| F5.1 | QA-C02, QA-K04 | Simulator + Structure |
| F5.2 | QA-K03 | Structure（已知 FAIL） |
| F5.3 | QA-C03 | Simulator + Structure |
| F5.4 | QA-G03 | Simulator + Human-only |
| F6.1 | QA-D01, QA-D04 | Structure |
| F6.2 | QA-D04 | Structure |
| F6.3 | QA-D04 | Structure |
| F6.4 | QA-D04 | Structure |
| F6.5 | QA-D05 | Structure |
| F6.6 | QA-D05 | Structure（已知 FAIL） |
| F6.7 | QA-D01 | Structure |
| F7.1 | QA-L01 | Simulator |
| F7.2 | QA-L02 | Simulator |
| F7.3 | QA-L03 | Simulator |
| F7.4 | QA-L04 | Simulator |
| F7.5 | QA-L05 | Structure（已知 FAIL） |
| F7.6 | QA-L06 | Structure（已知 FAIL） |
| F8.1 | QA-M01 | Structure |
| F8.2 | QA-H01 | Structure |
| F8.3 | QA-M04 | Structure + Human-only |
| F8.4 | QA-M03 | Structure |
| F8.5 | QA-M02 | Structure + Human-only |
| F9.1~F9.3 | — | Human-only（性能/稳定性需真机长时间运行） |
| F9.4~F9.5 | — | ⚪ 真机限定 |

---

## 已知缺陷汇总（预期 FAIL 项）

| QA 路径 | 功能 | 已知缺陷 | 优先级 |
|---------|------|---------|--------|
| QA-D01, QA-F03 | F3.2 | 沉浸 bridge 断联 — `.immersive` 模式 VirtualScreenEntity 无视频纹理（**T0.6 代码审计升级**） | **P0** |
| QA-J01 | F4.1 | 无网络缓冲指示器 | P0 |
| QA-J03 | F4.3 | 无自动重连逻辑 | P0 |
| QA-K03 | F5.2 | 无 HDR/SDR 实时切换按钮 | P0 |
| QA-I05 | F4.7 | 文件列表进度提示形态为文字标记非进度条（**T0.6 修正：非缺失，形态不同**） | P2 |
| QA-H04 | F3.9 | 捏合拖拽进度条 — `.drag` case 执行 break 未接线（**T0.6 代码审计新增**） | P1 |
| QA-D05 | F6.6 | 屏幕形状不持久化 | P1 |
| QA-E02 | F1.21 | FOV 180/360 消歧 hardcoded nil（**对抗性审查升级为 FAIL**） | P1 |
| QA-M03 | F8.4 | VoiceOver 标签未审计 | P1 |
| QA-L05 | F7.5 | 远程缓存清理 UI 缺失（**对抗性审查新增路径**） | P1 |
| QA-L06 | F7.6 | About 页面缺失（**对抗性审查新增路径**） | P1 |
| QA-G04 | F3.10 | 二级时间轴 — 计算模型无 View 消费（**T0.6 代码审计新增**） | P2 |

---

## Human-only 验证清单

以下项在 Simulator 上无法充分验证，需人类真机操作：

| 项 | 原因 |
|----|------|
| QA-H01~H04 手势交互 | visionOS 捏合手势精度需真实 Hand Tracking |
| QA-D02 屏幕距离/高度 | 空间位置视觉确认需 3D 环境 |
| QA-D03 X 轴旋转 | 空间旋转效果需真机 |
| QA-E03 鱼眼校正 | 校正质量需人眼评估 |
| QA-G03 CJK 字幕 | 字体渲染质量需人眼 |
| QA-M02 Ornament 位置 | 空间位置需 3D 环境 |
| QA-B04 Photos 访问 | Simulator 无真实 Photos 库 |
| QA-M04 WorldTrackingProvider 接线 | 世界空间锚定需 3D 环境验证 |
| F9.1~F9.3 性能 | 长时间运行/内存/帧率需真机 |

---

## 统计

| 类别 | 路径数 | Simulator | Structure | Human-only |
|------|--------|-----------|-----------|------------|
| A. 启动与导航 | 3 | 3 | 1 | 0 |
| B. 文件源管理 | 4 | 3 | 1 | 1 |
| C. 窗口模式播放 | 5 | 5 | 2 | 0 |
| D. 沉浸影院模式 | 5 | 1 | 5 | 3 |
| E. 全景模式 | 6 | 4 | 6 | 1 |
| F. 3D 立体视频 | 3 | 2 | 3 | 0 |
| G. 播放控件 | 7 | 7 | 1 | 1 |
| H. 手势交互 | 4 | 0 | 4 | 4 |
| I. 状态管理 | 5 | 5 | 0 | 0 |
| J. 错误处理 | 3 | 0 | 3 | 0 |
| K. HDR/色彩管理 | 4 | 3 | 3 | 0 |
| L. 设置与偏好 | 6 | 4 | 2 | 0 |
| M. 辅助功能 | 4 | 0 | 4 | 2 |
| **总计** | **59** | **37** | **35** | **12** |

> 注: 一条路径可能同时有多种验证类型（如 Simulator + Structure）
> Simulator 覆盖率: 37/59 = 63%
> 需 Human-only 项: 12 条
> 对抗性审查新增: QA-E06, QA-L05, QA-L06, QA-M04
