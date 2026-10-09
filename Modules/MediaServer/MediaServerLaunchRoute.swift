#if DEBUG
import Foundation

public struct MediaServerLaunchRoute: Equatable, Sendable {
    public var kind: MediaServerKind = .emby
    public var token: String?
    public let address: String
    public let username: String
    public let password: String
    public let libraryID: MediaServerItemID?
    public let itemID: MediaServerItemID?
    public let sectionName: String?
    public let sidebarIsVisible: Bool

    public static var current: MediaServerLaunchRoute? {
        environment(ProcessInfo.processInfo.environment)
    }

    static func environment(_ values: [String: String]) -> MediaServerLaunchRoute? {
        let kind = values["ENCHRON_MEDIA_SERVER_KIND"].flatMap(MediaServerKind.init(rawValue:)) ?? .emby
        let prefix = values["ENCHRON_MEDIA_SERVER_KIND"] == nil ? "ENCHRON_EMBY_" : "ENCHRON_MEDIA_SERVER_"
        guard let address = values[prefix + "ADDRESS"], address.isEmpty == false,
              let username = values[prefix + "USERNAME"], username.isEmpty == false else {
            return nil
        }
        return MediaServerLaunchRoute(
            kind: kind,
            token: values[prefix + "TOKEN"],
            address: address,
            username: username,
            password: values[prefix + "PASSWORD"] ?? "",
            libraryID: values[prefix + "LIBRARY"].map(MediaServerItemID.init(rawValue:)),
            itemID: values[prefix + "ITEM"].map(MediaServerItemID.init(rawValue:)),
            sectionName: values[prefix + "SECTION"],
            sidebarIsVisible: values[prefix + "SIDEBAR"] != "hidden"
        )
    }
}
#endif
