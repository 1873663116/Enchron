import SwiftUI

/// A single row in a settings Grid: label | slider | formatted value.
///
/// Follows the HelloWorld SliderGridRow pattern — three columns keep sliders
/// horizontally aligned across multiple rows, reducing vertical space compared
/// to stacked VStack labels.
struct SliderGridRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String
    var format: String = "%.1f"

    var body: some View {
        GridRow {
            Text(label)
                .gridColumnAlignment(.leading)
                .frame(minWidth: 64, alignment: .leading)
            Slider(value: $value, in: range)
                .accessibilityLabel(label)
                .accessibilityValue(String(format: "\(format)\(unit)", value))
            Text(String(format: "\(format)\(unit)", value))
                .monospacedDigit()
                .bold()
                .gridColumnAlignment(.trailing)
                .frame(minWidth: 60, alignment: .trailing)
        }
    }
}
