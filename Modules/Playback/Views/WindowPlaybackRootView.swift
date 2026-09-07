import DesignSystem
import SwiftUI
import UIKit

public struct WindowPlaybackLayout: Equatable {
    public static let fallbackAspectRatio: CGFloat = 16.0 / 9.0
    public static let fallback = WindowPlaybackLayout(aspectRatio: fallbackAspectRatio)

    static let minimumWidth: CGFloat = 750
    static let maximumExtent: CGFloat = 1_808

    private static let minimumArea: CGFloat = 912 * 513
    private static let defaultArea: CGFloat = 1_280 * 720
    private static let maximumArea: CGFloat = 1_808 * 1_017

    public let aspectRatio: CGFloat

    public init(aspectRatio: CGFloat) {
        self.aspectRatio = aspectRatio.isFinite && aspectRatio > 0
            ? aspectRatio
            : Self.fallbackAspectRatio
    }

    public init(
        resolution: PlaybackModel.MediaProfile.Resolution?,
        pixelAspectRatio: PlaybackModel.MediaProfile.PixelAspectRatio = .square,
        stereoLayout: PlaybackModel.StereoLayout
    ) {
        guard let resolution else {
            self.init(aspectRatio: Self.fallbackAspectRatio)
            return
        }
        let dimensions = stereoLayout.outputDisplayDimensions(
            inputWidth: resolution.width,
            inputHeight: resolution.height,
            pixelAspectRatio: pixelAspectRatio
        )
        guard dimensions.width > 0, dimensions.height > 0 else {
            self.init(aspectRatio: Self.fallbackAspectRatio)
            return
        }
        self.init(
            aspectRatio: CGFloat(dimensions.width) / CGFloat(dimensions.height)
        )
    }

    public var minimumSize: CGSize { size(area: Self.minimumArea) }

    public var defaultSize: CGSize { size(area: Self.defaultArea) }

    public var maximumSize: CGSize { size(area: Self.maximumArea) }

    func hasPlaybackAspectRatio(
        _ size: CGSize,
        tolerance: CGFloat = 0.001
    ) -> Bool {
        guard size.width > 0, size.height > 0 else { return false }
        return abs(size.width / size.height - aspectRatio) <= tolerance
    }

    public func contains(_ size: CGSize, tolerance: CGFloat = 0.5) -> Bool {
        size.width >= minimumSize.width - tolerance
            && size.height >= minimumSize.height - tolerance
            && size.width <= maximumSize.width + tolerance
            && size.height <= maximumSize.height + tolerance
    }

    private func size(area: CGFloat) -> CGSize {
        let width = (area * aspectRatio).squareRoot().rounded()
        return withinCeiling(atLeastMinimumWidth(sizeFrom(width: width)))
    }

    private func sizeFrom(width: CGFloat) -> CGSize {
        CGSize(width: width, height: width / aspectRatio)
    }

    private func atLeastMinimumWidth(_ size: CGSize) -> CGSize {
        guard size.width < Self.minimumWidth else { return size }
        return sizeFrom(width: Self.minimumWidth)
    }

    private func withinCeiling(_ size: CGSize) -> CGSize {
        let extent = max(size.width, size.height)
        guard extent > Self.maximumExtent else { return size }
        return sizeFrom(width: size.width * Self.maximumExtent / extent)
    }
}

public enum BrowserWindowLayout {
    static let minimumSize = CGSize(width: 1_088, height: 612)
    public static let defaultSize = CGSize(width: 1_536, height: 864)
    static let maximumSize = CGSize(width: 1_808, height: 1_017)
}

extension View {
    public func windowSceneReporting(
        _ onWindowSceneChange: @escaping @MainActor (UIWindowScene?) -> Void
    ) -> some View {
        background {
            WindowPlaybackSceneReader(onChange: onWindowSceneChange)
        }
    }

