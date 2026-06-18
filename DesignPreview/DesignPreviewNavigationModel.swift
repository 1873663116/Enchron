import Observation

@MainActor
@Observable
final class DesignPreviewNavigationModel {
    nonisolated static let mainWindowID = "main"
    nonisolated static let senseZoneVolumeID = "sense-zone"
    nonisolated static let windowPlaybackWindowID = "window-playback"

    var selectedTab: DesignPreviewTab = .files
    var returnRoute = DesignPreviewReturnRoute(tab: .files)
    var isEnvironmentTransitionInFlight = false

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
    case environment

    var restorableTab: DesignPreviewTab? {
        switch self {
        case .files, .settings:
            self
        case .environment:
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
