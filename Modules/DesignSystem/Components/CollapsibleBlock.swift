import SwiftUI

/// A block that shows as much of itself as it is allowed and, when there is more, turns into a
/// surface the wearer can look at and open.
///
/// A block that fits draws nothing extra: no surface, no highlight, no control. The whole point is
/// that a page which has little to say looks like plain text, and only the places holding more than
/// their room announce themselves.
public struct CollapsibleBlock<Content: View>: View {
    private let collapsedHeight: CGFloat
    private let title: String
    private let content: Content

    /// The unclipped height of the content, measured from a copy that is laid out but never drawn.
    /// The visible copy cannot answer this: it has already been cut down to the cap.
    @State private var naturalHeight: CGFloat = 0
    @State private var isPresenting = false

    public init(
        title: String,
        collapsedHeight: CGFloat = DesignTokens.Collapsible.collapsedHeight,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.collapsedHeight = collapsedHeight
        self.content = content()
    }

    private var overflows: Bool { naturalHeight > collapsedHeight + 1 }

    public var body: some View {
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

    /// At rest this is the same plain text every other block on the page is, carrying no surface of
    /// its own. The frame it opens from belongs to the hover highlight, so it appears under the
    /// wearer's gaze and nowhere else.
    ///
    /// The padding is taken back again on the outside, so the highlight has room around the text
    /// without the text itself sitting further in than the blocks beside it.
    private var collapsed: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            content
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: collapsedHeight, alignment: .top)
                // The last line is cut rather than faded out: a fade reads as a rendering fault
                // when the block is only one line short, and the word below already says why.
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

    /// A second copy of the content, laid out at its natural height and never drawn, purely so the
    /// block can tell whether it has more than it can show. It sits behind the visible copy where
    /// `fixedSize` frees it from the height the cap proposes.
    private var ruler: some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { naturalHeight = $0 }
            .hidden()
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}
