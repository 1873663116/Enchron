# OceanEnvironment

Ocean 场景包。`Resources/ocean.reality` 由 Xrplay_scene 的 `scripts/export_scene.py ocean --without-plugins` 导出；`Sources/OceanEnvironment/Vendor/OceanProbe` 是从 Xrplay_scene `scratch/OceanProbePlugin` 的运行时 target 复制的海面 FFT 模拟与天空旋转，去掉了只在 Reality Composer Pro 内有意义的编辑器状态分支。`OceanEnvironmentScene` 在加载时注册组件与 System、按作者值挂上 `OceanProbeComponent`、禁用 `ScreenPreview`，并把屏幕位置、尺寸与视频纹理写进 `OceanMaterialSource` 的 `OceanVideo` 材质；黑夜模式按亮度缩放 `SkyGain` 与 `OceanSoftLight`。
