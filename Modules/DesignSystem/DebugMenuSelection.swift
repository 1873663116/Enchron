#if DEBUG
import Foundation

public enum DebugMenuSelectionHost: String, CaseIterable, Sendable {
    case playerUI
    case playerPanel
    case files
    case mediaLibrary
    case emby
    case settings
}

public enum DebugMenuSelectionFamily: String, CaseIterable, Sendable {
    case subtitles
    case audio
    case speed
    case episodes
    case customAngle
    case sortKey
    case sortOrder
    case breadcrumb
    case manage
    case moveDestination
    case referenceMoveDestination
    case sourceAction
    case sourceAdd
    case season
    case version
    case resumeStrategy = "resume-strategy"
    case endBehavior = "end-behavior"
    case defaultSpeed = "default-speed"
    case controlsAutoHide = "controls-auto-hide"
}

public struct DebugMenuSelectionItem {
    public let id: String
    public let title: String
    public let isSelected: Bool
    private let selectItem: @MainActor () -> Void

    public init(
        id: String,
        title: String,
        isSelected: Bool,
        select: @escaping @MainActor () -> Void
    ) {
        self.id = id
        self.title = title
        self.isSelected = isSelected
        self.selectItem = select
    }

    @MainActor
    fileprivate func select() {
        selectItem()
    }
}

public struct DebugMenuSelectionSnapshot: Equatable, Sendable {
    public let id: String
    public let title: String
    public let isSelected: Bool

    fileprivate init(_ item: DebugMenuSelectionItem) {
        id = item.id
        title = item.title
        isSelected = item.isSelected
    }
}

@MainActor
public final class DebugMenuSelectionRequest {
    public static let firstUnselectedTarget = "__firstUnselected"
    public static let firstAvailableTarget = "__firstAvailable"

    public enum Operation: Equatable, Sendable {
        case list
        case select(target: String)
    }

    public let host: DebugMenuSelectionHost
    public let family: DebugMenuSelectionFamily
    public let operation: Operation
    public private(set) var items: [DebugMenuSelectionSnapshot]?
    public private(set) var selectedItem: DebugMenuSelectionSnapshot?

    public init(
        host: DebugMenuSelectionHost,
        family: DebugMenuSelectionFamily,
        operation: Operation
    ) {
        self.host = host
        self.family = family
        self.operation = operation
    }

    public func handle(
        host: DebugMenuSelectionHost,
        family: DebugMenuSelectionFamily,
        items: [DebugMenuSelectionItem]
    ) {
        guard self.host == host,
              self.family == family,
              self.items == nil,
              selectedItem == nil else {
            return
        }

        let snapshots = items.map(DebugMenuSelectionSnapshot.init)
        switch operation {
        case .list:
            self.items = snapshots
        case .select(let target):
            let index: Array<DebugMenuSelectionItem>.Index? = switch target {
            case Self.firstUnselectedTarget:
                items.firstIndex(where: { $0.isSelected == false })
            case Self.firstAvailableTarget:
                items.indices.first
            default:
                items.firstIndex(where: { $0.id == target })
            }
            guard let index else {
                self.items = snapshots
                return
            }
            let item = items[index]
            item.select()
            selectedItem = DebugMenuSelectionSnapshot(item)
        }
    }
}

public extension Notification.Name {
    static let debugMenuSelection = Notification.Name(
        "app.enchron.debug.menu-selection"
    )
}
#endif
