import Observation

@MainActor
@Observable
final class DesignPreviewNavigationModel {
    nonisolated static let mainWindowID = "main"
    nonisolated static let senseZoneVolumeID = "sense-zone"

    var selectedTab: DesignPreviewTab = .files
    var returnRoute = DesignPreviewReturnRoute(tab: .files)
    var isSceneTransitionInFlight = false

    func rememberReturnRoute(from tab: DesignPreviewTab) {
        guard let restorableTab = tab.restorableTab else { return }
        returnRoute = DesignPreviewReturnRoute(tab: restorableTab)
    }

    func restoreReturnRoute() {
        selectedTab = returnRoute.tab
    }
}

enum DesignPreviewTab: Hashable, Codable {
    case files
    case settings
    case scene

    var restorableTab: DesignPreviewTab? {
        switch self {
        case .files, .settings:
            self
        case .scene:
            nil
        }
    }
}

struct DesignPreviewReturnRoute: Hashable, Codable {
    let tab: DesignPreviewTab

    init(tab: DesignPreviewTab) {
        self.tab = tab.restorableTab ?? .files
    }
}
