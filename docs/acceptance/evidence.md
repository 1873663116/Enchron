# Enchron 播放系统证据

## 2026-07-17 macOS 产品播放闭环

- Scope：`EnchronMacOS` 现在以生产 `PlaybackRuntime` 和 in-tree `Packages/PlaybackCore` 作为本地媒体、文件夹、播放/暂停、seek、音轨、字幕与空间呈现状态机的主要开发宿主。产品媒体路线仍是 FFmpeg demux → compressed `CMSampleBuffer` → AVFoundation Receiver/synchronizer → RealityKit；没有把 Apple reference route 变成第二条产品路线。
- Deterministic fixtures：120.064 秒双音轨音画同步 MP4 的 SHA-256 为 `9c318aac50d9c4d03c82b988ad0ae83a06403cf5d813622724da3f5eed4eb80e`。30 秒 H.264/AAC/双音轨/SubRip/ASS/DVB bitmap MKV 在两次独立生成后均为 `4877f4030938ccf9e58933112a15ae59db46f5206b823b092aea0398f3a0f1d2`；嵌入的最小 DVB bitmap oracle 两次生成均为 `e6d5a376afea6ce10ffba5c33b4877d92e59199e2617437d26d3bca02110cfad`。生成脚本把 output `-bitexact` 放在 Matroska 输出之前，fixture registry 同时记录三条字幕轨与 bitmap pixel oracle。
- Subtitle architecture：文本、SubRip、WebVTT、MOV_TEXT 与 ASS 进入固定版本的 libass 0.17.4；HarfBuzz 14.2.0、FriBidi 1.0.16、FreeType 2.14.3 一并构建为 macOS、visionOS device 与 visionOS Simulator XCFramework slices。PGS/DVD/DVB 保持 decoder bitmap；两类输出统一为带 canvas/content rect、premultiplied BGRA 与 change ID 的 `PlaybackSubtitleFrame`，经共享 RealityKit transparent `UnlitMaterial` 纹理平面合成。底部安全带为控制层保留 32% 高度，避免字幕像素被 transport 覆盖。
- Real App subtitle/audio evidence：`/tmp/EnchronMacOSBitmapSubtitle-20260717-1330/result.json` 通过。SubRip 为 libass frame，13,606 个变化像素、3,718,553 channel difference；ASS 为 libass frame，28,764 / 8,870,149；DVB 为 bitmap frame，53,567 / 16,977,422。切换第二音轨并进入 Docked 后仍保持同一 session `A7C72E2B-4B53-4567-9DC8-98C5D141F58D` 和 bitmap frame；对应透明合成截图保存在同目录。
- Presentation/transport evidence：`/tmp/EnchronMacOSTransportPanorama-20260717-1342/result.json` 通过一次真实 App、真实鼠标流程：Window → Docked → Window → Panorama simulation → Window → pause → forward seek 约 10 秒 → resume → Back，全程 session `E41DBCEB-A2D6-455E-A375-12499122FE50`。macOS 的 Panorama 明确记录 `presentation=panorama / hosted=window / attached=window / simulation=panorama`，只模拟产品状态和同一 Window consumer，不宣称 macOS 创建了 `ImmersiveSpace`。
- Remote sources：WebDAV/SMB 范围读取、目录、认证与 credential lifecycle 共 11 项 focused contract 加 Xcode credential tests 通过。本机未配置 `ENCHRON_WEBDAV_TEST_*`、SMB 或其他 live endpoint 环境，因此真实远端播放按设计跳过，没有用 localhost 或 mock 冒充外部服务通过。
- Build and tests：PlaybackCore 81 tests 全部通过；Enchron 根包 48 项 Swift Testing 与 8 项 XCTest 通过，1 项未配置 live WebDAV 的测试按设计跳过。`EnchronMacOS` Release 构建、`XrPlayer` generic visionOS device 构建及 arm64 visionOS Simulator 构建通过。独立启动 Release bundle 还发现并修复了 `AMSMB2.framework` 只链接未嵌入的问题；最终 `Contents/Frameworks/AMSMB2.framework` 存在且 App 不依赖 Xcode 注入的 `DYLD` 路径即可播放。
- XCUI infrastructure boundary：`/tmp/EnchronMacOSFull-20260717-1347.xcresult` 中 8 项 macOS unit tests 通过，UI runner 在建立 XCTest 连接前挂起；重置 `testmanagerd` 后 `/tmp/EnchronMacOSUIFull-20260717-1353.xcresult` 再次得到相同 runner infrastructure failure。没有 UI assertion 失败。真实鼠标 harness 的产品流程证据独立通过，但不能把它改写成 XCTest runner 通过。
- Instruments：20 秒 Release Time Profiler 基线为 `/tmp/EnchronMacOSReleaseTimeProfiler-20260717-1420.trace`，最终为 `/tmp/EnchronMacOSReleaseTimeProfilerFinal-20260717-1437.trace`，两者 TOC 均指向 `/tmp/EnchronProfileBuild/Build/Products/Release/EnchronMacOS.app/Contents/MacOS/EnchronMacOS`。唯一可复现的 App 自有热点是 `PlaybackDebugRecorder` 对每个 heartbeat 重开事件文件并原子重写完整快照；改为会话内复用事件句柄、逐条保留 JSONL、首帧即时快照、其余快照 1 Hz 合并及显式/关闭强制刷新后，inclusive samples 从 100 ms / 1.736% 降至 49 ms / 0.516%，文件重开从 22 ms 降至 0。最终 trace 仍有一次 280.49 ms microhang；对应窗口只有 2 ms 样本回溯到 Enchron view，其余在 CoreRE、RealityFusion、SwiftUI/AttributeGraph，证据不足以归因给产品代码。
- Remaining boundary：本节关闭 macOS 本地产品路径、字幕像素、控制、同会话模式转换、远端契约、独立 Release 打包与 App 自有 CPU 热点；不替代 visionOS Simulator 空间运行、真实 WebDAV/SMB endpoint、Vision Pro 硬件解码/HDR/最终空间呈现与物理听音证据。

