import SwiftUI
import UIKit

/// Maps a point in the stream window onto the picture, so every gesture speaks
/// the same normalized coordinates the host expects.
enum StreamVideoGeometry {
    static func normalized(
        location: CGPoint,
        in size: CGSize,
        videoAspectRatio: CGFloat
    ) -> CGPoint? {
        guard size.width > 0, size.height > 0, videoAspectRatio > 0 else { return nil }
        let fitted: CGSize
        if size.width / size.height > videoAspectRatio {
            fitted = CGSize(width: size.height * videoAspectRatio, height: size.height)
        } else {
            fitted = CGSize(width: size.width, height: size.width / videoAspectRatio)
        }
        let origin = CGPoint(
            x: (size.width - fitted.width) / 2,
            y: (size.height - fitted.height) / 2
        )
        let x = (location.x - origin.x) / fitted.width
        let y = (location.y - origin.y) / fitted.height
        guard x >= 0, x <= 1, y >= 0, y <= 1 else { return nil }
        return CGPoint(x: x, y: y)
    }
}

/// Touch and trackpad gestures for the window picture.
///
/// A one finger drag moves the pointer, two fingers scroll, a long press holds
/// the right button, a double tap clicks twice, a pinch scales the picture and
/// an attached trackpad scrolls at high resolution. The recognizers live in
/// UIKit because the scroll types and the multi-touch counts the host needs are
/// not expressible as SwiftUI gestures.
public struct StreamTouchGestureSurface: UIViewRepresentable {
    public struct Configuration {
        public var absoluteTouchMode: Bool
        public var videoAspectRatio: CGFloat
        public var currentZoom: CGFloat
        public var onMove: (CGPoint) -> Void
        public var onRelativeMove: (CGFloat, CGFloat) -> Void
        public var onClick: (CGPoint) -> Void
        public var onRightButton: (Bool) -> Void
        public var onScroll: (Int32, Int32) -> Void
        public var onMagnify: (CGFloat) -> Void

        public init(
            absoluteTouchMode: Bool,
            videoAspectRatio: CGFloat,
            currentZoom: CGFloat,
            onMove: @escaping (CGPoint) -> Void,
            onRelativeMove: @escaping (CGFloat, CGFloat) -> Void,
            onClick: @escaping (CGPoint) -> Void,
            onRightButton: @escaping (Bool) -> Void,
            onScroll: @escaping (Int32, Int32) -> Void,
            onMagnify: @escaping (CGFloat) -> Void
        ) {
            self.absoluteTouchMode = absoluteTouchMode
            self.videoAspectRatio = videoAspectRatio
            self.currentZoom = currentZoom
            self.onMove = onMove
            self.onRelativeMove = onRelativeMove
            self.onClick = onClick
            self.onRightButton = onRightButton
            self.onScroll = onScroll
            self.onMagnify = onMagnify
        }
    }

    private var configuration: Configuration

    public init(configuration: Configuration) {
        self.configuration = configuration
    }

    public func makeUIView(context: Context) -> StreamTouchGestureView {
        StreamTouchGestureView(configuration: configuration)
    }

    public func updateUIView(_ uiView: StreamTouchGestureView, context: Context) {
        uiView.configuration = configuration
    }
}

public final class StreamTouchGestureView: UIView {
    var configuration: StreamTouchGestureSurface.Configuration

    private var lastScrollTranslation = CGPoint.zero
    private var lastPanTranslation = CGPoint.zero
    private var accumulatedZoom: CGFloat = 1

    init(configuration: StreamTouchGestureSurface.Configuration) {
        self.configuration = configuration
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = true
        installRecognizers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func installRecognizers() {
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.require(toFail: doubleTap)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1

        let twoFingerScroll = UIPanGestureRecognizer(
            target: self,
            action: #selector(handleTouchScroll(_:))
        )
        twoFingerScroll.minimumNumberOfTouches = 2
        twoFingerScroll.maximumNumberOfTouches = 2

        let trackpadScroll = UIPanGestureRecognizer(
            target: self,
            action: #selector(handleTrackpadScroll(_:))
        )
        trackpadScroll.maximumNumberOfTouches = 0
        trackpadScroll.allowedScrollTypesMask = .continuous
        trackpadScroll.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]

        let discreteScroll = UIPanGestureRecognizer(
            target: self,
            action: #selector(handleDiscreteScroll(_:))
        )
        discreteScroll.maximumNumberOfTouches = 0
        discreteScroll.allowedScrollTypesMask = .discrete
        discreteScroll.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]

