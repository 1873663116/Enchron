# EnvironmentSceneContract

观影环境场景与 Enchron 之间的契约：`EnvironmentScene` 协议、`EnvironmentSceneDescriptor`／`EnvironmentSceneGeometry`（天花板、距离策略、默认与范围）、`EnvironmentAppearance`（亮度）、`EnvironmentScreenRestPose`（场景作者定的屏幕静止位姿：世界中心、右／上／法向基、半宽半高，以及派生的底边高度、距离、偏航与屏幕高度）、`EnvironmentScreenState`（屏幕中心、基向量、半宽半高、视频纹理）与场景内的稳定实体名。`EnvironmentScreenRestPose.screenPreview(in:)` 从场景里名为 `ScreenPreview` 的面片的世界变换求出静止位姿，`load()` 把它交给 `restPose`。它只依赖 RealityKit 与 simd。场景包实现协议，Enchron 只消费协议；两边都不认识对方。