## 2026-07-16 Simulator 空间播放验收入口

- Code revision：本节对应的空间播放验收提交，基于 Enchron `889b19e832e5`。
- Implementation：新增 `SpatialPresentationAcceptanceUITests.testRealPlaybackDockedAndPanoramaRoundTrips` 与 `scripts/verify-spatial-presentations-simulator.zsh`。测试使用本机生成的 H.264/AAC moving fixture，经带认证与 Range 的 localhost HTTP source 进入产品 FFmpeg → PlaybackCore 路线，不设置 `ENCHRON_UI_TESTING`；一次启动要求 Window → Docked → Window → Panorama → Window、同一 Media Session、持续播放截图变化、无 load failure，并保存 `.xcresult` 截图。产品运行时把 scene container、RealityView/entity identity，以及 `VideoPlayerComponent` desired/actual immersive、viewing、spatial video mode 写入 PlaybackCore presentation events。
- Deterministic checks：runner 拒绝 UI fixture 日志，核对最终 snapshot 的 session/binding identity、active RealityKit binding、video/audio sample 推进与无 terminal error，并要求 presentation event 序列及 Panorama `ready + progressive/mono/screen` 收敛。语义元素不可直接命中时，测试保存截图后只使用该元素的语义几何中心 fallback；无有效几何即失败。runner 另有 600 秒宿主 watchdog，并把 `waiting for workers to materialize` 明确分类为基础设施失败。
- Compile and lower layers：新产品代码与 UI test target 已由 Xcode 27 beta 2 完整编译、链接、签名；PlaybackCore 67 tests 全部通过；Enchron 根包 30 项 Swift Testing 与 5 项 XCTest 通过，1 项外部 WebDAV 测试按设计跳过。
- Simulator result：未通过也未判定产品失败。原 Apple Vision Pro device 与新建隔离 device 均无法启动最小 `SmokeLaunchUITests`；Xcode 的首个未完成操作一致为 `com.apple.dt.xctest.target-runner` 等待 workers materialize，`IDELaunchiPhoneSimulatorLauncher` 未完成。直接 `simctl launch` 也无法返回，Device Hub 截图为纯黑；因此真实 Docked/Panorama 断言尚未开始执行。主要诊断 bundle 位于 `/var/folders/dw/_wl4kmhd2fdgqfmmj2ghcyb40000gn/T/EnchronSpatialAcceptance-20260716-125807/`。Vision Pro L3 未执行。

