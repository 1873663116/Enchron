public nonisolated enum PlaybackSurfaceSeekTravel {
    public static let windowWidth: Double = 1200
    public static let immersiveScale: Double = 8

    public static var immersiveWidth: Double {
        windowWidth * immersiveScale
    }

    public static func width(for presentation: PlaybackPresentation) -> Double {
        switch presentation {
        case .docked, .panorama: immersiveWidth
        case .window, .portal: windowWidth
        }
    }
}
