import SwiftUI
import UIKit

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
            Label {
                Text(title)
            } icon: {
                MenuCheckmark.image(isSelected: isSelected)
            }
        }
        .accessibilityIdentifier(identifier)
    }
}

public enum MenuCheckmark {
    private static let checkmark: UIImage = UIImage(systemName: "checkmark") ?? UIImage()

    private static let blankCheckmark: UIImage = checkmark
        .withTintColor(.clear, renderingMode: .alwaysOriginal)

    public static func image(isSelected: Bool) -> Image {
        Image(uiImage: isSelected ? checkmark : blankCheckmark)
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