## 2026-07-16 单仓迁移与应用控制收敛

- Verified code revision：Enchron `e6d32e86e3d9`；该 revision 已包含完整 PlaybackCore 导入历史与应用控制重构。
- Scope：PlaybackCore 以保留 Git 历史的方式进入 `Packages/PlaybackCore`；核心行为 spec、节点 01–09、fixture registry 和 evidence 进入 Enchron 的统一 `docs/`。macOS `EnchronMacOS` 同时保留 Core scenario 与生产 App Adapter scenario，二者是同一 Enchron App 的递进验证入口。
- State ownership：删除 Enchron App 的重复 `PlaybackState`、`PlaybackSession`、媒体格式副本与 seek generation。`PlaybackRuntime` 直接投影 PlaybackCore 的 `PlaybackStatus`；连续相对 seek 在 `PlaybackCoreController` 内基于最新请求目标累计，App 不再推测核心时间线。
- L1：`Packages/PlaybackCore` 的 `swift test` 共 67 项全部通过，新增 `rapidRelativeSeeksAccumulateInsideTheCore`；Enchron 根包 30 项 Swift Testing 与 6 项 XCTest 通过，其中 1 项未配置外部 WebDAV 环境而按设计跳过。
- Build：`EnchronMacOS` macOS target 与 `XrPlayer` `generic/platform=visionOS` 无签名构建通过。Xcode 直接从 `Packages/PlaybackCore` 解析本地 package，不再依赖兄弟仓库路径。
- Core L2：`script/build_and_run.sh --l2-core /Users/xiongzhipeng/Desktop/test/HDR10/HDR10.MP4 /tmp/enchron-l2-core-e6d32e8.json` 通过。Apple compressed 与 FFmpeg compressed 两条路线均完成真实播放推进、audio renderer enqueue、暂停/恢复、音量/静音、速率恢复、前后 seek、三次连续 seek、cleanup 与 reopen；sample 与 displayed pixel 均符合 BT.2020/PQ/video-range oracle，displayed pixel format 为 `&xv0`。artifact 内嵌 Enchron/PlaybackCore revision 均为 `e6d32e86e3d9`。
- App Adapter L2：`script/build_and_run.sh --l2-app /Users/xiongzhipeng/Desktop/test/HDR10/HDR10.MP4 /tmp/enchron-l2-app-e6d32e8.json` 通过。生产 `PlaybackRuntime` 的 FFmpeg 路线通过与 Core scenario 相同的 renderer、颜色、音频、控制、cleanup 与 reopen 断言；artifact 内嵌 Enchron/PlaybackCore revision 均为 `e6d32e86e3d9`。
- Simulator boundary：visionOS 27.0 Simulator 测试已完成编译，但 test runner 没有 materialize；Xcode 等待约 295 秒后报告 simulator launch server died，`NSMachErrorDomain Code=-308 (ipc/mig) server died`。显式重启后仍停在 `Waiting on BackBoard`。因此本次结果是 Simulator 基础设施阻塞，不是测试失败，也不标记 Simulator passed。
- Evidence boundary：当前 HDR10 fixture 仍是 license 未记录的 diagnostic fixture，audio renderer 推进不能代替物理听音，Vision Pro L3 未执行。

## 2026-07-16 Enchron macOS L2 恢复与 HDR10 颜色回归

