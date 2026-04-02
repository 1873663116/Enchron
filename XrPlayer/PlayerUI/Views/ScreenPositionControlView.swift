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
                VStack(spacing: 20) {
                    // Distance
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Distance: \(model.screenDistance, specifier: "%.1f")m")
                            .font(.subheadline)
                        Picker("Distance Preset", selection: $model.screenDistance) {
                            Text("Near").tag(4.0)
                            Text("Comfort").tag(8.0)
                            Text("Cinema").tag(14.0)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("Distance preset")
                        Slider(value: $model.screenDistance, in: 2.0...20.0)
                            .accessibilityLabel("Screen distance")
                            .accessibilityValue("\(String(format: "%.1f", model.screenDistance)) meters")
                    }

                    // Vertical Offset
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Vertical: \(model.screenVerticalOffset, specifier: "%.1f")m")
                            .font(.subheadline)
                        Slider(value: $model.screenVerticalOffset, in: -2.0...2.0)
                            .accessibilityLabel("Vertical offset")
                            .accessibilityValue("\(String(format: "%.1f", model.screenVerticalOffset)) meters")
                    }

                    // View Angle (X-axis rotation)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Rotation: \(model.screenViewAngle, specifier: "%.0f")°")
                            .font(.subheadline)
                        Picker("Angle Preset", selection: $model.screenViewAngle) {
                            Text("Left").tag(-30.0)
                            Text("Center").tag(0.0)
                            Text("Right").tag(30.0)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("Rotation preset")
                        Slider(value: $model.screenViewAngle, in: -45...45)
                            .accessibilityLabel("Screen rotation")
                            .accessibilityValue("\(String(format: "%.0f", model.screenViewAngle)) degrees")
                    }
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassBackgroundEffect()
        .onChange(of: model.screenDistance) { _, _ in appModel.saveScreenPosition() }
        .onChange(of: model.screenVerticalOffset) { _, _ in appModel.saveScreenPosition() }
        .onChange(of: model.screenViewAngle) { _, _ in appModel.saveScreenPosition() }
    }
}
