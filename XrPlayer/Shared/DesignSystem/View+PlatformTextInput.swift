import SwiftUI

extension View {
    @ViewBuilder
    func enchronLiteralTextInput() -> some View {
        #if os(visionOS)
        textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        self
        #endif
    }
}