- Code revisions：PlaybackCore `2491fede02ba` 与 Enchron `f4aa5be3311f` 加当前工作区变更。
- Toolchain：Xcode 27.0 beta 2（`27A5209h`）、Apple Swift 6.4、macOS 27 SDK、FFmpeg 8.0.1。
- Diagnostic fixture：registry ID `local-hdr10-pq-hevc-aac-001`，本机 `HDR10.MP4`，759,326,428 bytes，SHA-256 `b73fe04c7cec95449d0d9d09e6211693b766ae178b73ca7bf25eae3288b09580`，HEVC `hvc1`、3840×2160、59.94 fps、HDR10/PQ、AAC stereo。registry 把它标为 `diagnostic-only-until-license-is-recorded`；因此本轮结果不能代表完整 acceptance fixture matrix。
- Historical reference：commit `8ba948006597222bbbb8e4d657efd370d8ab7545` 的 Verify App 已同时实现 Apple compressed 与 FFmpeg compressed 两条路线。FFmpeg 只负责 demux；两条路线从 compressed `CMSampleBuffer` 后共用 AVFoundation renderer、synchronizer、RealityKit consumer、控制和断言。当前 Enchron macOS Core scenario 恢复的是这条分层边界，不把历史实现误写为只有 `AVAssetReader`。
- Color first failure：FFmpeg Provider Open 与 sample 一度缺失 BT.2020/PQ/matrix；其根因是 2026-07-16 的 FFmpeg 构建加入 `--disable-decoders`。bridge 不调用 FFmpeg decode API，但 `avformat_find_stream_info` 仍需要 codec probing 从 HEVC VUI 补出容器没有直接给出的颜色事实。移除该选项并把构建 revision 更新为 `network-demux-metadata-v2` 后，Provider 恢复 `bt2020 / smpte2084 / bt2020nc / tv`。
- Range first failure：Provider 已报告 `tv` 时，FFmpeg sample 的 `CMFormatDescription` 仍没有 range；bridge 只为 JPEG range 写入 `FullRangeVideo=true`，对 MPEG range 没有写入 `false`。现在两种已知 range 都显式写入，FFmpeg sample 恢复 `2020 / ST_2084_PQ / 2020 / video`，displayed pixel 为 `&xv0`。
- Lifecycle failures：快速 seek 与 close 暴露了三个独立竞态。FFmpeg video/audio reader 的同步 copy 与 `cancel()` 销毁 reader 可并发，导致 use-after-free；delivery task cancellation 曾在持有 `deliveryTaskLock` 时进入 AVFoundation Receiver cancellation，形成锁顺序反转；三个 actor-reentrant seek 可同时等待同一旧任务，随后较旧 waiter 与最新 waiter 一起进入同一个 session。修复分别为序列化 reader 所有权、在锁外执行 `Task.cancel()`、等待后重新检查 seek generation，并新增三连 seek 回归测试。
- L1 result：当时 `swift test` 的 66 tests 全部通过，包含 `threeRapidSeeksOnlyAllowNewestWaiterToEnterSession`；后续单仓迁移记录已提升为 67 项。
- L2 command：`Enchron/script/build_and_run.sh --l2-core /Users/xiongzhipeng/Desktop/test/HDR10/HDR10.MP4 /tmp/enchron-l2-core-hdr10-after-seek-fix.json`。同一构建随后直接执行两次，artifact 为 `/tmp/enchron-l2-core-repeat-1.json` 与 `/tmp/enchron-l2-core-repeat-2.json`。
- L2 machine result：三次完整双路线运行都通过。Apple compressed 与 FFmpeg compressed 均证明真实 Receiver、共享 synchronizer、RealityKit `VideoMaterial` consumer、displayed pixel、audio sample/buffer 推进、3 秒稳定播放、pause/resume、volume/mute、1.5× 与恢复、前后 seek、三次快速连续 seek 的最终请求所有权、cleanup barrier 与新 session/reopen。两条路线的 sample 与 displayed pixel 都保持 BT.2020/PQ/video-range；renderer ready 且无 terminal error。
- App Adapter command：`Enchron/script/build_and_run.sh --l2-app /Users/xiongzhipeng/Desktop/test/HDR10/HDR10.MP4 /tmp/enchron-l2-app-adapter-hdr10.json`，同一构建复测 artifact 为 `/tmp/enchron-l2-app-adapter-repeat.json`。Enchron macOS target 直接编译生产 `XrPlayer/App/PlaybackRuntime.swift` 与其产品模型，不使用同名 fixture adapter；两次都通过产品 FFmpeg route 的同一媒体、控制、颜色、RealityKit、cleanup 与 reopen 断言。Core FFmpeg 与 App Adapter 均记录 `receiverAsyncBackpressure`、`platform=macOS`、BT.2020/PQ/video-range 和 `&xv0`，连续 seek 最终 epoch 与目标一致。
- Product assembly：Enchron 30 项 Swift Testing 加 5 项 XCTest 通过，1 项未配置外部 WebDAV 环境的测试按设计跳过；`XrPlayer` generic visionOS device 无签名构建通过，证明同一 `PlaybackRuntime` 的 visionOS 分支仍可编译。这仍不是 Simulator 或设备运行证据。
- Evidence boundary：音频 renderer enqueue 与共享时间线只能证明 audio lane 推进，不能代替人在物理输出设备上确认“可听且同步”；当前 fixture 只有单音轨，也没有覆盖 SDR、HLG、Dolby Vision、B-frame、长媒体和许可完整的 fixture 集合。visionOS Simulator 当前 revision 与 Vision Pro L3 尚未执行。因此本记录关闭本地 HDR10 颜色、快速 seek/cleanup 与生产 App Adapter 接入回归，但仍不把完整 L2 或整个验收链标记为通过。

