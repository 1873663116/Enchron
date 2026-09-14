# OceanEnvironment

Ocean 场景包。`Resources/ocean.reality` 由 Xrplay_scene 的 `scripts/export_scene.py ocean --without-plugins` 导出；`Sources/OceanEnvironment/Vendor/OceanProbe` 是从 Xrplay_scene `scratch/OceanProbePlugin` 的运行时 target 复制的海面 FFT 模拟与天空旋转，去掉了只在 Reality Composer Pro 内有意义的编辑器状态分支。`OceanEnvironmentScene` 在加载时注册组件与 System、按作者值挂上 `OceanProbeComponent`（风向与涌浪方向与 RCP 工程一致）、从带 `DockingRegionComponent` 的 `Video` 实体的世界变换求出 `restPose`、禁用 `ScreenPreview`，并把屏幕位置、尺寸、水平右向量与视频纹理写进 `OceanMaterialSource` 的 `OceanVideo` 材质；黑夜模式按亮度缩放 `SkyGain` 与 `OceanSoftLight`。场景根只有竖直位移、没有旋转，局部轴与 visionOS 世界轴一致：观众朝 −Z，屏幕在 (0, −1, −15) 朝 +Z；`restPose` 仍由根变换与实体局部变换合成，不能读局部值。

环境声由 `OceanEnvironmentAudio` 管理：`Resources/Audio` 里的 19 个 AAC 文件在 `load()` 时加载，环境声床播在场景里带 `AmbientAudioComponent` 的实体上，海浪按文件名前缀 `ocean_swell_near`／`ocean_swell_mid`／`ocean_swell_far` 组成三档；素材母版与重新编码方式见 Xrplay_scene 的 `assets/audio/ocean/rcp_setup.md`。音频不导入 RCP，因为 RCP 导出会把它解码成未压缩采样写进 `.reality`。
