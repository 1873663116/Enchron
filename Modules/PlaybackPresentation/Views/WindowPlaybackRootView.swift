import DesignSystem
import PlaybackFeature
import PlaybackPresentation
import SwiftUI
import UIKit

struct WindowPlaybackLayout: Equatable {
    static let fallbackAspectRatio: CGFloat = 16.0 / 9.0
    static let fallback = WindowPlaybackLayout(aspectRatio: fallbackAspectRatio)

    /// The control bar hangs below the window at a fixed 728pt, so a narrower
    /// window would wear a bar wider than itself.
    static let minimumWidth: CGFloat = 750
    /// One ceiling for both axes, so a very tall video and a very flat one are
    /// bounded by the same number.
    static let maximumExtent: CGFloat = 1_808

    private static let minimumArea: CGFloat = 912 * 513
    private static let defaultArea: CGFloat = 1_280 * 720
    private static let maximumArea: CGFloat = 1_808 * 1_017

    let aspectRatio: CGFloat

    init(aspectRatio: CGFloat) {
        self.aspectRatio = aspectRatio.isFinite && aspectRatio > 0
            ? aspectRatio
            : Self.fallbackAspectRatio
    }

    init(
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

    var minimumSize: CGSize { size(area: Self.minimumArea) }

    var defaultSize: CGSize { size(area: Self.defaultArea) }

    var maximumSize: CGSize { size(area: Self.maximumArea) }

    func hasPlaybackAspectRatio(
        _ size: CGSize,
        tolerance: CGFloat = 0.001
    ) -> Bool {
        guard size.width > 0, size.height > 0 else { return false }
        return abs(size.width / size.height - aspectRatio) <= tolerance
    }

    func contains(_ size: CGSize, tolerance: CGFloat = 0.5) -> Bool {
        size.width >= minimumSize.width - tolerance
            && size.height >= minimumSize.height - tolerance
            && size.width <= maximumSize.width + tolerance
            && size.height <= maximumSize.height + tolerance
    }

    /// Each tier is a target area, not a bounding box. A box carries a shape of
    /// its own and starves whatever does not share it, which is how a
    /// side-by-side override on a mono source used to ask for a window
    /// thousands of points tall. Height is always taken from the width and the
    /// video's own ratio, and both clamps scale the whole rectangle, so the
    /// window can never disagree with the picture and earn a band of empty
    /// glass.
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

/// The window range the browser asks for. It has no video to match, so its
/// shape is fixed at 4:3 and owes nothing to playback's.
enum BrowserWindowLayout {
    static let minimumSize = CGSize(width: 912, height: 684)
    static let defaultSize = CGSize(width: 1_280, height: 960)
    static let maximumSize = CGSize(width: 1_808, height: 1_356)
}

extension View {
    /// Every surface that can own the window states its own range. None of them restores a system
    /// default on the way out, so the order in which one surface disappears and the next appears
    /// cannot leave the window unconstrained.
    func browserWindowGeometry() -> some View {
        background {
            WindowPlaybackSceneReader { windowScene in
                guard let windowScene else { return }
                windowScene.requestGeometryUpdate(
                    UIWindowScene.GeometryPreferences.Vision(
                        minimumSize: BrowserWindowLayout.minimumSize,
                        maximumSize: BrowserWindowLayout.maximumSize,
                        resizingRestrictions: .freeform
                    )
                )
            }
        }
    }
}

enum PortalWindowLayout {
    static let minimumSize = WindowPlaybackLayout.fallback.minimumSize
    static let defaultSize = WindowPlaybackLayout.fallback.defaultSize
    static let maximumSize = WindowPlaybackLayout.fallback.maximumSize

    static func contains(_ size: CGSize) -> Bool {
        size.width >= minimumSize.width
            && size.height >= minimumSize.height
            && size.width <= maximumSize.width
            && size.height <= maximumSize.height
    }
}

enum WindowPlaybackGeometryPolicy: Equatable {
    case aspectLocked(WindowPlaybackLayout)
    case freeform(
        defaultSize: CGSize,
        minimumSize: CGSize,
        maximumSize: CGSize
    )

    init(
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

    var minimumSize: CGSize? {
        switch self {
        case let .aspectLocked(layout): layout.minimumSize
        case let .freeform(_, minimumSize, _): minimumSize
        }
    }

    var idealSize: CGSize? {
        switch self {
        case let .aspectLocked(layout): layout.defaultSize
        case let .freeform(defaultSize, _, _): defaultSize
        }
    }

    var maximumSize: CGSize? {
        switch self {
        case let .aspectLocked(layout): layout.maximumSize
        case let .freeform(_, _, maximumSize): maximumSize
        }
    }
}

enum WindowPlaybackGeometryRefreshEvent: Equatable {
    case requested(revision: UInt64, size: CGSize)
    case failed(revision: UInt64, message: String)
}

struct WindowPlaybackTopChrome<
    NavigationControl: View,
    SpatialActions: View,
    MoreControl: View
>: View {
    private let navigationControl: NavigationControl
    private let spatialActions: SpatialActions
    private let moreControl: MoreControl

    init(
        @ViewBuilder navigationControl: () -> NavigationControl,
        @ViewBuilder spatialActions: () -> SpatialActions,
        @ViewBuilder moreControl: () -> MoreControl
    ) {
        self.navigationControl = navigationControl()
        self.spatialActions = spatialActions()
        self.moreControl = moreControl()
    }

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
            navigationControl
            spatialActions
                .frame(maxWidth: .infinity)
            moreControl
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
            Spacer(minLength: DesignTokens.Spacing.xl)
            formatControl
        }
    }
}

/// The production composition for playback inside a system-owned window.
///
/// The App owns the `Window` scene and injects live content. DesignPreview
/// injects deterministic fixtures into this same composition.
struct WindowPlaybackRootView<
    VideoContent: View,
    TopChrome: View
>: View {
    @State private var owningWindowScene: UIWindowScene?
    @State private var lastGeometryRefreshRevision: UInt64 = 0
    private let geometryPolicy: WindowPlaybackGeometryPolicy
    private let geometryRefreshRevision: UInt64
    private let preferredInitialSize: CGSize?
    private let freeformSizeOnDisappear: @MainActor () -> CGSize?
    private let showsWindowChrome: Bool
    private let hidesSurfaceFromAccessibility: Bool
    private let onSurfaceTap: (() -> Void)?
    private let onWindowSceneChange: (@MainActor (UIWindowScene?) -> Void)?
    private let onGeometryRefresh: @MainActor (WindowPlaybackGeometryRefreshEvent) -> Void
    private let videoContent: VideoContent
    private let topChrome: TopChrome

    init(
        geometryPolicy: WindowPlaybackGeometryPolicy,
        geometryRefreshRevision: UInt64 = 0,
        preferredInitialSize: CGSize? = nil,
        freeformSizeOnDisappear: @escaping @MainActor () -> CGSize? = { nil },
        showsWindowChrome: Bool,
        hidesSurfaceFromAccessibility: Bool = false,
        onSurfaceTap: (() -> Void)? = nil,
        onWindowSceneChange: (@MainActor (UIWindowScene?) -> Void)? = nil,
        onGeometryRefresh: @escaping @MainActor (
            WindowPlaybackGeometryRefreshEvent
        ) -> Void = { _ in },
        @ViewBuilder videoContent: () -> VideoContent,
        @ViewBuilder topChrome: () -> TopChrome
    ) {
        self.geometryPolicy = geometryPolicy
        self.geometryRefreshRevision = geometryRefreshRevision
        self.preferredInitialSize = preferredInitialSize
        self.freeformSizeOnDisappear = freeformSizeOnDisappear
        self.showsWindowChrome = showsWindowChrome
        self.hidesSurfaceFromAccessibility = hidesSurfaceFromAccessibility
        self.onSurfaceTap = onSurfaceTap
        self.onWindowSceneChange = onWindowSceneChange
        self.onGeometryRefresh = onGeometryRefresh
        self.videoContent = videoContent()
        self.topChrome = topChrome()
    }

    var body: some View {
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
            .overlay {
                if showsWindowChrome {
                    edgeEmphasis
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .top) {
                if showsWindowChrome {
                    topChromePlane
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("WindowPlayback-root")
    }

    /// Window presentation assigns direct surface input to the video layer.
    /// The top chrome occupies only the height of its controls and any visible
    /// secondary menu, leaving the remaining video area to that surface owner.
    private var topChromePlane: some View {
        topChrome
            .padding(.horizontal, DesignTokens.Spacing.xl)
            .padding(.top, DesignTokens.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .top)
            .zIndex(2)
            .transition(.opacity)
    }

    @ViewBuilder
    private var surfaceContent: some View {
        if let onSurfaceTap {
            ZStack {
                // Window owns surface taps in SwiftUI. The RealityView must not
                // compete for gaze + pinch, or the clear hit layer never fires.
                videoContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    // Padding remains part of a SwiftUI view's content shape.
                    // A separate non-interactive band is required so chrome
                    // and its secondary panel are genuinely outside the
                    // playback-surface hit region.
                    Color.clear
                        .frame(height: surfaceTapTopInset)
                        .allowsHitTesting(false)

                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(
                            SpatialTapGesture()
                                .onEnded { _ in onSurfaceTap() }
                        )
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel("Playback surface")
                        .accessibilityIdentifier("PlayerUI-window-playback-surface")
                        .accessibilityAction {
                            onSurfaceTap()
                        }
                        // An open secondary menu owns Accessibility interaction
                        // in its visible bounds. The spatial tap layer remains
                        // active outside the menu and returns to the tree when
                        // the menu closes.
                        .accessibilityHidden(hidesSurfaceFromAccessibility)
                }
            }
        } else {
            videoContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The playback surface begins below the stable button row. Secondary
    /// panels render above it and own their complete hit shapes, so opening a
    /// panel never changes the surface region or rebuilds the top controls.
    private var surfaceTapTopInset: CGFloat {
        guard showsWindowChrome else { return 0 }
        return DesignTokens.Spacing.lg + DesignTokens.Interactive.large
    }

    private var edgeEmphasis: some View {
        VStack(spacing: 0) {
            PlaybackEdgeEmphasis(.top)
            Spacer(minLength: 0)
            PlaybackEdgeEmphasis(.bottom)
        }
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
        case let .freeform(defaultSize, minimumSize, maximumSize):
            return freeformWindowGeometryPreferences(
                size: size ?? defaultSize,
                minimumSize: minimumSize,
                maximumSize: maximumSize
            )
        }
    }

    private func restoreFreeformWindowGeometry(
        in windowScene: UIWindowScene?,
        size: CGSize?
    ) {
        guard let windowScene else { return }
        windowScene.requestGeometryUpdate(
            freeformWindowGeometryPreferences(size: size)
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
            resizingRestrictions: .freeform
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
