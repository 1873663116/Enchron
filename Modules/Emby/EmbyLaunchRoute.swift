#if DEBUG
import Foundation

/// Opens a named Emby screen straight from the launch environment.
///
/// The visionOS simulator exposes no UI automation and this toolchain ships no Simulator window, so
/// a screenshot is the only way to see a screen and a launch argument is the only way to reach one.
public struct EmbyLaunchRoute: Equatable, Sendable {
    public let address: String
    public let username: String
    public let password: String
    public let libraryID: EmbyItemID?
    public let itemID: EmbyItemID?
    /// Detail-page section to scroll to, so sections below the fold can be photographed.
    public let sectionName: String?
    public let sidebarIsVisible: Bool

    public static var current: EmbyLaunchRoute? {
        environment(ProcessInfo.processInfo.environment)
    }

    static func environment(_ values: [String: String]) -> EmbyLaunchRoute? {
        guard let address = values["ENCHRON_EMBY_ADDRESS"], address.isEmpty == false,
              let username = values["ENCHRON_EMBY_USERNAME"], username.isEmpty == false else {
            return nil
        }
        return EmbyLaunchRoute(
            address: address,
            username: username,
            password: values["ENCHRON_EMBY_PASSWORD"] ?? "",
            libraryID: values["ENCHRON_EMBY_LIBRARY"].map(EmbyItemID.init(rawValue:)),
            itemID: values["ENCHRON_EMBY_ITEM"].map(EmbyItemID.init(rawValue:)),
            sectionName: values["ENCHRON_EMBY_SECTION"],
            sidebarIsVisible: values["ENCHRON_EMBY_SIDEBAR"] != "hidden"
        )
    }
}
#endif
