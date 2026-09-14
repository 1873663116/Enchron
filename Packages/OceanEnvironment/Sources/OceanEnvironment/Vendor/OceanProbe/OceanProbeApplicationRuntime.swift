import Foundation
import RealityKit

@MainActor
public enum OceanProbeApplicationRuntime {
    public static func register(environmentTextureBundle: Bundle) {
        RuntimeEnvironmentLighting.configure(
            applicationResourceBundle: environmentTextureBundle
        )
        OceanProbeComponent.registerComponent()
        OceanProbeSystem.registerSystem()
    }
}