    public func browserWindowGeometry(
        onWindowSceneChange: (@MainActor (UIWindowScene?) -> Void)? = nil
    ) -> some View {
        background {
            WindowPlaybackSceneReader { windowScene in
                onWindowSceneChange?(windowScene)
                guard let windowScene else { return }
                windowScene.requestGeometryUpdate(
                    UIWindowScene.GeometryPreferences.Vision(
                        minimumSize: BrowserWindowLayout.minimumSize,
                        maximumSize: BrowserWindowLayout.maximumSize,
                        resizingRestrictions: .uniform
                    )
                )
            }
        }
    }
}

public struct WindowPlaybackGeometryDiagnosticSnapshot: Equatable, Sendable {
    public enum PolicyKind: String, Equatable, Sendable {
        case aspectLocked
        case audioOnly
    }

    public enum ResizingRestriction: String, Equatable, Sendable {
        case uniform
    }

    public let policyKind: PolicyKind
    public let requestedIdealWidth: CGFloat
    public let requestedIdealHeight: CGFloat
    public let minimumWidth: CGFloat
    public let minimumHeight: CGFloat
    public let maximumWidth: CGFloat
    public let maximumHeight: CGFloat
    public let resizingRestriction: ResizingRestriction

    public var accessibilityFields: [String] {
        [
            "windowGeometryPolicyKind=\(policyKind.rawValue)",
            "windowGeometryRequestedIdealWidth=\(requestedIdealWidth)",
            "windowGeometryRequestedIdealHeight=\(requestedIdealHeight)",
            "windowGeometryMinimumWidth=\(minimumWidth)",
            "windowGeometryMinimumHeight=\(minimumHeight)",
            "windowGeometryMaximumWidth=\(maximumWidth)",
            "windowGeometryMaximumHeight=\(maximumHeight)",
            "windowGeometryResizingRestriction=\(resizingRestriction.rawValue)"
        ]
    }

    fileprivate var requestedIdealSize: CGSize {
        CGSize(width: requestedIdealWidth, height: requestedIdealHeight)
    }

    fileprivate var minimumSize: CGSize {
        CGSize(width: minimumWidth, height: minimumHeight)
    }

    fileprivate var maximumSize: CGSize {
        CGSize(width: maximumWidth, height: maximumHeight)
    }
}

public enum WindowPlaybackGeometryPolicy: Equatable {
    case aspectLocked(WindowPlaybackLayout)
    case audioOnly

    public init(
        presentation: PlaybackPresentation,
        videoLayout: WindowPlaybackLayout
    ) {
        switch presentation {
        case .portal:
            self = .aspectLocked(.fallback)
        case .window, .docked, .panorama:
            self = .aspectLocked(videoLayout)
        }
    }

    public var diagnosticSnapshot: WindowPlaybackGeometryDiagnosticSnapshot {
        let policyKind: WindowPlaybackGeometryDiagnosticSnapshot.PolicyKind
        let minimumSize: CGSize
        let idealSize: CGSize
        let maximumSize: CGSize
        switch self {
        case let .aspectLocked(layout):
            policyKind = .aspectLocked
            minimumSize = layout.minimumSize
            idealSize = layout.defaultSize
            maximumSize = layout.maximumSize
        case .audioOnly:
            policyKind = .audioOnly
            minimumSize = CGSize(width: 750, height: 380)
            idealSize = CGSize(width: 800, height: 450)
            maximumSize = CGSize(width: 960, height: 540)
        }
        return WindowPlaybackGeometryDiagnosticSnapshot(
            policyKind: policyKind,
            requestedIdealWidth: idealSize.width,
            requestedIdealHeight: idealSize.height,
            minimumWidth: minimumSize.width,
            minimumHeight: minimumSize.height,
            maximumWidth: maximumSize.width,
            maximumHeight: maximumSize.height,
            resizingRestriction: .uniform
        )
    }

    var minimumSize: CGSize? {
        diagnosticSnapshot.minimumSize
    }

