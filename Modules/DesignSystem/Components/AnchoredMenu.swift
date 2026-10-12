import SwiftUI

@MainActor
@Observable
public final class AnchoredMenuPresentation {
    @Observable
    final class Panel: Identifiable {
        let id = UUID()
        let key: String
        let source: CGRect
        let sizing: AnchoredMenuSizing
        let content: () -> AnyView
        let onDismiss: () -> Void
        var isPresented = true
        var size: CGSize = .zero

        init(key: String, source: CGRect, sizing: AnchoredMenuSizing,
             onDismiss: @escaping () -> Void, content: @escaping () -> AnyView) {
            self.key = key
            self.source = source
            self.sizing = sizing
            self.onDismiss = onDismiss
            self.content = content
        }
    }

    public let coordinateSpace = UUID()
    public var preferredEdge: AnchoredMenuPlacement.Edge = .below
    public var bounds: CGRect = .zero
    private(set) var root: Panel?
    private(set) var child: Panel?

    public init() {}

    public var isActive: Bool { root != nil }
    public var isPresented: Bool { root?.isPresented == true }
    public var selectedSubmenu: String? { child?.isPresented == true ? child?.key : nil }

    public func present<Content: View>(
        key: String, source: CGRect, sizing: AnchoredMenuSizing = .content,
        onDismiss: @escaping () -> Void = {},
        @ViewBuilder content: @escaping () -> Content
    ) {
        root = Panel(key: key, source: source, sizing: sizing,
                     onDismiss: onDismiss, content: { AnyView(content()) })
        child = nil
    }

    public func presentSubmenu<Content: View>(
        key: String, source: CGRect, sizing: AnchoredMenuSizing = .content,
        @ViewBuilder content: @escaping () -> Content
    ) {
        guard root?.isPresented == true else { return }
        if child != nil {
            dismissSubmenu()
            return
        }
        child = Panel(key: key, source: source, sizing: sizing,
                      onDismiss: {}, content: { AnyView(content()) })
    }

    public func dismissSubmenu() {
        child?.isPresented = false
    }

    public func dismiss() {
        child?.isPresented = false
        root?.isPresented = false
    }

    public func reset() {
        let callback = root?.onDismiss
        root = nil
        child = nil
        callback?()
    }

    func finished(_ id: UUID) {
        if child?.id == id { child = nil }
        if root?.id == id { reset() }
    }

    func placement(for panel: Panel) -> AnchoredMenuPlacement {
        let available = bounds.insetBy(dx: DesignTokens.Menu.edgeInset, dy: DesignTokens.Menu.edgeInset)
        if let root, root.id != panel.id {
            return .submenu(source: panel.source, parent: placement(for: root).frame,
                            size: panel.size, bounds: available)
        }
        return .root(source: panel.source, size: panel.size,
                     bounds: available, preferredEdge: preferredEdge)
    }
}

public extension EnvironmentValues {
    @Entry var anchoredMenuPresentation: AnchoredMenuPresentation?
}

public struct AnchoredMenuLayer: View {
    private let presentation: AnchoredMenuPresentation

    public init(presentation: AnchoredMenuPresentation) {
        self.presentation = presentation
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            if presentation.isActive {
                AnchoredMenuDismissArea(presentation: presentation)
            }
            if let root = presentation.root {
                AnchoredMenuSurface(panel: root, presentation: presentation, isSubmenu: false)
                    .id(root.id)
            }
            if let child = presentation.child {
                AnchoredMenuSurface(panel: child, presentation: presentation, isSubmenu: true)
                    .id(child.id)
                    .zIndex(1)
            }
        }
        .frame(width: presentation.bounds.width, height: presentation.bounds.height,
               alignment: .topLeading)
        .coordinateSpace(name: presentation.coordinateSpace)
        .environment(\.anchoredMenuPresentation, presentation)
        .accessibilityElement(children: .contain)
    }
}

private struct AnchoredMenuDismissArea: View {
    let presentation: AnchoredMenuPresentation

    var body: some View {
        Button { presentation.dismiss() } label: {
            DesignTokens.Surface.menuDismissInput
                .contentShape(.interaction, Rectangle())
        }
        .buttonStyle(.plain)
        .enchronHoverEffectDisabled()
        .accessibilityLabel("Dismiss menu")
        .accessibilityIdentifier("PlayerPanel-menu-dismiss-area")
    }
}

private struct AnchoredMenuSurface: View {
    let panel: AnchoredMenuPresentation.Panel
    let presentation: AnchoredMenuPresentation
    let isSubmenu: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0
    @State private var containerRadii: RectangleCornerRadii?

    private var availableSize: CGSize {
        CGSize(width: max(0, presentation.bounds.width - DesignTokens.Menu.edgeInset * 2),
               height: max(0, presentation.bounds.height - DesignTokens.Menu.edgeInset * 2))
    }

