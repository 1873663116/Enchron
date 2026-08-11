import DesignSystem
import PlaybackFeature
import SwiftUI
import UIKit

struct WindowPlaybackLayout: Equatable {
    static let fallbackAspectRatio: CGFloat = 16.0 / 9.0
    static let minimumWidthMultiplier: CGFloat = 1.25
    static let defaultWidthMultiplier: CGFloat = 1.75
    static let maximumWidthMultiplier: CGFloat = 2.50
    static let fallback = WindowPlaybackLayout(aspectRatio: fallbackAspectRatio)

    let aspectRatio: CGFloat

    init(aspectRatio: CGFloat) {
        self.aspectRatio = aspectRatio.isFinite && aspectRatio > 0
            ? aspectRatio
            : Self.fallbackAspectRatio
    }

    init(
        resolution: PlaybackModel.MediaProfile.Resolution?,
        stereoLayout: PlaybackModel.StereoLayout
    ) {
        guard let resolution else {
            self.init(aspectRatio: Self.fallbackAspectRatio)
            return
        }
        let dimensions = stereoLayout.outputDimensions(
            inputWidth: resolution.width,
            inputHeight: resolution.height
        )
        guard dimensions.width > 0, dimensions.height > 0 else {
            self.init(aspectRatio: Self.fallbackAspectRatio)
            return
        }
        self.init(
            aspectRatio: CGFloat(dimensions.width) / CGFloat(dimensions.height)
        )
    }

    var minimumSize: CGSize {
        size(width: alignedWidth(
            DesignTokens.ControlBar.outerWidth * Self.minimumWidthMultiplier,
            rule: .up
        ))
    }

    var defaultSize: CGSize {
        size(width: alignedWidth(
            DesignTokens.ControlBar.outerWidth * Self.defaultWidthMultiplier,
            rule: .nearest
        ))
    }

    var maximumSize: CGSize {
        size(width: alignedWidth(
            DesignTokens.ControlBar.outerWidth * Self.maximumWidthMultiplier,
            rule: .down
        ))
    }

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

    func sizeThatFits(_ availableSize: CGSize) -> CGSize {
        guard availableSize.width > 0, availableSize.height > 0 else {
            return minimumSize
        }
        let widthLimitedByHeight = availableSize.height * aspectRatio
        let fittedWidth = min(
            availableSize.width,
            widthLimitedByHeight,
            maximumSize.width
        )
        let resolvedWidth = max(minimumSize.width, fittedWidth)
        return CGSize(
            width: resolvedWidth,
            height: resolvedWidth / aspectRatio
        )
    }

    private enum WidthAlignmentRule {
        case up
        case nearest
        case down
    }

    private func alignedWidth(
        _ width: CGFloat,
        rule: WidthAlignmentRule
    ) -> CGFloat {
        let unit: CGFloat = 16
        let quotient = width / unit
        switch rule {
        case .up:
            return quotient.rounded(.up) * unit
        case .nearest:
            return quotient.rounded() * unit
        case .down:
            return quotient.rounded(.down) * unit
        }
    }

    private func size(width: CGFloat) -> CGSize {
        CGSize(width: width, height: width / aspectRatio)
    }
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
    #if os(visionOS)
    @State private var owningWindowScene: UIWindowScene?
    #endif
    private let layout: WindowPlaybackLayout
    private let preferredInitialSize: CGSize?
    private let freeformSizeOnDisappear: @MainActor () -> CGSize?
    private let showsWindowChrome: Bool
    private let hidesSurfaceFromAccessibility: Bool
    private let onSurfaceTap: (() -> Void)?
    private let onWindowSceneChange: (@MainActor (UIWindowScene?) -> Void)?
    private let videoContent: VideoContent
    private let topChrome: TopChrome

    init(
        layout: WindowPlaybackLayout,
        preferredInitialSize: CGSize? = nil,
        freeformSizeOnDisappear: @escaping @MainActor () -> CGSize? = { nil },
        showsWindowChrome: Bool,
        hidesSurfaceFromAccessibility: Bool = false,
        onSurfaceTap: (() -> Void)? = nil,
        onWindowSceneChange: (@MainActor (UIWindowScene?) -> Void)? = nil,
        @ViewBuilder videoContent: () -> VideoContent,
        @ViewBuilder topChrome: () -> TopChrome
    ) {
        self.layout = layout
        self.preferredInitialSize = preferredInitialSize
        self.freeformSizeOnDisappear = freeformSizeOnDisappear
        self.showsWindowChrome = showsWindowChrome
        self.hidesSurfaceFromAccessibility = hidesSurfaceFromAccessibility
        self.onSurfaceTap = onSurfaceTap
        self.onWindowSceneChange = onWindowSceneChange
        self.videoContent = videoContent()
        self.topChrome = topChrome()
    }

    var body: some View {
        layeredContent
            .aspectRatio(layout.aspectRatio, contentMode: .fit)
            .frame(
                minWidth: layout.minimumSize.width,
                idealWidth: layout.defaultSize.width,
                maxWidth: layout.maximumSize.width,
                minHeight: layout.minimumSize.height,
                idealHeight: layout.defaultSize.height,
                maxHeight: layout.maximumSize.height
            )
            #if os(visionOS)
            .background {
                WindowPlaybackSceneReader { windowScene in
                    guard owningWindowScene !== windowScene else { return }
                    owningWindowScene = windowScene
                    onWindowSceneChange?(windowScene)
                    updateWindowGeometry(in: windowScene)
                }
            }
            .onChange(of: layout) { _, _ in
                updateWindowGeometry(in: owningWindowScene)
            }
            .onDisappear {
                restoreFreeformWindowGeometry(
                    in: owningWindowScene,
                    size: freeformSizeOnDisappear()
                )
            }
            #endif
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
            .animation(
                DesignTokens.AnimationToken.panelSpring,
                value: showsWindowChrome
            )
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
            .transition(.opacity.combined(with: .move(edge: .top)))
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
                        #if os(visionOS)
                        .gesture(
                            SpatialTapGesture()
                                .onEnded { _ in onSurfaceTap() }
                        )
                        #else
                        .onTapGesture(perform: onSurfaceTap)
                        #endif
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

    #if os(visionOS)
    private func updateWindowGeometry(in windowScene: UIWindowScene?) {
        guard let windowScene else { return }
        let preferences = UIWindowScene.GeometryPreferences.Vision(
            size: preferredInitialSize ?? layout.defaultSize,
            minimumSize: layout.minimumSize,
            maximumSize: layout.maximumSize,
            resizingRestrictions: .uniform
        )
        windowScene.requestGeometryUpdate(preferences)
    }

    private func restoreFreeformWindowGeometry(
        in windowScene: UIWindowScene?,
        size: CGSize?
    ) {
        guard let windowScene else { return }
        let systemDefault = CGSize(
            width: UIProposedSceneSizeNoPreference,
            height: UIProposedSceneSizeNoPreference
        )
        let preferences = UIWindowScene.GeometryPreferences.Vision(
            size: size,
            minimumSize: systemDefault,
            maximumSize: systemDefault,
            resizingRestrictions: .freeform
        )
        windowScene.requestGeometryUpdate(preferences)
    }
    #endif
}

#if os(visionOS)
private struct WindowPlaybackSceneReader: UIViewRepresentable {
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

private final class WindowPlaybackSceneReportingView: UIView {
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
#endif
