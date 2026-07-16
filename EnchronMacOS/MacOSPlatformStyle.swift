import SwiftUI

enum MacOSGlassBackgroundEffect {
    case plate
}

enum MacOSGlassBackgroundDisplayMode {
    case always
}

extension View {
    func glassBackgroundEffect<S: InsettableShape>(
        in shape: S,
        displayMode: MacOSGlassBackgroundDisplayMode = .always
    ) -> some View {
        glassEffect(.regular, in: shape)
    }

    func glassBackgroundEffect<S: InsettableShape>(
        _ effect: MacOSGlassBackgroundEffect,
        in shape: S,
        displayMode: MacOSGlassBackgroundDisplayMode = .always
    ) -> some View {
        glassEffect(.regular, in: shape)
    }
}
