# visionOS presentation regression

本文只记录回归合同，不授权执行真机测试。文件名、`script/probe_vision_device.sh` 与 `--presentation-probe` 中的 probe 是保留的启动入口名称，不代表另一套播放器或呈现协调器。只有操作者针对本次运行明确确认 Vision Pro 已佩戴、解锁且可测试后，脚本才可构建签名版本、安装和启动；设备已连接或过去曾确认都不算本次授权。代码驱动输入端调用与 SwiftUI 相同的公开 `PresentationCommand`，没有 probe 专属 scene 或 binding 编排。

回归使用两类 fixture。rectilinear 音视频 fixture 验证 Flat Window、无媒体与 Window 播放中的独立 Open / Close Scene、Docked 与 Window 返回；APMP equirectangular fixture 验证同一个 Playback Window `RealityView` 中的 Portal、同一个 Playback `ImmersiveSpace` 中使用 `.progressive` viewing mode 的黑场 Panorama，以及通过 showWindow 或 closeMedia 恢复进入前的 Scene 状态。两条 Playback Route 的成功记录彼此独立。

Stereo 是独立用例组，不和 Scene、Projection、Route 或播放控制做全排列。八个 Stereo case 固定使用同一个 active Apple Compressed APMP Media Session，在 Flat Window、Portal Window、Docked、Panorama 各自验证 `mono ↔ sideBySide` 与 `mono ↔ overUnder`；组内不得为每个 case reopen。唯一预期结果是目标 Stereo 生效且产品形态、Projection、Placement、Scene Lifecycle、Scene Content 与 Custom Scene Intent 不变。

如果 30 秒 fixture 在组内接近结束，runner 可以在下一个 case 捕获 baseline 之前对同一 Media Session 执行 seek-to-zero 以恢复测试余量；这不得更换 Media Session、renderer 或 route，也不计入 Stereo case 的预期结果。

manifest 固定为 49 个独立 case：无媒体 Window / Scene lifecycle 4 个；两条路线各验证四种 Shape，共 8 个；Window 播放中 Scene open / close 不迁移 2 个；上述固定 session 验证四种 Shape 各自的两个 Stereo round-trip，共 8 个；Panorama 从 Scene closed / `customScene` open 进入，并分别通过 showWindow 与 closeMedia 恢复，共 4 个；Docked → Flat Window、Docked → Panorama、Panorama → Flat Window 合法 edge 共 3 个；两条路线各自验证 pause、play、rate、seek、audio track selection、volume、mute toggle、reopen、close，共 18 个，且每个控制 case 从 Playing Flat Window、mono、Scene closed 开始；cold route switch 1 个；final cleanup 1 个。

精确 ID schema 为 `lifecycle.{lifecycle}`、`shape.{route}.{shape}`、`scene.windowPlayback.{openDoesNotMigrate|closeDoesNotMigrate}`、`stereo.{shape}.mono-{sideBySide|overUnder}-roundTrip`、`scene.{panoramaFromClosed.restoresClosed|panoramaFromOpen.restoresCustomScene|closeMediaFromPanorama.restoresClosed|closeMediaFromPanorama.restoresCustomScene}`、`edge.{dockedToFlatWindow|dockedToPanorama|panoramaToFlatWindow}`、`control.{route}.{control}`、`route.appleCompressed-to-ffmpegCompressed.coldSwitch` 和 `cleanup.final`；lifecycle、route、shape、control 的取值固定为验证系统列出的集合。实际 `caseID` 集合必须和展开后的 49 个预期 ID 完全相等；缺失、重复、未声明的 ID 或尚未到终态的 case 都使 `completed = false`。已经明确到达 failed 终态的 case 仍可计入 `completed`，但必须使 `passed = false`。

每个 case 记录实际 route / source、Media Session、renderer / video Entity identity、RealityView、Scene Lifecycle / Content / Intent、Playback Placement、Candidate / Presented Product Shape、Detected / Effective Projection、desired / actual viewing mode、acknowledgement surface、sample baseline、保留引用的 displayed-pixel observation、timeline、rollback 与错误。只有公开状态达到目标、renderer 精确为 ready，并在转换后得到归属于当前 renderer 的 fresh pixel，且 sample / timeline 相对 baseline 继续推进时才通过；缺少 required key 或失败时丢失 baseline / 中间 evidence 都不得通过。

Window Bar、当前形态下按钮不存在或 disabled、控件不遮挡视频等纯 UI 问题由少量 UI smoke 或人工检查负责。自动回归不调用产品 UI 不暴露的非法组合。

真机回归证明真实设备上的 scene/API 交接和可见播放事实，但不自动替代 HDR / EDR、可听输出、主观同步或空间观感的人工差分验收。
