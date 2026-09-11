# EnvironmentSceneContract

观影环境场景与 Enchron 之间的契约：`EnvironmentScene` 协议、`EnvironmentSceneDescriptor`／`EnvironmentSceneGeometry`（天花板、距离策略、默认与范围）、`EnvironmentAppearance`（亮度）、`EnvironmentScreenState`（屏幕中心、基向量、半宽半高、视频纹理）与场景内的稳定实体名。它只依赖 RealityKit 与 simd。场景包实现协议，Enchron 只消费协议；两边都不认识对方。