        let longPress = UILongPressGestureRecognizer(
            target: self,
            action: #selector(handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.55

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))

        for recognizer in [
            doubleTap, tap, pan, twoFingerScroll, trackpadScroll, discreteScroll, longPress, pinch
        ] {
            addGestureRecognizer(recognizer)
        }
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard let point = normalizedPoint(recognizer.location(in: self)) else { return }
        configuration.onClick(point)
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard let point = normalizedPoint(recognizer.location(in: self)) else { return }
        configuration.onClick(point)
        configuration.onClick(point)
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            lastPanTranslation = .zero
            if configuration.absoluteTouchMode,
               let point = normalizedPoint(recognizer.location(in: self)) {
                configuration.onMove(point)
            }
        case .changed:
            if configuration.absoluteTouchMode {
                if let point = normalizedPoint(recognizer.location(in: self)) {
                    configuration.onMove(point)
                }
            } else {
                let translation = recognizer.translation(in: self)
                let deltaX = translation.x - lastPanTranslation.x
                let deltaY = translation.y - lastPanTranslation.y
                guard deltaX != 0 || deltaY != 0 else { return }
                lastPanTranslation = translation
                configuration.onRelativeMove(deltaX, deltaY)
            }
        case .ended, .cancelled, .failed:
            lastPanTranslation = .zero
        default:
            break
        }
    }

    @objc private func handleTouchScroll(_ recognizer: UIPanGestureRecognizer) {
        let delta = scrollDelta(recognizer, scaledBy: 1)
        guard delta != .zero else { return }
        configuration.onScroll(Int32(-delta.y), Int32(-delta.x))
    }

    @objc private func handleTrackpadScroll(_ recognizer: UIPanGestureRecognizer) {
        let scale: CGFloat = 120 * 20
        let delta = scrollDelta(
            recognizer,
            scaledBy: bounds.size.height > 0 ? scale / bounds.size.height : 1
        )
        guard delta != .zero else { return }
        configuration.onScroll(Int32(delta.y), Int32(-delta.x))
    }

    @objc private func handleDiscreteScroll(_ recognizer: UIPanGestureRecognizer) {
        let delta = scrollDelta(recognizer, scaledBy: 1)
        guard delta != .zero else { return }
        configuration.onScroll(
            delta.y > 0 ? 120 : (delta.y < 0 ? -120 : 0),
            delta.x < 0 ? 120 : (delta.x > 0 ? -120 : 0)
        )
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            configuration.onRightButton(true)
        case .ended, .cancelled, .failed:
            configuration.onRightButton(false)
        default:
            break
        }
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began:
            accumulatedZoom = configuration.currentZoom
        case .changed:
            accumulatedZoom *= recognizer.scale
            recognizer.scale = 1
            configuration.onMagnify(accumulatedZoom)
        default:
            break
        }
    }

    private func scrollDelta(_ recognizer: UIPanGestureRecognizer, scaledBy scale: CGFloat) -> CGPoint {
        switch recognizer.state {
        case .began, .changed:
            break
        default:
            lastScrollTranslation = .zero
            return .zero
        }
        let current = recognizer.translation(in: self)
        let delta = CGPoint(
            x: (current.x - lastScrollTranslation.x) * scale,
            y: (current.y - lastScrollTranslation.y) * scale
        )
        if delta != .zero {
            lastScrollTranslation = current
        }
        return delta
    }

    private func normalizedPoint(_ location: CGPoint) -> CGPoint? {
        StreamVideoGeometry.normalized(
            location: location,
            in: bounds.size,
            videoAspectRatio: configuration.videoAspectRatio
        )
    }
}
