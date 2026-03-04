import SwiftUI
import RealityKit
import RealityKitContent

public struct ImmersiveSpaceView: View {
    @Environment(AppModel.self) var appModel

    public init() {}
    
    public var body: some View {
        RealityView { content in
            // Initial content
            if let entity = try? await Entity(named: "Immersive", in: realityKitContentBundle) {
                content.add(entity)
            }
        }
    }
}
