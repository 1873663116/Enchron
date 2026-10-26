import AVFoundation
import Observation
import SwiftUI
#if os(visionOS)
import AVKit
import UIKit
#endif

public enum PlaybackRefreshRatePolicy {
    public static func requestedHz(for frameRate: Double) -> Float {
        guard frameRate.isFinite, frameRate > 0 else { return 90 }
        let fractionalRates = [24.0, 30, 48, 60, 120]
        let fractionalNormalized = fractionalRates.first {
            abs(frameRate - $0 * 1000 / 1001) < 0.005
        } ?? frameRate
        let rounded = fractionalNormalized.rounded()
        let normalized = abs(fractionalNormalized - rounded) < 0.005 ? rounded : fractionalNormalized
        if normalized >= 120 { return 120 }
        return [90.0, 96, 100, 120].first {
            let multiple = $0 / normalized
            return abs(multiple - multiple.rounded()) < 0.0001
        }.map(Float.init) ?? 90
    }
}

@MainActor
@Observable
public final class PlaybackDisplayCriteria {
    public var isEnabled = true {
        didSet { apply() }
    }
    public private(set) var statusText = "Not requested"
    public private(set) var requestedHz: Float?
    public private(set) var matchingEnabled: Bool?
    @ObservationIgnored private var format: CMFormatDescription?
    @ObservationIgnored private var targetHz: Float?
    @ObservationIgnored private var sourceFrameRate: Double?
    @ObservationIgnored private var playbackHost: PlaybackHost?
#if os(visionOS)
    private struct Host {
        weak var window: UIWindow?
        let immersive: Bool
    }
    @ObservationIgnored private var hosts: [UUID: Host] = [:]
    @ObservationIgnored private var appliedManager: AVDisplayManager?
    @ObservationIgnored private var appliedFormat: CMFormatDescription?
    @ObservationIgnored private var reportedUnavailableManager = false
#endif

    public init() {}

    /// A streaming session has no decoded format of its own to hand over, so
    /// the profile it negotiated stands in for one. The display only needs to
    /// know which frame rate and colour space the content carries.
    func updateStream(frameRate: Double, hdr: Bool, width: Int, height: Int) {
        update(
            frameRate: frameRate,
            format: Self.streamFormat(hdr: hdr, width: width, height: height),
            host: .window
        )
    }

    private static func streamFormat(hdr: Bool, width: Int, height: Int) -> CMFormatDescription? {
        var extensions: [String: Any] = [:]
        if hdr {
            extensions[kCMFormatDescriptionExtension_ColorPrimaries as String] =
                kCMFormatDescriptionColorPrimaries_ITU_R_2020
            extensions[kCMFormatDescriptionExtension_TransferFunction as String] =
                kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ
            extensions[kCMFormatDescriptionExtension_YCbCrMatrix as String] =
                kCMFormatDescriptionYCbCrMatrix_ITU_R_2020
        }
        var format: CMFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCMVideoCodecType_HEVC,
            width: Int32(max(width, 2)),
            height: Int32(max(height, 2)),
            extensions: extensions.isEmpty ? nil : extensions as CFDictionary,
            formatDescriptionOut: &format
        )
        return status == noErr ? format : nil
    }

    func update(
        frameRate: Double, format: CMFormatDescription?, host: PlaybackHost = .window
    ) {
        playbackHost = host
        sourceFrameRate = frameRate
        self.format = format
        targetHz = PlaybackRefreshRatePolicy.requestedHz(for: frameRate)
        apply()
    }

    func clear() {
        format = nil
        targetHz = nil
        sourceFrameRate = nil
        playbackHost = nil
        apply()
    }

#if os(visionOS)
    func setWindow(_ window: UIWindow?, id: UUID, immersive: Bool) {
        if let window {
            hosts[id] = Host(window: window, immersive: immersive)
        } else {
            hosts.removeValue(forKey: id)
        }
        apply()
    }
#endif

    private func apply() {
#if os(visionOS)
        let host = hosts.values.first {
            $0.immersive == (playbackHost == .immersiveSpace) && $0.window != nil
        }
        guard isEnabled, let format, let targetHz else {
            statusText = !isEnabled ? "Off" : targetHz == nil ? "Not requested"
                : "Waiting for video"
            releaseRequest()
            return
        }
        guard let manager = host?.window?.playbackDisplayManager else {
            statusText = host == nil ? "Waiting for window" : "Unavailable"
            reportUnavailableManager(hasHost: host != nil)
            releaseRequest()
            return
        }
        reportedUnavailableManager = false
        statusText = "Submitted"
        matchingEnabled = manager.isDisplayCriteriaMatchingEnabled
        let sameFormat = appliedFormat.map {
            CMFormatDescriptionEqual($0, otherFormatDescription: format)
        } ?? false
        guard appliedManager !== manager || requestedHz != targetHz || !sameFormat else {
            return
        }
        appliedManager?.preferredDisplayCriteria = nil
        manager.preferredDisplayCriteria = AVDisplayCriteria(
            refreshRate: targetHz, formatDescription: format
        )
        appliedManager = manager
        appliedFormat = format
        requestedHz = targetHz
        SurfaceInputProbes.record(
            "displayCriteria requestedHz=\(targetHz)"
                + " sourceFrameRate=\(sourceFrameRate ?? 0)"
                + " matchingEnabled=\(matchingEnabled == true) immersive=\(host?.immersive == true)"
                + " playbackHost=\(playbackHost?.rawValue ?? "none")"
                + " requestReadbackPresent=\(manager.preferredDisplayCriteria != nil)",
            retention: .evidence
        )
#endif
    }

#if os(visionOS)
    private func releaseRequest() {
        if requestedHz != nil {
            SurfaceInputProbes.record("displayCriteria cleared", retention: .evidence)
        }
        appliedManager?.preferredDisplayCriteria = nil
        appliedManager = nil
        appliedFormat = nil
        requestedHz = nil
        matchingEnabled = nil
    }

    private func reportUnavailableManager(hasHost: Bool) {
        guard hasHost, reportedUnavailableManager == false else { return }
        reportedUnavailableManager = true
        SurfaceInputProbes.record(
            "displayCriteria unavailable windowSelector=avDisplayManager",
            retention: .evidence
        )
    }
#endif
}

#if os(visionOS)
private extension UIWindow {
    var playbackDisplayManager: AVDisplayManager? {
        let selector = NSSelectorFromString("avDisplayManager")
        guard responds(to: selector) else { return nil }
        return avDisplayManager
    }
}
#endif

#if os(visionOS)
private struct PlaybackDisplayCriteriaHost: UIViewRepresentable {
    let criteria: PlaybackDisplayCriteria
    let immersive: Bool

    func makeUIView(context: Context) -> HostView {
        HostView(criteria: criteria, immersive: immersive)
    }

    func updateUIView(_ view: HostView, context: Context) {}

    static func dismantleUIView(_ view: HostView, coordinator: ()) {
        view.criteria.setWindow(nil, id: view.id, immersive: view.immersive)
    }

    final class HostView: UIView {
        let id = UUID()
        let criteria: PlaybackDisplayCriteria
        let immersive: Bool

        init(criteria: PlaybackDisplayCriteria, immersive: Bool) {
            self.criteria = criteria
            self.immersive = immersive
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            criteria.setWindow(window, id: id, immersive: immersive)
        }
    }
}

public extension View {
    func playbackDisplayCriteriaHost(
        _ criteria: PlaybackDisplayCriteria, immersive: Bool = false
    ) -> some View {
        background {
            PlaybackDisplayCriteriaHost(criteria: criteria, immersive: immersive)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }
}
#endif
