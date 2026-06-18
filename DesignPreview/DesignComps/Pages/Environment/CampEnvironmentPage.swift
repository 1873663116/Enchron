import SwiftUI

struct CampEnvironmentPage: View {
    var onReturn: () -> Void = {}

    var body: some View {
        EnvironmentCardCarousel(onReturn: onReturn)
            .background(.clear)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("DesignComps-CampEnvironmentPage")
            .accessibilityLabel("Camp environment page")
    }
}
