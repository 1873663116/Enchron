import DesignSystem
import SwiftUI

struct CollapsibleBlock<Content: View>: View {
    private let collapsedHeight: CGFloat
    private let title: String
    private let content: Content

    @State private var naturalHeight: CGFloat = 0
    @State private var isPresenting = false

    init(
        title: String,
        collapsedHeight: CGFloat = DesignTokens.Collapsible.collapsedHeight,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.collapsedHeight = collapsedHeight
        self.content = content()
    }

    private var overflows: Bool { naturalHeight > collapsedHeight + 1 }

    var body: some View {
        Group {
            if overflows {
                Button { isPresenting = true } label: { collapsed }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title), more")
                    .popover(isPresented: $isPresenting) { expanded }
            } else {
                content
            }
        }
        .background(alignment: .top) { ruler }
    }

    private var collapsed: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            content
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: collapsedHeight, alignment: .top)
                .clipped()

            Text("More")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
        }
        .padding(DesignTokens.Spacing.sm)
        .enchronHoverContentShape(DesignTokens.ShapeToken.element)
        .contentShape(DesignTokens.ShapeToken.element)
        .enchronHoverEffect(.highlight)
        .padding(-DesignTokens.Spacing.sm)
    }

    private var expanded: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                Text(title)
                    .font(DesignTokens.Typography.sectionHeader)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DesignTokens.Spacing.xl)
        }
        .frame(
            width: DesignTokens.Collapsible.expandedWidth,
            height: DesignTokens.Collapsible.expandedMaxHeight
        )
    }

    private var ruler: some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { naturalHeight = $0 }
            .hidden()
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}