    var body: some View {
        let shape = DesignTokens.ShapeToken.menu(containerRadii: containerRadii)
        ScrollView {
            AnchoredMenuContentLayout(sizing: panel.sizing, availableWidth: availableSize.width) {
                panel.content()
            }
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                    guard size.height > 0, size.width > 0 else { return }
                    panel.size = CGSize(width: size.width + DesignTokens.Menu.glassPadding * 2,
                                        height: panel.sizing.height(contentHeight: size.height,
                                                                    availableHeight: availableSize.height))
                }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: max(0, panel.size.width - DesignTokens.Menu.glassPadding * 2),
               height: max(0, panel.size.height - DesignTokens.Menu.glassPadding * 2))
        .padding(DesignTokens.Menu.glassPadding)
        .containerShape(shape)
        .clipShape(shape)
        .enchronGlassBackground(in: shape)
        .contentShape(.interaction, shape)
        .background {
            shape.fill(.clear)
                .onTapGesture {
                    if !isSubmenu { presentation.dismissSubmenu() }
                }
        }
        .highPriorityGesture(
            TapGesture().onEnded { presentation.dismissSubmenu() },
            including: !isSubmenu && presentation.child != nil ? .all : .subviews
        )
        .modifier(AnchoredMenuMotion(
            progress: progress,
            placement: presentation.placement(for: panel),
            depth: isSubmenu ? DesignTokens.Menu.layerDepth * 2 : DesignTokens.Menu.layerDepth,
            reduceMotion: reduceMotion
        ))
        .onGeometryChange(for: RectangleCornerRadii?.self) { $0.concentricCornerRadii } action: { radii in
            containerRadii = radii
        }
        .allowsHitTesting(panel.isPresented && progress > 0)
        .accessibilityElement(children: .contain)
        .accessibilityHidden(!panel.isPresented)
        .onChange(of: panel.size, initial: true) { _, size in
            if size.width > 0, size.height > 0, panel.isPresented, progress == 0 { animate() }
        }
        .onChange(of: panel.isPresented) { _, _ in animate() }
    }

    private func animate() {
        let opening = panel.isPresented
        withAnimation(reduceMotion ? DesignTokens.AnimationToken.informationReveal
            : DesignTokens.AnimationToken.menuPopup, completionCriteria: .removed) {
            progress = opening ? 1 : 0
        } completion: {
            if !opening, !panel.isPresented { presentation.finished(panel.id) }
        }
    }
}

private struct AnchoredMenuContentLayout: Layout {
    let sizing: AnchoredMenuSizing
    let availableWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let ideal = content.sizeThatFits(.unspecified)
        let width = max(0, sizing.width(idealContentWidth: ideal.width, availableWidth: availableWidth)
                        - DesignTokens.Menu.glassPadding * 2)
        return CGSize(width: width,
                      height: content.sizeThatFits(ProposedViewSize(width: width, height: nil)).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading,
                             proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

private struct AnchoredMenuMotion: AnimatableModifier {
    var progress: CGFloat
    let placement: AnchoredMenuPlacement
    let depth: CGFloat
    let reduceMotion: Bool

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let frame = reduceMotion ? placement.frame : placement.frame(at: progress)
        content
            .scaleEffect(placement.frame.width > 0 ? frame.width / placement.frame.width : 1)
            .offset(x: frame.midX - placement.frame.width / 2,
                    y: frame.midY - placement.frame.height / 2)
            .opacity(Double(min(max(progress, 0), 1)))
            .enchronSpatialOffset(z: depth)
    }
}

private struct AnchoredMenuHost: ViewModifier {
    let presentation: AnchoredMenuPresentation

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(!presentation.isActive)
            .environment(\.anchoredMenuPresentation, presentation)
            .coordinateSpace(name: presentation.coordinateSpace)
            .overlay(alignment: .topLeading) {
                AnchoredMenuLayer(presentation: presentation)
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                presentation.bounds = CGRect(origin: .zero, size: size)
            }
            .onDisappear { presentation.reset() }
    }
}

private struct AnchoredMenuSource<MenuContent: View>: ViewModifier {
    @Environment(\.anchoredMenuPresentation) private var presentation
    @Binding var isPresented: Bool
    let key: String
    let width: CGFloat
    let menuContent: () -> MenuContent
    @State private var source = CGRect.zero

    func body(content: Content) -> some View {
        if let presentation {
            content
                .onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .named(presentation.coordinateSpace))
                } action: { frame in
                    source = frame
                    if isPresented, !presentation.isActive { present(in: presentation) }
                }
                .onChange(of: isPresented, initial: true) { _, value in
                    if value, !source.isEmpty {
                        present(in: presentation)
                    } else if !value, presentation.root?.key == key {
                        presentation.dismiss()
                    }
                }
        } else {
            content
        }
    }

    private func present(in presentation: AnchoredMenuPresentation) {
        presentation.present(key: key, source: source, sizing: .fixed(width: width),
                             onDismiss: { isPresented = false }, content: menuContent)
    }
}

public extension View {
    func anchoredMenuHost(presentation: AnchoredMenuPresentation) -> some View {
        modifier(AnchoredMenuHost(presentation: presentation))
    }

    func anchoredMenuDismissRegion(presentation: AnchoredMenuPresentation) -> some View {
        allowsHitTesting(!presentation.isActive)
            .overlay {
                if presentation.isActive {
                    AnchoredMenuDismissArea(presentation: presentation)
                }
            }
    }

    func anchoredMenu<MenuContent: View>(
        isPresented: Binding<Bool>, key: String, width: CGFloat,
        @ViewBuilder content: @escaping () -> MenuContent
    ) -> some View {
        modifier(AnchoredMenuSource(isPresented: isPresented, key: key, width: width, menuContent: content))
    }
}
