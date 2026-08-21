import SwiftUI

/// One selectable row of a `Menu`, carrying an identifier that survives.
///
/// SwiftUI keeps `.accessibilityIdentifier` only on the rows a menu adopts as
/// first-class actions. A `Picker` row and a `Toggle` row are both content the
/// menu lays out for itself, and both reach the accessibility tree with no
/// identifier at all, so nothing can address them and no coverage check can go
/// red over them. A `Button` keeps its identifier. All three were measured
/// against one build on device on 2026-08-21.
///
/// The cost is the checkmark. A `Picker` draws it on the trailing edge and this
/// draws it on the leading edge, which shifts the title. That is the whole
/// price of the row being reachable, and the playback panel has shipped this
/// form for its own menus all along.
public struct MenuSelectionRow: View {
    private let title: String
    private let isSelected: Bool
    private let identifier: String
    private let action: () -> Void

    public init(
        _ title: String,
        isSelected: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isSelected = isSelected
        self.identifier = identifier
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            if isSelected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
        .accessibilityIdentifier(identifier)
    }
}

#Preview("Selected and not", traits: .sizeThatFitsLayout) {
    Menu("Sort") {
        MenuSelectionRow("Name", isSelected: true, identifier: "preview-name") {}
        MenuSelectionRow("Date Modified", isSelected: false, identifier: "preview-date") {}
        MenuSelectionRow("Size", isSelected: false, identifier: "preview-size") {}
    }
    .padding()
}
