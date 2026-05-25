import SwiftUI

struct CampScenePage: View {
    var onReturn: () -> Void = {}

    var body: some View {
        SceneCardCarousel(onReturn: onReturn)
            .background(.clear)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("DesignComps-CampScenePage")
            .accessibilityLabel("Camp scene page")
    }
}
