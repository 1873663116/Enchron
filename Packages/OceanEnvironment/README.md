# OceanEnvironment

Ocean 场景包。`Resources/ocean.reality` 由 Xrplay_scene 的 `scripts/export_scene.py ocean --without-plugins` 导出；`Sources/OceanEnvironment/Vendor/OceanProbe` 提供海面 FFT 模拟与天空旋转。`OceanEnvironmentScene` 在加载时注册组件与 System、挂上 `authoredSimulation`、禁用 `ScreenPreview`，并在更新时把屏幕位置、尺寸、水平右向量与视频纹理写进 `OceanMaterialSource` 的 `OceanVideo` 材质。黑夜模式按亮度缩放 `SkyGain` 与 `OceanSoftLight`。

打包资产中的 `DockingRegion` 中心对应 16 米高的作者屏幕。加载时以该中心和作者高度求出底边，再生成 20 米高的 `restPose`，使屏幕向上扩展、底边保持原位。世界变换由实体与所有父级变换合成。运行时宽度由视频比例确定，距离与观看高度范围由 `descriptor.geometry` 提供。

环境声由 `OceanEnvironmentAudio` 管理：`Resources/Audio` 里的 19 个 AAC 文件在 `load()` 时加载，环境声床播在场景里带 `AmbientAudioComponent` 的实体上，海浪按文件名前缀 `ocean_swell_near`／`ocean_swell_mid`／`ocean_swell_far` 组成三档；素材母版与重新编码方式见 Xrplay_scene 的 `assets/audio/ocean/rcp_setup.md`。音频不导入 RCP，因为 RCP 导出会把它解码成未压缩采样写进 `.reality`。
