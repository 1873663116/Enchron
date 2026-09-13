# QuietRoomEnvironment

Quiet Room 场景包，产品的默认观影环境。`Resources/quiet_room.reality` 由 Xrplay_scene 的 `scripts/export_scene.py quiet_room` 导出。`QuietRoomEnvironmentScene` 从 `ScreenPreview` 的世界变换求出 `restPose` 再禁用它，收集所有带 `screen_center` 参数的 `FloorScreenGlow` 材质，把屏幕中心、半宽、半高、法向（`screen_forward`）与视频纹理写进去，并把 `screen_lod_near`/`screen_lod_far` 按视频纹理宽度与 1920 像素参考画面的比值换算，使头显上投到地面的画面模糊程度与 RCP 里用全尺寸测试图调出的一致；没有屏幕时把 `screen_light_gain` 置零。加载时把作者摆放的 `Floor_*`/`Ceil_*` 瓦片按 Floor/Ceil 与 A/B/C 变体分组合并成 `MeshInstancesComponent` 宿主，原实体移除。它没有黑夜模式。
