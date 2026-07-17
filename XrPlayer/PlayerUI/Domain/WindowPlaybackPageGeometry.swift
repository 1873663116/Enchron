import CoreGraphics

struct WindowPlaybackPageGeometry: Equatable {
    let canvasFrame: CGRect
    let deckFrame: CGRect?

    nonisolated static func resolve(
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
        let canvasHeight = max(0, containerHeight - deckHeight - resolvedSpacing)

        return Self(
            canvasFrame: CGRect(x: 0, y: 0, width: containerWidth, height: canvasHeight),
            deckFrame: CGRect(
                x: (containerWidth - deckWidth) / 2,
                y: canvasHeight + resolvedSpacing,
                width: deckWidth,
                height: deckHeight
            )
        )
    }
}
