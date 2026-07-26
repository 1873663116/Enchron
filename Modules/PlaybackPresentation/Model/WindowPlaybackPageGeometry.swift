import CoreGraphics

public struct WindowPlaybackPageGeometry: Equatable {
    public let canvasFrame: CGRect
    public let deckFrame: CGRect?

    public nonisolated static func resolve(
        in containerSize: CGSize,
        deckSize: CGSize?,
        spacing: CGFloat
    ) -> Self {
        let containerWidth = max(0, containerSize.width)
        let containerHeight = max(0, containerSize.height)
        guard let deckSize else {
            return Self(
                canvasFrame: CGRect(x: 0, y: 0, width: containerWidth, height: containerHeight),
                deckFrame: nil
            )
        }

        let deckWidth = min(containerWidth, max(0, deckSize.width))
        let deckHeight = min(containerHeight, max(0, deckSize.height))
        let resolvedSpacing = min(max(0, spacing), max(0, containerHeight - deckHeight))

        return Self(
            canvasFrame: CGRect(x: 0, y: 0, width: containerWidth, height: containerHeight),
            deckFrame: CGRect(
                x: (containerWidth - deckWidth) / 2,
                y: containerHeight - deckHeight - resolvedSpacing,
                width: deckWidth,
                height: deckHeight
            )
        )
    }
}
