import SwiftUI
import Observation

@MainActor
@Observable
public final class AppModel {
    public enum NavigationTab: String, CaseIterable {
        case files, emby, settings, environment

        var isContentDestination: Bool {
            self != .environment
        }
    }
    public var selectedTab: NavigationTab = .files
}
