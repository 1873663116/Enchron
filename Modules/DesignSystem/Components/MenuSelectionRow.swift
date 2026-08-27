import SwiftUI

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