    var idealSize: CGSize? {
        diagnosticSnapshot.requestedIdealSize
    }

    var maximumSize: CGSize? {
        diagnosticSnapshot.maximumSize
    }
}

public enum WindowPlaybackGeometryRefreshEvent: Equatable {
    case requested(revision: UInt64, size: CGSize)
    case failed(revision: UInt64, message: String)
}

public struct WindowPlaybackTopChrome<
    NavigationControl: View,
    SpatialActions: View,
    MoreControl: View
>: View {
    private let navigationControl: NavigationControl
    private let spatialActions: SpatialActions
    private let moreControl: MoreControl

    public init(
        @ViewBuilder navigationControl: () -> NavigationControl,
        @ViewBuilder spatialActions: () -> SpatialActions,
        @ViewBuilder moreControl: () -> MoreControl
    ) {
        self.navigationControl = navigationControl()
        self.spatialActions = spatialActions()
        self.moreControl = moreControl()
    }

    public var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
            navigationControl
                .enchronSpatialFrame(depth: 0)
                .enchronSpatialOffset(
                    z: WindowPlaybackSurfaceGeometry.coincidentChromeDepth
                )
            spatialActions
                .frame(maxWidth: .infinity)
            moreControl
                .enchronSpatialFrame(depth: 0)
                .enchronSpatialOffset(
                    z: WindowPlaybackSurfaceGeometry.coincidentChromeDepth
                )
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .zIndex(1)
    }
}

struct WindowPlaybackSpatialActions<
    DockControl: View,
    FormatControl: View
>: View {
    private let dockControl: DockControl
    private let formatControl: FormatControl

    init(
        @ViewBuilder dockControl: () -> DockControl,
        @ViewBuilder formatControl: () -> FormatControl
    ) {
        self.dockControl = dockControl()
        self.formatControl = formatControl()
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            dockControl
                .enchronSpatialFrame(depth: 0)
                .enchronSpatialOffset(
                    z: WindowPlaybackSurfaceGeometry.coincidentChromeDepth
                )
            Spacer(minLength: DesignTokens.Spacing.xl)
            formatControl
                .enchronSpatialFrame(depth: 0)
                .enchronSpatialOffset(
                    z: WindowPlaybackSurfaceGeometry.coincidentChromeDepth
                )
        }
    }
}

public struct WindowPlaybackRootView<
    VideoContent: View,
    TopChrome: View
