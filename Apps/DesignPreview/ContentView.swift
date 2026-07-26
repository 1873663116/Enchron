import DesignSystem
import MediaLibrary
import PlaybackPresentation
import SwiftUI

// MARK: - Preview routing

enum DesignPreviewPage: String, CaseIterable, Identifiable {
    // MARK: Components (front)
    case components
    case sidebar
    case settingListGroup
    case slider
    case environmentCard
    case connectionForm
    case dialogs
    case fusedPanel
    // MARK: Design Tokens (back)
    case spacing
    case radiusAndShapes
    case interactionAndLayout
    case typographyAndSymbols
    case surfaceAndStroke
    case animation
    case pressFeedback
    case componentStandards

    var id: String { rawValue }

    var title: String {
        switch self {
        case .components: "Components"
        case .spacing: "Spacing"
        case .radiusAndShapes: "Radius & Shapes"
        case .interactionAndLayout: "Interaction & Layout"
        case .typographyAndSymbols: "Typography & Symbols"
        case .surfaceAndStroke: "Surface & Stroke"
        case .animation: "Animation"
        case .pressFeedback: "Press Feedback"
        case .sidebar: "Sidebar"
        case .settingListGroup: "Setting List Group"
        case .slider: "Slider"
        case .environmentCard: "Environment Card"
        case .connectionForm: "Connection Form"
        case .dialogs: "Dialogs"
        case .fusedPanel: "Fused Panel"
        case .componentStandards: "Component Standards"
        }
    }
}

struct ContentView: View {
    @State private var selection: DesignPreviewPage? = .components

    var body: some View {
        NavigationSplitView {
            List(DesignPreviewPage.allCases, selection: $selection) { page in
                Text(page.title)
                    .tag(page)
            }
            .navigationTitle("Design Preview")
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            switch selection ?? .components {
            case .components:
                ComponentLibraryView()
            case .spacing:
                SpacingScalePreview()
            case .radiusAndShapes:
                RadiusShapesPreview()
            case .interactionAndLayout:
                InteractionLayoutPreview()
            case .typographyAndSymbols:
                TypographySymbolsPreview()
            case .surfaceAndStroke:
                SurfaceStrokePreview()
            case .animation:
                AnimationTokensPreview()
            case .pressFeedback:
                PressFeedbackPreview()
            case .sidebar:
                SidebarPreview()
            case .settingListGroup:
                SettingListGroupPreview()
            case .slider:
                SliderPreview()
            case .environmentCard:
                EnvironmentCardPreview()
            case .connectionForm:
                ConnectionFormPreview()
            case .dialogs:
                DialogsPreview()
            case .fusedPanel:
                FusedPlayerPanelPreview()
            case .componentStandards:
                ComponentStandardsPreview()
            }
        }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
}

// MARK: - Fused Player Panel
