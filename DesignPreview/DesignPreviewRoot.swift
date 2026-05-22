import SwiftUI

struct DesignPreviewRoot: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ContentView()
            .ornament(attachmentAnchor: .scene(.bottomTrailing)) {
                Button {
                    openWindow(id: "designComps-emptyPanel")
                } label: {
                    Label("Empty Panel", systemImage: "rectangle.roundedtop")
                }
                .buttonStyle(.borderless)
                .glassBackgroundEffect(in: Capsule())
                .accessibilityIdentifier("DesignPreview-openEmptyPanel")
                .accessibilityLabel("Open Empty Panel")
            }
    }
}
