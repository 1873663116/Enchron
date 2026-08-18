import DesignSystem
import Emby
import Foundation
import MediaLibrary
import PlaybackFeature
import PlaybackPresentation
#if os(visionOS)
import UIKit
#endif

@MainActor
final class TestCommandChannel {
    private struct Request: Decodable {
        let id: String
        let verb: String
        let args: [String: String]
    }

    private struct Response: Encodable {
        struct MenuItem: Encodable {
            let id: String
            let title: String
            let isSelected: Bool
        }

        let id: String
        let ok: Bool
        let detail: String?
        let payload: [String]?
        var menuItems: [MenuItem]? = nil
    }

    private struct CommandError: LocalizedError {
        let message: String

        var errorDescription: String? { message }
    }

    private let mediaLibrary: MediaLibraryViewModel
    private let appModel: AppModel
    private let playbackRuntime: PlaybackRuntime
    private let fileManager: FileManager
    private let defaults: UserDefaults
    private let commandURL: URL
    private let commandsURL: URL
    private let responsesURL: URL
    private let responseSessionURL: URL
    private let inboxURL: URL
    private var pollingTask: Task<Void, Never>?

    init(
        mediaLibrary: MediaLibraryViewModel,
        appModel: AppModel,
        playbackRuntime: PlaybackRuntime,
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard
    ) throws {
        self.mediaLibrary = mediaLibrary
        self.appModel = appModel
        self.playbackRuntime = playbackRuntime
        self.fileManager = fileManager
        self.defaults = defaults

        let documentsURL = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        commandURL = documentsURL.appending(path: "test-command.json")
        commandsURL = documentsURL.appending(
            path: "test-commands",
            directoryHint: .isDirectory
        )
        responsesURL = documentsURL.appending(
            path: "test-responses",
            directoryHint: .isDirectory
        )
        responseSessionURL = documentsURL.appending(
            path: "test-response-session.txt"
        )
        inboxURL = documentsURL.appending(
            path: "TestMediaInbox",
            directoryHint: .isDirectory
        )
        var inboxIsDirectory: ObjCBool = false
        if fileManager.fileExists(
            atPath: inboxURL.path,
            isDirectory: &inboxIsDirectory
        ), inboxIsDirectory.boolValue == false {
            try fileManager.removeItem(at: inboxURL)
        }
        try fileManager.createDirectory(
            at: commandsURL,
            withIntermediateDirectories: true
        )
        for queuedCommandURL in try fileManager.contentsOfDirectory(
            at: commandsURL,
            includingPropertiesForKeys: nil
        ) where queuedCommandURL.pathExtension == "json" {
            try fileManager.removeItem(at: queuedCommandURL)
        }
        try fileManager.createDirectory(
            at: responsesURL,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: inboxURL,
            withIntermediateDirectories: true
        )
    }

    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while Task.isCancelled == false {
                self?.processRequestIfPresent()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func processRequestIfPresent() {
        do {
            guard let requestURL = try nextRequestURL() else { return }
            let request = try JSONDecoder().decode(
                Request.self,
                from: Data(contentsOf: requestURL)
            )
#if DEBUG
            try prepareEvidenceSession(for: request, requestURL: requestURL)
#endif
            let responseURL = responsesURL.appending(path: "\(request.id).json")
            if fileManager.fileExists(atPath: responseURL.path) {
                if requestURL == commandURL {
                    try fileManager.removeItem(at: requestURL)
                }
                return
            }

#if DEBUG
            if let evidenceSession = request.args["evidenceSession"],
               evidenceSession.isEmpty == false {
                AppModel.recordProbe(
                    "reachability evidence session=\(evidenceSession)"
                        + " command=\(request.id) verb=\(request.verb)"
                )
            }
#endif
            AppModel.recordProbe("testcmd \(request.verb) begin")
            let response: Response
            do {
                response = try execute(request)
            } catch {
                response = Response(
                    id: request.id,
                    ok: false,
                    detail: error.localizedDescription,
                    payload: nil
                )
            }

            let data = try JSONEncoder().encode(response)
            try data.write(to: responseURL, options: .atomic)
            AppModel.recordProbe(
                "testcmd \(request.verb) \(response.ok ? "ok" : "failed")"
            )
            if requestURL == commandURL {
                try fileManager.removeItem(at: requestURL)
            }
        } catch {
            AppModel.recordProbe(
                "testcmd channel failed error=\(error.localizedDescription)"
            )
        }
    }

    private func nextRequestURL() throws -> URL? {
        if fileManager.fileExists(atPath: commandURL.path) {
            return commandURL
        }
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        return try fileManager.contentsOfDirectory(
            at: commandsURL,
            includingPropertiesForKeys: Array(keys)
        )
        .filter { requestURL in
            guard requestURL.pathExtension == "json" else { return false }
            let responseURL = responsesURL.appending(
                path: "\(requestURL.deletingPathExtension().lastPathComponent).json"
            )
            return fileManager.fileExists(atPath: responseURL.path) == false
        }
        .sorted { lhs, rhs in
            let lhsDate = try? lhs.resourceValues(forKeys: keys)
                .contentModificationDate
            let rhsDate = try? rhs.resourceValues(forKeys: keys)
                .contentModificationDate
            return (lhsDate ?? .distantPast) < (rhsDate ?? .distantPast)
        }
        .first
    }

#if DEBUG
    private func prepareEvidenceSession(
        for request: Request,
        requestURL: URL
    ) throws {
        guard let evidenceSession = request.args["evidenceSession"],
              evidenceSession.isEmpty == false else { return }
        let currentSession = try? String(
            contentsOf: responseSessionURL,
            encoding: .utf8
        )
        guard currentSession != evidenceSession else { return }
        for responseURL in try fileManager.contentsOfDirectory(
            at: responsesURL,
            includingPropertiesForKeys: nil
        ) where responseURL.pathExtension == "json" {
            try fileManager.removeItem(at: responseURL)
        }
        for queuedCommandURL in try fileManager.contentsOfDirectory(
            at: commandsURL,
            includingPropertiesForKeys: nil
        ) where queuedCommandURL.pathExtension == "json"
            && queuedCommandURL != requestURL {
            try fileManager.removeItem(at: queuedCommandURL)
        }
        try evidenceSession.write(
            to: responseSessionURL,
            atomically: true,
            encoding: .utf8
        )
    }
#endif

    private func execute(_ request: Request) throws -> Response {
        switch request.verb {
        case "ping":
            return Response(id: request.id, ok: true, detail: nil, payload: nil)
        case "toggleControls":
            let requestedVisibility = request.args["visible"].flatMap(Bool.init)
            if requestedVisibility == nil || requestedVisibility != appModel.showControls {
                appModel.toggleControlsFromPlaybackSurface()
            }
            return Response(
                id: request.id,
                ok: true,
                detail: nil,
                payload: [String(appModel.showControls)]
            )
#if DEBUG
        case "setWindowSize":
            return try setWindowSize(request)
        case "openEnvironmentCard":
            let requested = try appModel.requestEnvironmentCard(
                mediaSessionID: playbackRuntime.activeSessionID,
                wasPlaying: playbackRuntime.productLifecycle == .playing
            )
            return Response(
                id: request.id,
                ok: requested,
                detail: requested ? nil : "The environment card request was already pending.",
                payload: [String(describing: appModel.environmentCardResidency)]
            )
        case "dismissEnvironmentCard":
            appModel.environmentCardDismissalRequestRevision &+= 1
            return Response(
                id: request.id,
                ok: true,
                detail: nil,
                payload: [String(appModel.environmentCardDismissalRequestRevision)]
            )
        case "scrollEmby":
            return try scrollEmby(request)
        case "showPlaybackIssue":
            return try showPlaybackIssue(request)
        case "showFileBrowserError":
            return try showFileBrowserError(request)
        case "seekNormalized":
            return try seekNormalized(request)
        case "setDockedPlacement":
            return try setDockedPlacement(request)
        case "listMenuItems":
            return try performMenuSelection(request, operation: .list)
        case "selectMenuItem":
            guard let target = request.args["target"], target.isEmpty == false else {
                throw CommandError(
                    message: "selectMenuItem requires a target argument."
                )
            }
            return try performMenuSelection(
                request,
                operation: .select(target: target)
            )
        case "toggleBlackoutProbeWindow":
            appModel.showBlackoutProbeWindow.toggle()
            return Response(
                id: request.id,
                ok: true,
                detail: nil,
                payload: [String(appModel.showBlackoutProbeWindow)]
            )
#endif
        case "resetState":
            // TestMediaInbox is harness-owned staging, not app state; clearing
            // it here would force a re-push of every media file per cell.
            // The in-memory library must go first: it re-persists itself on
            // mutation and on termination, so leaving it populated resurrects
            // the references this reset just deleted.
            let references = allReferences
            for reference in references {
                mediaLibrary.remove(reference)
            }
            mediaLibrary.navigateToRoot()
            let folders = mediaLibrary.allFolders
            for folder in folders.reversed() {
                mediaLibrary.remove(folder)
            }
            let keys = defaults.dictionaryRepresentation().keys.filter {
                $0.hasPrefix("enchron.")
            }
            for key in keys {
                defaults.removeObject(forKey: key)
            }
            if let folderName = request.args["libraryFolder"],
               folderName.isEmpty == false {
                mediaLibrary.createFolder(named: folderName)
                if let detail = mediaLibrary.lastErrorMessage {
                    throw CommandError(message: detail)
                }
            }
            return Response(
                id: request.id,
                ok: true,
                detail: "Removed \(references.count) library references, "
                    + "removed \(folders.count) library folders, and "
                    + "deleted \(keys.count) enchron.* defaults keys.",
                payload: nil
            )
        case "importMedia":
            guard let fileName = request.args["file"],
                  fileName.isEmpty == false,
                  fileName != ".",
                  fileName != "..",
                  (fileName as NSString).lastPathComponent == fileName else {
                throw CommandError(
                    message: "importMedia requires a direct TestMediaInbox file name."
                )
            }
            let fileURL = inboxURL.appending(
                path: fileName,
                directoryHint: .notDirectory
            )
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(
                atPath: fileURL.path,
                isDirectory: &isDirectory
            ), isDirectory.boolValue == false else {
                throw CommandError(
                    message: "TestMediaInbox does not contain \(fileName)."
                )
            }

            let referenceIDsBeforeImport = Set(allReferences.map(\.id))
            mediaLibrary.addFiles([fileURL])
            if let detail = mediaLibrary.lastErrorMessage {
                throw CommandError(message: detail)
            }
            guard allReferences.contains(where: {
                referenceIDsBeforeImport.contains($0.id) == false
            }) else {
                throw CommandError(
                    message: "The production media import pipeline did not add \(fileName)."
                )
            }
            return Response(
                id: request.id,
                ok: true,
                detail: nil,
                payload: allReferenceNames
            )
        case "listLibrary":
            return Response(
                id: request.id,
                ok: true,
                detail: nil,
                payload: allReferenceNames
            )
        default:
            throw CommandError(
                message: "Unknown app command verb: \(request.verb)."
            )
        }
    }

#if DEBUG && os(visionOS)
    private func performMenuSelection(
        _ request: Request,
        operation: DebugMenuSelectionRequest.Operation
    ) throws -> Response {
        guard let hostText = request.args["host"],
              let host = DebugMenuSelectionHost(rawValue: hostText) else {
            throw CommandError(
                message: "\(request.verb) requires host="
                    + DebugMenuSelectionHost.allCases.map(\.rawValue).joined(separator: "|")
                    + "."
            )
        }
        guard let familyText = request.args["family"],
              let family = DebugMenuSelectionFamily(rawValue: familyText) else {
            throw CommandError(
                message: "\(request.verb) requires family="
                    + DebugMenuSelectionFamily.allCases.map(\.rawValue).joined(separator: "|")
                    + "."
            )
        }

        let menuRequest = DebugMenuSelectionRequest(
            host: host,
            family: family,
            operation: operation
        )
        NotificationCenter.default.post(
            name: .debugMenuSelection,
            object: menuRequest
        )

        switch operation {
        case .list:
            guard let items = menuRequest.items else {
                throw CommandError(
                    message: "No visible \(host.rawValue) host accepted family="
                        + family.rawValue + "."
                )
            }
            return menuResponse(
                request: request,
                host: host,
                family: family,
                items: items
            )
        case .select(let target):
            guard let selectedItem = menuRequest.selectedItem else {
                if let items = menuRequest.items {
                    let available = items.map(\.id).joined(separator: ",")
                    throw CommandError(
                        message: "\(host.rawValue).\(family.rawValue) has no target="
                            + target + "; available=" + available + "."
                    )
                }
                throw CommandError(
                    message: "No visible \(host.rawValue) host accepted family="
                        + family.rawValue + "."
                )
            }
            return menuResponse(
                request: request,
                host: host,
                family: family,
                items: [selectedItem]
            )
        }
    }

    private func menuResponse(
        request: Request,
        host: DebugMenuSelectionHost,
        family: DebugMenuSelectionFamily,
        items: [DebugMenuSelectionSnapshot]
    ) -> Response {
        Response(
            id: request.id,
            ok: true,
            detail: "host=\(host.rawValue) family=\(family.rawValue)",
            payload: items.map(\.id),
            menuItems: items.map {
                Response.MenuItem(
                    id: $0.id,
                    title: $0.title,
                    isSelected: $0.isSelected
                )
            }
        )
    }

    private func seekNormalized(_ request: Request) throws -> Response {
        guard let positionText = request.args["position"],
              let position = Double(positionText),
              position.isFinite,
              (0...1).contains(position) else {
            throw CommandError(
                message: "seekNormalized requires position between 0 and 1."
            )
        }
        let duration = playbackRuntime.playbackPosition.duration
        guard duration > 0 else {
            throw CommandError(message: "seekNormalized requires active playback.")
        }
        let seconds = position * duration
        playbackRuntime.seek(to: seconds, event: .progressBar)
        AppModel.recordProbe(
            "testcmd seekNormalized delivered position=\(position) seconds=\(seconds)"
        )
        return Response(
            id: request.id,
            ok: true,
            detail: nil,
            payload: [String(position), String(seconds)]
        )
    }

    private func setDockedPlacement(_ request: Request) throws -> Response {
        guard appModel.playbackPresentation == .docked else {
            throw CommandError(message: "setDockedPlacement requires Docked playback.")
        }
        guard let axis = request.args["axis"],
              let valueText = request.args["value"],
              let value = Double(valueText),
              value.isFinite else {
            throw CommandError(
                message: "setDockedPlacement requires axis and finite value arguments."
            )
        }
        let applied: Double
        switch axis {
        case "screenSize":
            guard PlaybackScreenSize.scaleRange.contains(value) else {
                throw CommandError(message: "screenSize is outside its product range.")
            }
            appModel.setScreenScale(value)
            applied = appModel.screenScale
        case "distance":
            guard PlaybackDockedPlacement.distanceRange.contains(value) else {
                throw CommandError(message: "distance is outside its product range.")
            }
            appModel.setScreenDistance(value)
            applied = appModel.screenDepthOffset
        case "elevation":
            guard PlaybackDockedPlacement.elevationRange.contains(value) else {
                throw CommandError(message: "elevation is outside its product range.")
            }
            appModel.setScreenElevation(value)
            applied = appModel.screenViewAngle
        default:
            throw CommandError(
                message: "setDockedPlacement axis must be screenSize|distance|elevation."
            )
        }
        AppModel.recordProbe(
            "testcmd setDockedPlacement delivered axis=\(axis) value=\(applied)"
        )
        return Response(
            id: request.id,
            ok: true,
            detail: nil,
            payload: [axis, String(applied)]
        )
    }

    private func showPlaybackIssue(_ request: Request) throws -> Response {
        guard let category = request.args["category"] else {
            throw CommandError(
                message: "showPlaybackIssue requires a category argument."
            )
        }
        let issue: PlaybackUserVisibleIssue = switch category {
        case "mediaOpeningFailed": .mediaOpeningFailed
        case "playbackFailed": .playbackFailed
        case "playbackControlFailed": .playbackControlFailed
        case "mediaFormatChangeFailed": .mediaFormatChangeFailed
        case "presentationConversionFailed": .presentationConversionFailed
        case "surfaceAttachmentFailed": .surfaceAttachmentFailed
        case "environmentLoadingFailed": .environmentLoadingFailed
        case "capabilityUnavailable":
            .capabilityUnavailable(.videoDecoderUnavailable)
        default:
            throw CommandError(
                message: "showPlaybackIssue does not support category \(category)."
            )
        }
        playbackRuntime.setUserVisibleIssue(issue)
        AppModel.recordProbe(
            "testcmd showPlaybackIssue delivered category=\(category)"
        )
        return Response(
            id: request.id,
            ok: true,
            detail: nil,
            payload: [category]
        )
    }

    private func scrollEmby(_ request: Request) throws -> Response {
        guard let page = request.args["page"],
              ["home", "library", "search", "detail"].contains(page) else {
            throw CommandError(
                message: "scrollEmby requires page=home|library|search|detail."
            )
        }
        guard let directionText = request.args["direction"],
              let direction = EmbyReachabilityScrollRequest.Direction(
                  rawValue: directionText
              ) else {
            throw CommandError(
                message: "scrollEmby requires direction=forward|backward."
            )
        }
        let scrollRequest = EmbyReachabilityScrollRequest(
            page: page,
            direction: direction
        ) { deliveredPage in
            AppModel.recordProbe(
                "testcmd scrollEmby delivered page=\(deliveredPage)"
                    + " direction=\(direction.rawValue)"
            )
        }
        NotificationCenter.default.post(
            name: .embyReachabilityScroll,
            object: scrollRequest
        )
        guard let handledPage = scrollRequest.handledPage else {
            throw CommandError(
                message: "No visible Emby page accepted scrollEmby page=\(page)."
            )
        }
        return Response(
            id: request.id,
            ok: true,
            detail: nil,
            payload: [handledPage, direction.rawValue]
        )
    }

    private func showFileBrowserError(_ request: Request) throws -> Response {
        let message = request.args["message"] ?? "Reachability verification error"
        let errorRequest = FileBrowserReachabilityErrorRequest(message: message)
        NotificationCenter.default.post(
            name: .fileBrowserReachabilityError,
            object: errorRequest
        )
        guard errorRequest.wasHandled else {
            throw CommandError(
                message: "No visible Files screen accepted showFileBrowserError."
            )
        }
        return Response(
            id: request.id,
            ok: true,
            detail: nil,
            payload: [message]
        )
    }

    private func setWindowSize(_ request: Request) throws -> Response {
        guard appModel.playbackPresentation == .portal else {
            throw CommandError(message: "setWindowSize requires Portal playback.")
        }
        guard let widthText = request.args["width"],
              let heightText = request.args["height"],
              let width = Double(widthText),
              let height = Double(heightText),
              width.isFinite,
              height.isFinite else {
            throw CommandError(
                message: "setWindowSize requires finite width and height arguments."
            )
        }
        let size = CGSize(width: width, height: height)
        guard PortalWindowLayout.contains(size) else {
            throw CommandError(
                message: "setWindowSize must stay within Portal bounds "
                    + "\(PortalWindowLayout.minimumSize.width)x"
                    + "\(PortalWindowLayout.minimumSize.height)..."
                    + "\(PortalWindowLayout.maximumSize.width)x"
                    + "\(PortalWindowLayout.maximumSize.height)."
            )
        }
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            throw CommandError(message: "setWindowSize found no foreground Window scene.")
        }

        appModel.recordSurfaceInputProbe(
            "setWindowSize requested=\(size.width)x\(size.height)"
        )
        windowScene.requestGeometryUpdate(
            UIWindowScene.GeometryPreferences.Vision(
                size: size,
                minimumSize: PortalWindowLayout.minimumSize,
                maximumSize: PortalWindowLayout.maximumSize,
                resizingRestrictions: .freeform
            )
        ) { [weak appModel] error in
            Task { @MainActor in
                appModel?.recordSurfaceInputProbe(
                    "setWindowSize failed error=\(error.localizedDescription)"
                )
            }
        }
        Task { @MainActor [weak appModel, weak windowScene] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let windowScene else { return }
            let applied = windowScene.effectiveGeometry.coordinateSpace.bounds.size
            appModel?.recordSurfaceInputProbe(
                "setWindowSize observed=\(applied.width)x\(applied.height)"
            )
        }
        return Response(
            id: request.id,
            ok: true,
            detail: nil,
            payload: ["\(size.width)x\(size.height)"]
        )
    }
#elseif DEBUG
    private func setWindowSize(_ request: Request) throws -> Response {
        _ = request
        throw CommandError(message: "setWindowSize requires visionOS.")
    }
#endif

    private var allReferences: [FileBrowsingDomain.MediaReference] {
        let library = mediaLibrary.library
        return library.references(in: nil) + mediaLibrary.allFolders.flatMap {
            library.references(in: $0.id)
        }
    }

    private var allReferenceNames: [String] {
        allReferences.map(\.name)
    }
}

@MainActor
private enum TestCommandChannelBootstrap {
    static var activeChannel: TestCommandChannel?

    static func installIfEnabled(
        environment: [String: String],
        application: EnchronApplication
    ) {
        guard environment["ENCHRON_TEST_CHANNEL"] == "1" else { return }
        do {
            let channel = try TestCommandChannel(
                mediaLibrary: application.mediaLibraryViewModel,
                appModel: application.appModel,
                playbackRuntime: application.playbackRuntime
            )
            activeChannel = channel
            channel.start()
        } catch {
            AppModel.recordProbe(
                "testcmd channel failed error=\(error.localizedDescription)"
            )
        }
    }
}

extension EnchronApplication {
    convenience init() {
        let environment = ProcessInfo.processInfo.environment
        self.init(environment: environment)
        TestCommandChannelBootstrap.installIfEnabled(
            environment: environment,
            application: self
        )
    }
}
