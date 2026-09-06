import CoreGraphics
import CoreMedia
import CoreText
import Foundation

final class CoreTextSubtitleFrameRenderer: SubtitleFrameRendering, @unchecked Sendable {
    static let canvasWidth = 1_920
    static let canvasHeight = 1_080
    static let codecNames: Set<String> = ["subrip", "srt", "webvtt", "mov_text", "text", "tx3g"]

    static func rendersTextTrack(codecName: String) -> Bool {
        codecNames.contains(codecName.lowercased())
    }

    private let source: FFmpegSubtitleFrameRenderer
    private let track: PlaybackSubtitleTrack
    private let resolveStyle: @Sendable () -> CoreTextSubtitleStyle
    private let lock = NSLock()
    private var style: CoreTextSubtitleStyle
    private var cues: [PlaybackSubtitleCue]
    private var lastText: String?
    private var lastFrame: PlaybackSubtitleFrame?
    private var changeIdentifier: UInt64 = 0
    private var settingsObserver: NSObjectProtocol?

    init(
        source: FFmpegSubtitleFrameRenderer,
        track: PlaybackSubtitleTrack,
        style: @escaping @Sendable () -> CoreTextSubtitleStyle = CoreTextSubtitleStyle.captionAppearance
    ) throws {
        self.source = source
        self.track = track
        resolveStyle = style
        self.style = style()
        cues = try source.textCues(for: track)
        settingsObserver = NotificationCenter.default.addObserver(
            forName: CoreTextSubtitleStyle.settingsChangedNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.reloadStyle()
        }
    }

    deinit {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
    }

    func reloadStyle() {
        let next = resolveStyle()
        lock.withLock {
            style = next
            lastText = nil
            lastFrame = nil
        }
    }

    func ingestPendingCues(for track: PlaybackSubtitleTrack) throws -> [PlaybackSubtitleCue] {
        let arrived = try source.ingestPendingCues(for: track)
        guard !arrived.isEmpty else { return arrived }
        lock.withLock {
            cues.append(contentsOf: arrived)
            cues.sort { CMTimeCompare($0.timeRange.start, $1.timeRange.start) < 0 }
        }
        return arrived
    }

    func frame(
        at time: CMTime,
        viewportWidth: Int,
        viewportHeight: Int
    ) throws -> PlaybackSubtitleFrame? {
        guard time.isNumeric else { return nil }
        return lock.withLock {
            let text = cues
                .filter {
                    CMTimeCompare(time, $0.timeRange.start) >= 0
                        && CMTimeCompare(time, $0.timeRange.end) < 0
                }
                .map(\.text)
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            if text == lastText { return lastFrame }
            lastText = text
            changeIdentifier &+= 1
            lastFrame = text.isEmpty
                ? nil
                : Self.rasterize(text, changeIdentifier: changeIdentifier, style: style)
            return lastFrame
        }
    }

    static func rasterize(
        _ text: String,
        changeIdentifier: UInt64,
        style: CoreTextSubtitleStyle = CoreTextSubtitleStyle()
    ) -> PlaybackSubtitleFrame? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let emSize = style.emSize(canvasHeight: canvasHeight)
        let font = style.font(emSize: emSize)
        let outlineWidth = style.outlineWidth(emSize: emSize)
        var lineAdvance = style.lineAdvance(emSize: emSize)
        var alignment = CTTextAlignment.center
        let settings = [
            CTParagraphStyleSetting(
                spec: .alignment,
                valueSize: MemoryLayout<CTTextAlignment>.size,
                value: &alignment
            ),
            CTParagraphStyleSetting(
                spec: .minimumLineHeight,
                valueSize: MemoryLayout<CGFloat>.size,
                value: &lineAdvance
            ),
            CTParagraphStyleSetting(
                spec: .maximumLineHeight,
                valueSize: MemoryLayout<CGFloat>.size,
                value: &lineAdvance
            )
        ]
        let paragraph = CTParagraphStyleCreate(settings, settings.count)
        let outlineStrokePercent = outlineWidth * 2 / emSize * 100
        let outlineAttributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CoreTextSubtitleStyle.outlineColor,
            kCTStrokeWidthAttributeName: outlineStrokePercent as CFNumber,
            kCTStrokeColorAttributeName: CoreTextSubtitleStyle.outlineColor,
            kCTParagraphStyleAttributeName: paragraph
        ]
        let fillAttributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: style.fillColor,
            kCTParagraphStyleAttributeName: paragraph
        ]
        guard let outlined = CFAttributedStringCreate(
            kCFAllocatorDefault,
            text as CFString,
            outlineAttributes as CFDictionary
        ), let filled = CFAttributedStringCreate(
            kCFAllocatorDefault,
            text as CFString,
            fillAttributes as CFDictionary
        ) else { return nil }
        let outlineFramesetter = CTFramesetterCreateWithAttributedString(outlined)
        let fillFramesetter = CTFramesetterCreateWithAttributedString(filled)
        let horizontalMargin = CoreTextSubtitleStyle.horizontalMargin(canvasWidth: canvasWidth)
        let bottomMargin = CoreTextSubtitleStyle.bottomMargin(canvasHeight: canvasHeight)
        let blockWidth = CGFloat(canvasWidth) - horizontalMargin * 2
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            fillFramesetter,
            CFRange(location: 0, length: 0),
            nil,
            CGSize(width: blockWidth, height: CGFloat(canvasHeight)),
            nil
        )
        let padding = ceil(outlineWidth + style.shadowExtent(emSize: emSize) + 2)
        let textHeight = ceil(min(
            suggested.height,
            lineAdvance * CGFloat(CoreTextSubtitleStyle.maximumLines) + 0.5
        ))
        let blockHeight = textHeight + padding * 2
        let width = Int(ceil(blockWidth))
        let height = Int(ceil(blockHeight))
        guard width > 0, height > 0 else { return nil }
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            ) else { return false }
            let path = CGPath(
                rect: CGRect(
                    x: 0,
                    y: padding,
                    width: blockWidth,
                    height: textHeight
                ),
                transform: nil
            )
            let range = CFRange(location: 0, length: 0)
            context.saveGState()
            if let shadowOffset = style.shadowOffset(emSize: emSize) {
                context.setShadow(
                    offset: shadowOffset,
                    blur: style.shadowBlur(emSize: emSize),
                    color: CoreTextSubtitleStyle.shadowColor
                )
            }
            CTFrameDraw(CTFramesetterCreateFrame(outlineFramesetter, range, path, nil), context)
            context.restoreGState()
            CTFrameDraw(CTFramesetterCreateFrame(fillFramesetter, range, path, nil), context)
            return true
        }
        guard drew else { return nil }
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[y * bytesPerRow + x * 4 + 3] > 0 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let contentWidth = maxX - minX + 1
        let contentHeight = maxY - minY + 1
        var cropped = Data(capacity: contentWidth * 4 * contentHeight)
        for row in 0..<contentHeight {
            let sourceStart = (minY + row) * bytesPerRow + minX * 4
            cropped.append(contentsOf: pixels[sourceStart..<sourceStart + contentWidth * 4])
        }
        let blockTop = CGFloat(canvasHeight) - bottomMargin - blockHeight
        return PlaybackSubtitleFrame(
            kind: .coreText,
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight,
            contentX: Int(horizontalMargin) + minX,
            contentY: Int(blockTop) + minY,
            contentWidth: contentWidth,
            contentHeight: contentHeight,
            bytesPerRow: contentWidth * 4,
            premultipliedBGRA: cropped,
            changeIdentifier: changeIdentifier
        )
    }
}
