import CoreGraphics
import CoreMedia
import CoreText
import Foundation

final class CoreTextSubtitleFrameRenderer: SubtitleFrameRendering, @unchecked Sendable {
    static let canvasWidth = 1_920
    static let canvasHeight = 1_080
    static let fontName = "Helvetica Neue"
    static let lineHeight: CGFloat = 64
    static let horizontalMargin: CGFloat = 80
    static let bottomMargin: CGFloat = 54
    static let outlineWidth: CGFloat = 3
    static let shadowOffset: CGFloat = 1
    static let fillColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    static let outlineColor = CGColor(srgbRed: 0.063, green: 0.063, blue: 0.063, alpha: 1)
    static let shadowColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.5)
    static let codecNames: Set<String> = ["subrip", "srt", "webvtt", "mov_text", "text", "tx3g"]

    static func rendersTextTrack(codecName: String) -> Bool {
        codecNames.contains(codecName.lowercased())
    }

    private let source: FFmpegSubtitleFrameRenderer
    private let track: PlaybackSubtitleTrack
    private let lock = NSLock()
    private var cues: [PlaybackSubtitleCue]
    private var lastText: String?
    private var lastFrame: PlaybackSubtitleFrame?
    private var changeIdentifier: UInt64 = 0

    init(source: FFmpegSubtitleFrameRenderer, track: PlaybackSubtitleTrack) throws {
        self.source = source
        self.track = track
        cues = try source.textCues(for: track)
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
                : Self.rasterize(text, changeIdentifier: changeIdentifier)
            return lastFrame
        }
    }

    static func rasterize(
        _ text: String,
        changeIdentifier: UInt64
    ) -> PlaybackSubtitleFrame? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let font = Self.font()
        var alignment = CTTextAlignment.center
        let settings = [
            CTParagraphStyleSetting(
                spec: .alignment,
                valueSize: MemoryLayout<CTTextAlignment>.size,
                value: &alignment
            )
        ]
        let paragraph = CTParagraphStyleCreate(settings, settings.count)
        let pointSize = CTFontGetSize(font)
        let outlineStrokePercent = outlineWidth * 2 / pointSize * 100
        let outlineAttributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: outlineColor,
            kCTStrokeWidthAttributeName: outlineStrokePercent as CFNumber,
            kCTStrokeColorAttributeName: outlineColor,
            kCTParagraphStyleAttributeName: paragraph
        ]
        let fillAttributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: fillColor,
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
        let blockWidth = CGFloat(canvasWidth) - horizontalMargin * 2
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            fillFramesetter,
            CFRange(location: 0, length: 0),
            nil,
            CGSize(width: blockWidth, height: CGFloat(canvasHeight)),
            nil
        )
        let padding = outlineWidth + shadowOffset + 2
        let blockHeight = min(
            CGFloat(canvasHeight) - bottomMargin,
            ceil(suggested.height) + padding * 2
        )
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
                    height: blockHeight - padding
                ),
                transform: nil
            )
            let range = CFRange(location: 0, length: 0)
            context.saveGState()
            context.setShadow(
                offset: CGSize(width: shadowOffset, height: -shadowOffset),
                blur: 0,
                color: shadowColor
            )
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

    static func font() -> CTFont {
        let nominal = CTFontCreateWithName(fontName as CFString, lineHeight, nil)
        let cellHeight = CTFontGetAscent(nominal) + CTFontGetDescent(nominal)
        guard cellHeight > 0 else { return nominal }
        return CTFontCreateWithName(fontName as CFString, lineHeight * lineHeight / cellHeight, nil)
    }
}