>: View {
    @State private var owningWindowScene: UIWindowScene?
    @State private var lastGeometryRefreshRevision: UInt64 = 0
    @State private var surfaceHeight: CGFloat = 0
    @State private var topChromeHeight: CGFloat = 0
    private let geometryPolicy: WindowPlaybackGeometryPolicy
    private let geometryRefreshRevision: UInt64
    private let preferredInitialSize: CGSize?
    private let freeformSizeOnDisappear: @MainActor () -> CGSize?
    private let showsWindowChrome: Bool
    private let onWindowSceneChange: (@MainActor (UIWindowScene?) -> Void)?
    private let onGeometryRefresh: @MainActor (WindowPlaybackGeometryRefreshEvent) -> Void
    private let onTopChromeOcclusionChange: (@MainActor (Float) -> Void)?
    private let onSurfaceHeightChange: (@MainActor (CGFloat) -> Void)?
    private let videoContent: VideoContent
    private let topChrome: TopChrome

    public init(
        geometryPolicy: WindowPlaybackGeometryPolicy,
        geometryRefreshRevision: UInt64 = 0,
        preferredInitialSize: CGSize? = nil,
        freeformSizeOnDisappear: @escaping @MainActor () -> CGSize? = { nil },
        showsWindowChrome: Bool,
        onWindowSceneChange: (@MainActor (UIWindowScene?) -> Void)? = nil,
        onGeometryRefresh: @escaping @MainActor (
            WindowPlaybackGeometryRefreshEvent
        ) -> Void = { _ in },
        onTopChromeOcclusionChange: (@MainActor (Float) -> Void)? = nil,
        onSurfaceHeightChange: (@MainActor (CGFloat) -> Void)? = nil,
        @ViewBuilder videoContent: () -> VideoContent,
        @ViewBuilder topChrome: () -> TopChrome
    ) {
        self.geometryPolicy = geometryPolicy
        self.geometryRefreshRevision = geometryRefreshRevision
        self.preferredInitialSize = preferredInitialSize
        self.freeformSizeOnDisappear = freeformSizeOnDisappear
        self.showsWindowChrome = showsWindowChrome
        self.onWindowSceneChange = onWindowSceneChange
        self.onGeometryRefresh = onGeometryRefresh
        self.onTopChromeOcclusionChange = onTopChromeOcclusionChange
        self.onSurfaceHeightChange = onSurfaceHeightChange
        self.videoContent = videoContent()
        self.topChrome = topChrome()
    }

    public var body: some View {
        layeredContent
            .frame(
                minWidth: geometryPolicy.minimumSize?.width,
                idealWidth: geometryPolicy.idealSize?.width,
                maxWidth: geometryPolicy.maximumSize?.width,
                minHeight: geometryPolicy.minimumSize?.height,
                idealHeight: geometryPolicy.idealSize?.height,
                maxHeight: geometryPolicy.maximumSize?.height
            )
            .background {
                WindowPlaybackSceneReader { windowScene in
                    guard owningWindowScene !== windowScene else { return }
                    owningWindowScene = windowScene
                    onWindowSceneChange?(windowScene)
                    updateWindowGeometry(in: windowScene)
                    requestGeometryRefreshIfNeeded(in: windowScene)
                }
            }
            .onChange(of: geometryPolicy) { _, _ in
                updateWindowGeometry(in: owningWindowScene)
            }
            .onChange(of: geometryRefreshRevision) { _, _ in
                requestGeometryRefreshIfNeeded(in: owningWindowScene)
            }
            .onDisappear {
                restoreFreeformWindowGeometry(
                    in: owningWindowScene,
                    size: freeformSizeOnDisappear()
                )
            }
    }

    private var layeredContent: some View {
        surfaceContent
            .overlay(alignment: .top) {
                edgeEmphasis
                    .opacity(showsWindowChrome ? 1 : 0)
                    .animation(
                        DesignTokens.AnimationToken.controlsTransition,
                        value: showsWindowChrome
                    )
            }
            .overlay(alignment: .top) {
                topChromePlane
                    .opacity(showsWindowChrome ? 1 : 0)
                    .animation(
                        DesignTokens.AnimationToken.controlsTransition,
                        value: showsWindowChrome
                    )
                    .allowsHitTesting(showsWindowChrome)
                    .accessibilityHidden(!showsWindowChrome)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                surfaceHeight = $0
                onSurfaceHeightChange?($0)
            }
            .onChange(of: topChromeOcclusionFraction, initial: true) { _, fraction in
                onTopChromeOcclusionChange?(fraction)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("WindowPlayback-root")
    }

    private var topChromeOcclusionFraction: Float {
        guard showsWindowChrome,
              surfaceHeight > 0,
              topChromeHeight > 0 else {
            return 0
        }
        return Float(min(topChromeHeight / surfaceHeight, 1))
    }

    private var topChromePlane: some View {
        topChrome
            .padding(.horizontal, DesignTokens.Spacing.xl)
            .padding(.top, DesignTokens.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .top)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                topChromeHeight = $0
            }
            .zIndex(2)
    }

    private var surfaceContent: some View {
        videoContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("PlayerUI-window-playback-surface")
    }

    private var edgeEmphasis: some View {
        PlaybackEdgeEmphasis()
            .enchronSpatialFrame(depth: 0)
            .enchronSpatialOffset(
                z: WindowPlaybackSurfaceGeometry.coincidentChromeDepth
            )
            .allowsHitTesting(false)
    }

    private func updateWindowGeometry(in windowScene: UIWindowScene?) {
        guard let windowScene else { return }
        windowScene.requestGeometryUpdate(
            windowGeometryPreferences(size: nil)
        )
    }

    private func requestGeometryRefreshIfNeeded(in windowScene: UIWindowScene?) {
        guard geometryRefreshRevision > lastGeometryRefreshRevision,
              let windowScene else { return }
        let revision = geometryRefreshRevision
        let size = windowScene.effectiveGeometry.coordinateSpace.bounds.size
        lastGeometryRefreshRevision = revision
        onGeometryRefresh(.requested(revision: revision, size: size))
        windowScene.requestGeometryUpdate(
            windowGeometryPreferences(size: size)
        ) { error in
            Task { @MainActor in
                onGeometryRefresh(
                    .failed(
                        revision: revision,
                        message: error.localizedDescription
                    )
                )
            }
        }
    }

    private func windowGeometryPreferences(
        size: CGSize?
    ) -> UIWindowScene.GeometryPreferences.Vision {
        switch geometryPolicy {
        case let .aspectLocked(layout):
            return UIWindowScene.GeometryPreferences.Vision(
                size: size ?? preferredInitialSize ?? layout.defaultSize,
                minimumSize: layout.minimumSize,
                maximumSize: layout.maximumSize,
                resizingRestrictions: .uniform
            )
        case .audioOnly:
            return UIWindowScene.GeometryPreferences.Vision(
                size: size ?? preferredInitialSize ?? geometryPolicy.idealSize,
                minimumSize: geometryPolicy.minimumSize,
                maximumSize: geometryPolicy.maximumSize,
                resizingRestrictions: .uniform
            )
        }
    }

    private func restoreFreeformWindowGeometry(
        in windowScene: UIWindowScene?,
        size: CGSize?
    ) {
        guard let windowScene else { return }
        windowScene.requestGeometryUpdate(
            freeformWindowGeometryPreferences(
                size: size,
                minimumSize: size == nil ? nil : BrowserWindowLayout.minimumSize,
                maximumSize: size == nil ? nil : BrowserWindowLayout.maximumSize
            )
        )
    }

    private func freeformWindowGeometryPreferences(
        size: CGSize?,
        minimumSize: CGSize? = nil,
        maximumSize: CGSize? = nil
    ) -> UIWindowScene.GeometryPreferences.Vision {
        let systemDefault = CGSize(
            width: UIProposedSceneSizeNoPreference,
            height: UIProposedSceneSizeNoPreference
        )
        return UIWindowScene.GeometryPreferences.Vision(
            size: size,
            minimumSize: minimumSize ?? systemDefault,
            maximumSize: maximumSize ?? systemDefault,
            resizingRestrictions: .uniform
        )
    }
}

struct WindowPlaybackSceneReader: UIViewRepresentable {
    let onChange: @MainActor (UIWindowScene?) -> Void

    func makeUIView(context: Context) -> WindowPlaybackSceneReportingView {
        WindowPlaybackSceneReportingView(onChange: onChange)
    }

    func updateUIView(
        _ uiView: WindowPlaybackSceneReportingView,
        context: Context
    ) {
        uiView.onChange = onChange
        uiView.reportOwningScene()
    }
}

final class WindowPlaybackSceneReportingView: UIView {
    var onChange: @MainActor (UIWindowScene?) -> Void
    private weak var reportedScene: UIWindowScene?

    init(onChange: @escaping @MainActor (UIWindowScene?) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        reportOwningScene()
    }

    func reportOwningScene() {
        let nextScene = window?.windowScene
        guard reportedScene !== nextScene else { return }
        reportedScene = nextScene
        onChange(nextScene)
    }
}
