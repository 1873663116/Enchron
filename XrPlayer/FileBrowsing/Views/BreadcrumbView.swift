import SwiftUI

/// Tappable path breadcrumb showing the current navigation hierarchy.
/// Each segment navigates to that folder level when tapped.
struct BreadcrumbView: View {
    @Environment(FileBrowsingViewModel.self) private var viewModel

    var body: some View {
        let segments = viewModel.breadcrumbSegments

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(segments.enumerated()), id: \.offset) { offset, segment in
                    if offset > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }

                    let isLast = offset == segments.count - 1

                    Button {
                        guard !isLast else { return }
                        Task {
                            await viewModel.navigateToBreadcrumb(index: segment.index)
                        }
                    } label: {
                        Text(segment.name)
                            .font(.subheadline)
                            .fontWeight(isLast ? .semibold : .regular)
                            .foregroundStyle(isLast ? .primary : .secondary)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.lift)
                    .frame(minWidth: 60, minHeight: 60)
                    .contentShape(.rect)
                    .disabled(isLast)
                    .accessibilityLabel(isLast ? "\(segment.name), current folder" : segment.name)
                    .accessibilityHint(isLast ? "" : "Navigates to \(segment.name)")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}
