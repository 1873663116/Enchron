import CoreGraphics
import CoreText
import Foundation
import MediaAccessibility

struct CoreTextSubtitleStyle: @unchecked Sendable {
    enum EdgeShadow: Equatable, Sendable {
        case none
        case raised
        case depressed
        case dropShadow
    }

    static let emFraction: CGFloat = 0.05
    static let lineAdvanceEmMultiple: CGFloat = 1.2
    static let outlineEmFraction: CGFloat = 0.06
    static let marginFraction: CGFloat = 0.05
    static let maximumLines = 3
    static let shadowOffsetEmFraction: CGFloat = 0.1
    static let shadowBlurEmFraction: CGFloat = 0.16
    static let mediumWeightTrait: CGFloat = 0.23
    static let outlineColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
    static let shadowColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
    static let defaultFillColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    static let settingsChangedNotification = Notification.Name(
        kMACaptionAppearanceSettingsChangedNotification as String
    )

    var relativeCharacterSize: CGFloat
    var edgeShadow: EdgeShadow
    var fillColor: CGColor
    var fontDescriptor: CTFontDescriptor?

    init(
        relativeCharacterSize: CGFloat = 1,
        edgeShadow: EdgeShadow = .none,
        fillColor: CGColor = CoreTextSubtitleStyle.defaultFillColor,
        fontDescriptor: CTFontDescriptor? = nil
    ) {
        self.relativeCharacterSize = relativeCharacterSize
        self.edgeShadow = edgeShadow
        self.fillColor = fillColor
        self.fontDescriptor = fontDescriptor
    }

    static func captionAppearance() -> CoreTextSubtitleStyle {
        var behavior = MACaptionAppearanceBehavior.useValue
        let characterSize = MACaptionAppearanceGetRelativeCharacterSize(.user, &behavior)
        let edgeStyle = MACaptionAppearanceGetTextEdgeStyle(.user, &behavior)
        let foreground = MACaptionAppearanceCopyForegroundColor(.user, &behavior)
            .takeRetainedValue()
        let opacity = MACaptionAppearanceGetForegroundOpacity(.user, &behavior)
        let descriptor = MACaptionAppearanceCopyFontDescriptorForStyle(
            .user,
            &behavior,
            .default
        ).takeRetainedValue()
        let fill = opacity > 0 && opacity < 1 ? foreground.copy(alpha: opacity) : foreground
        return CoreTextSubtitleStyle(
            relativeCharacterSize: characterSize.isFinite && characterSize > 0 ? characterSize : 1,
            edgeShadow: Self.edgeShadow(for: edgeStyle),
            fillColor: fill ?? defaultFillColor,
            fontDescriptor: descriptor
        )
    }

    static func edgeShadow(for edgeStyle: MACaptionAppearanceTextEdgeStyle) -> EdgeShadow {
        switch edgeStyle {
        case .raised: .raised
        case .depressed: .depressed
        case .dropShadow: .dropShadow
        default: .none
        }
    }

    static func horizontalMargin(canvasWidth: Int) -> CGFloat {
        CGFloat(canvasWidth) * marginFraction
    }

    static func bottomMargin(canvasHeight: Int) -> CGFloat {
        CGFloat(canvasHeight) * marginFraction
    }

    func emSize(canvasHeight: Int) -> CGFloat {
        CGFloat(canvasHeight) * Self.emFraction * relativeCharacterSize
    }

    func lineAdvance(emSize: CGFloat) -> CGFloat {
        emSize * Self.lineAdvanceEmMultiple
    }

    func outlineWidth(emSize: CGFloat) -> CGFloat {
        emSize * Self.outlineEmFraction
    }

    func shadowOffset(emSize: CGFloat) -> CGSize? {
        let distance = emSize * Self.shadowOffsetEmFraction
        switch edgeShadow {
        case .none: return nil
        case .raised: return CGSize(width: -distance, height: distance)
        case .depressed: return CGSize(width: distance, height: -distance)
        case .dropShadow: return CGSize(width: 0, height: -distance)
        }
    }

    func shadowBlur(emSize: CGFloat) -> CGFloat {
        edgeShadow == .none ? 0 : emSize * Self.shadowBlurEmFraction
    }

    func shadowExtent(emSize: CGFloat) -> CGFloat {
        edgeShadow == .none
            ? 0
            : emSize * (Self.shadowOffsetEmFraction + Self.shadowBlurEmFraction)
    }

    func font(emSize: CGFloat) -> CTFont {
        if let fontDescriptor {
            return CTFontCreateWithFontDescriptor(fontDescriptor, emSize, nil)
        }
        let system = CTFontCreateUIFontForLanguage(.system, emSize, nil)
            ?? CTFontCreateWithName("Helvetica Neue" as CFString, emSize, nil)
        let traits: [CFString: Any] = [kCTFontWeightTrait: Self.mediumWeightTrait]
        let medium = CTFontDescriptorCreateWithAttributes(
            [kCTFontTraitsAttribute: traits] as CFDictionary
        )
        return CTFontCreateCopyWithAttributes(system, emSize, nil, medium)
    }
}
