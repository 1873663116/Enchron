import SwiftUI

struct CampScenePage: View {
    var body: some View {
        SceneCardCarousel()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.clear)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("DesignComps-CampScenePage")
            .accessibilityLabel("Camp scene page")
    }
}
