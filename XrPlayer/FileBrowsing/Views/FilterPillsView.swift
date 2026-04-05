import SwiftUI

/// Horizontal row of pill-shaped filter toggles (All, 4K, HDR, Spatial).
/// "All" is the default; other filters are additive.
struct FilterPillsView: View {
    @Environment(FileBrowsingViewModel.self) private var viewModel

    private let filters: [FileBrowsingDomain.ContentFilter] = FileBrowsingDomain.ContentFilter.allCases

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filters, id: \.self) { filter in
                    let isActive = viewModel.activeFilters.contains(filter)

                    Button {
                        viewModel.toggleFilter(filter)
                    } label: {
                        Text(filter.displayName)
                            .font(DesignTokens.Typography.badge)
                            .fontWeight(.medium)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                isActive ? Color.enchronTertiary : Color.enchronSurfaceContainerHighest,
                                in: Capsule()
                            )
                            .foregroundStyle(isActive ? Color.enchronOnTertiary : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(filter.displayName) filter")
                    .accessibilityAddTraits(isActive ? .isSelected : [])
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
    }
}
