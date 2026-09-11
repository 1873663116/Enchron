# QuietRoomEnvironment

Quiet Room 场景包，产品的默认观影环境。`Resources/quiet_room.reality` 由 Xrplay_scene 的 `scripts/export_scene.py quiet_room` 导出。`QuietRoomEnvironmentScene` 从 `ScreenPreview` 的世界变换求出 `restPose` 再禁用它，收集所有带 `screen_center` 参数的 `FloorScreenGlow` 材质，把屏幕中心、半宽、半高与视频纹理写进去；没有屏幕时把 `screen_light_gain` 置零。它没有黑夜模式。