## 2026-07-15 Swift 6.4 / AVFoundation Receiver 升级

- Code revision：`89310ad` 加当前未提交升级工作区。
- Toolchain：Xcode 27.0 beta 2（`27A5209h`）、Apple Swift 6.4（`swiftlang-6.4.0.23.5`）、macOS 27 SDK、visionOS 27 SDK。
- Commands：`script/build_ffmpeg.sh` 与 object-level `vtool -show-build`；PlaybackCore 在全新 scratch path 执行 `swift test`；两个保留诊断工具以 `xcrun swiftc -swift-version 6 -typecheck` 检查；Enchron `swift test`；`XrPlayer` 与 `DesignPreview` 的 `generic/platform=visionOS` 无签名构建。
- Result：FFmpeg XCFramework 的 macOS arm64、visionOS arm64、visionOS Simulator arm64 / x86_64 object 均声明 minOS 27.0 与 SDK 27.0；PlaybackCore 全新冷构建 56 tests passed；两个诊断工具无警告通过 Swift 6 类型检查；Enchron 31 tests passed、1 个需外部 WebDAV 环境的测试 skipped；两个 visionOS scheme 构建成功，XrPlayer 另以全新 DerivedData 链接重建后的 FFmpeg 成功。
- Proven：现有 provider、Media Session、控制与 renderer graph 已在 Swift 6.4 工具链编译；Apple reader 使用 `AVAssetReaderOutput.Provider`；audio/video 输入使用 AVFoundation Receiver async enqueue、Receiver flush 与 rendering event；正常接受、解码警告、flush cancellation、requires-flush failure、backpressure cancellation 与 cleanup 有确定性回归。
- Not proven：Vision Pro 硬件解码、HDR / Dolby Vision、RealityKit 最终呈现和长时间真机行为；单一公开 sample-buffer 路径、compressed audio、subtitle interface 与移除 route selection 仍属于后续架构迁移。

当前 Xcode 27 beta 2 SDK 声明的 video Receiver requires-flush rendering event 与本机 macOS 27 beta Swift runtime 符号不一致。实现不直接引用该不匹配 case，并把未识别的 video terminal event 保守记录为 requires-flush failure；更新到匹配的 Xcode / macOS beta 后必须重新验证并移除此兼容边界。

## AVFoundation reference evidence

既有 macOS probe 已证明 Dolby Vision Profile 5、8.1 与 8.4 的 storage-format sample 保留对应 codec configuration，并被 Apple renderer 接受产生 displayed pixel buffer。既有 Vision Pro 人工对照记录显示三类样片的 Apple Compressed 画面与系统播放器一致。

这些结果证明 AVFoundation reference path 的系统能力，不证明 PlaybackCore 当前 FFmpeg sample assembly 已经满足同一合同；产品路径迁移后必须使用相同 profile 重新验证。
