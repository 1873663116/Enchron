import SwiftUI

public struct ScreenPositionControlView: View {
    @Environment(AppModel.self) private var appModel
    private let onClose: () -> Void

    public init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    public var body: some View {
        @Bindable var model = appModel

        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Screen Position")
                    .font(.headline)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Screen Position")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Preset pickers
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Distance Preset", selection: $model.screenDistance) {
                            Text("Near").tag(4.0)
                            Text("Comfort").tag(8.0)
                            Text("Cinema").tag(14.0)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("Distance preset")

                        Picker("Angle Preset", selection: $model.screenViewAngle) {
                            Text("Left").tag(-30.0)
                            Text("Center").tag(0.0)
                            Text("Right").tag(30.0)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("Rotation preset")
                    }

                    Divider()

                    // Fine-tune sliders — Grid keeps columns aligned (HelloWorld SliderGridRow pattern)
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
                        SliderGridRow(
                            label: "Distance",
                            value: $model.screenDistance,
                            range: 2.0...20.0,
                            unit: "m"
                        )
                        SliderGridRow(
                            label: "Vertical",
                            value: $model.screenVerticalOffset,
                            range: -2.0...2.0,
                            unit: "m"
                        )
                        SliderGridRow(
                            label: "Rotation",
                            value: $model.screenViewAngle,
                            range: -45...45,
                            unit: "°",
                            format: "%.0f"
                        )
                    }
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onChange(of: model.screenDistance) { _, _ in appModel.saveScreenPosition() }
        .onChange(of: model.screenVerticalOffset) { _, _ in appModel.saveScreenPosition() }
        .onChange(of: model.screenViewAngle) { _, _ in appModel.saveScreenPosition() }
    }
}
