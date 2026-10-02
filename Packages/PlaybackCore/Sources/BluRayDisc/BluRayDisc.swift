import BluRayDiscBridge
import Foundation

public struct BluRayPlaylistID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

public enum BluRayStreamKind: Sendable, Equatable {
    case video
    case audio
    case subtitle
}

public struct BluRayStream: Sendable, Equatable {
    public let pid: UInt16
    public let codingType: UInt8
    public let kind: BluRayStreamKind
    public let language: String?

    public init(pid: UInt16, codingType: UInt8, kind: BluRayStreamKind, language: String?) {
        self.pid = pid
        self.codingType = codingType
        self.kind = kind
        self.language = language
    }
}

public struct BluRayClip: Sendable, Equatable {
    public let clipID: String
    public let startTimeSeconds: Double
    public let inTimeSeconds: Double
    public let outTimeSeconds: Double
    public let byteStart: UInt64
    public let byteEnd: UInt64
    public let packetCount: UInt32
    public let streams: [BluRayStream]

    public init(
        clipID: String,
        startTimeSeconds: Double,
        inTimeSeconds: Double,
        outTimeSeconds: Double,
        byteStart: UInt64,
        byteEnd: UInt64,
        packetCount: UInt32,
        streams: [BluRayStream]
    ) {
        self.clipID = clipID
        self.startTimeSeconds = startTimeSeconds
        self.inTimeSeconds = inTimeSeconds
        self.outTimeSeconds = outTimeSeconds
        self.byteStart = byteStart
        self.byteEnd = byteEnd
        self.packetCount = packetCount
        self.streams = streams
    }
}

public struct BluRayDiscTitle: Sendable, Equatable, Identifiable {
    public var id: BluRayPlaylistID { playlistID }
    public let playlistID: BluRayPlaylistID
    public let ordinal: Int
    public let optionalName: String?
    public let durationSeconds: Double
    public let isMain: Bool
    public let clips: [BluRayClip]

    public init(
        playlistID: BluRayPlaylistID,
        ordinal: Int,
        optionalName: String? = nil,
        durationSeconds: Double,
        isMain: Bool = false,
        clips: [BluRayClip] = []
    ) {
        self.playlistID = playlistID
        self.ordinal = ordinal
        self.optionalName = optionalName
        self.durationSeconds = durationSeconds
        self.isMain = isMain
        self.clips = clips
    }
}

public struct BluRayDiscCatalog: Sendable, Equatable {
    public let titles: [BluRayDiscTitle]

    public init(titles: [BluRayDiscTitle]) {
        self.titles = titles
    }
}

public protocol BluRayDiscRandomAccessFile: Sendable {
    var size: Int64 { get async throws }
    func read(at offset: Int64, count: Int) async throws -> Data
}

public protocol BluRayDiscFileSystem: Sendable {
    func contents(of relativePath: String) async throws -> [String]
    func openFile(at relativePath: String) async throws -> any BluRayDiscRandomAccessFile
}

public enum BluRayDiscSource: @unchecked Sendable, Equatable {
    case url(URL)
    case fileSystem(rootURL: URL, any BluRayDiscFileSystem)

    public var rootURL: URL {
        switch self {
        case .url(let url): url
        case .fileSystem(let rootURL, _): rootURL
        }
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.rootURL.standardized == rhs.rootURL.standardized
    }
}

public enum BluRayDiscError: LocalizedError, Sendable, Equatable {
    case encrypted
    case corrupt(String)
    case unsupported(String)
    case io(String)

    public var errorDescription: String? {
        switch self {
        case .encrypted: "This encrypted Blu-ray disc is unsupported."
        case .corrupt(let message), .unsupported(let message), .io(let message): message
        }
    }

    fileprivate init(bridgeMessage: String) {
        if bridgeMessage.hasPrefix("encrypted:") {
            self = .encrypted
        } else if bridgeMessage.hasPrefix("corrupt:") {
            self = .corrupt(String(bridgeMessage.dropFirst("corrupt: ".count)))
        } else if bridgeMessage.hasPrefix("unsupported:") {
            self = .unsupported(String(bridgeMessage.dropFirst("unsupported: ".count)))
        } else {
            self = .io(bridgeMessage.hasPrefix("io: ")
                ? String(bridgeMessage.dropFirst("io: ".count)) : bridgeMessage)
        }
    }
}

public final class BluRayDiscReader: @unchecked Sendable {
    private let lock = NSLock()
    private var handle: OpaquePointer?

    fileprivate init(handle: OpaquePointer) {
        self.handle = handle
    }

    deinit {
        if let handle = lock.withLock({ self.handle }) {
            PBBlurayClose(handle)
        }
    }

    /// Transfers the reader and its callback context to PlaybackFFmpegBridge.
    /// The caller must close the returned handle exactly once with PBBlurayClose.
    public func takeNativeHandle() -> OpaquePointer? {
        lock.withLock {
            defer { handle = nil }
            return handle
        }
    }
}

public enum BluRayDisc {
    public static func catalog(at url: URL) throws -> BluRayDiscCatalog {
        guard url.isFileURL else {
            throw BluRayDiscError.unsupported("Use catalog(source:) for a remote disc image.")
        }
        var error = [CChar](repeating: 0, count: 512)
        let pointer = url.withUnsafeFileSystemRepresentation { path in
            PBBlurayCatalogOpen(path, &error, error.count)
        }
        guard let pointer else { throw BluRayDiscError(bridgeMessage: errorMessage(error)) }
        defer { PBBlurayCatalogClose(pointer) }
        return decodeCatalog(pointer)
    }

    public static func catalog(source: BluRayDiscSource) async throws -> BluRayDiscCatalog {
        switch source {
        case .url(let url) where url.isFileURL:
            return try await Task.detached(priority: .utility) { try catalog(at: url) }.value
        case .url(let url):
            return try await catalog(image: HTTPRangeFile(url: url))
        case .fileSystem(_, let files):
            return try await catalog(files: files)
        }
    }

    public static func catalog(files: any BluRayDiscFileSystem) async throws -> BluRayDiscCatalog {
        try await catalog(box: CallbackBox(storage: .files(files)), kind: PBBlurayAccessFiles)
    }

    public static func catalog(image: any BluRayDiscRandomAccessFile) async throws -> BluRayDiscCatalog {
        try await catalog(box: CallbackBox(storage: .image(image)), kind: PBBlurayAccessImage)
    }

    public static func open(source: BluRayDiscSource, playlistID: BluRayPlaylistID) async throws -> BluRayDiscReader {
        switch source {
        case .url(let url) where url.isFileURL:
            return try await Task.detached(priority: .utility) {
                var error = [CChar](repeating: 0, count: 512)
                let pointer = url.withUnsafeFileSystemRepresentation { path in
                    PBBlurayOpen(path, playlistID.rawValue, &error, error.count)
                }
                guard let pointer else {
                    throw BluRayDiscError(bridgeMessage: errorMessage(error))
                }
                return BluRayDiscReader(handle: pointer)
            }.value
        case .url(let url):
            return try await open(box: CallbackBox(storage: .image(HTTPRangeFile(url: url))),
                                  kind: PBBlurayAccessImage, playlistID: playlistID)
        case .fileSystem(_, let files):
            return try await open(box: CallbackBox(storage: .files(files)),
                                  kind: PBBlurayAccessFiles, playlistID: playlistID)
        }
    }

    private static func catalog(box: CallbackBox, kind: PBBlurayAccessKind) async throws -> BluRayDiscCatalog {
        try await withTaskCancellationHandler {
            try await Task.detached(priority: .utility) {
                var error = [CChar](repeating: 0, count: 512)
                var io = makeCallbacks(box)
                let pointer = PBBlurayCatalogOpenWithIO(kind, &io, &error, error.count)
                guard let pointer else {
                    throw BluRayDiscError(bridgeMessage: errorMessage(error))
                }
                defer { PBBlurayCatalogClose(pointer) }
                return decodeCatalog(pointer)
            }.value
        } onCancel: {
            box.cancel()
        }
    }

    private static func open(box: CallbackBox, kind: PBBlurayAccessKind,
                             playlistID: BluRayPlaylistID) async throws -> BluRayDiscReader {
        try await withTaskCancellationHandler {
            try await Task.detached(priority: .utility) {
                var error = [CChar](repeating: 0, count: 512)
                var io = makeCallbacks(box)
                let pointer = PBBlurayOpenWithIO(kind, &io, playlistID.rawValue,
                                                  &error, error.count)
                guard let pointer else {
                    throw BluRayDiscError(bridgeMessage: errorMessage(error))
                }
                return BluRayDiscReader(handle: pointer)
            }.value
        } onCancel: {
            box.cancel()
        }
    }

    private static func decodeCatalog(_ pointer: OpaquePointer) -> BluRayDiscCatalog {
        let titles = (0..<PBBlurayCatalogCount(pointer)).compactMap { index -> BluRayDiscTitle? in
            var raw = PBBlurayTitleInfo()
            guard PBBlurayCatalogTitleAt(pointer, index, &raw) else { return nil }
            let clips = (0..<raw.clipCount).compactMap { clipIndex -> BluRayClip? in
                var clip = PBBlurayClipInfo()
                guard PBBlurayCatalogClipAt(pointer, index, clipIndex, &clip) else { return nil }
                let streams = (0..<clip.streamCount).compactMap { streamIndex -> BluRayStream? in
                    var stream = PBBlurayStreamInfo()
                    guard PBBlurayCatalogStreamAt(pointer, index, clipIndex, streamIndex, &stream) else {
                        return nil
                    }
                    return decodeStream(stream)
                }
                return decodeClip(clip, streams: streams)
            }
            let name = stringFromTuple(raw.optionalName)
            return BluRayDiscTitle(
                playlistID: BluRayPlaylistID(rawValue: raw.playlistID),
                ordinal: Int(index) + 1,
                optionalName: name.isEmpty ? nil : name,
                durationSeconds: Double(raw.duration90k) / 90_000,
                isMain: raw.isMain,
                clips: clips
            )
        }
        return BluRayDiscCatalog(titles: titles)
    }

    private static func errorMessage(_ bytes: [CChar]) -> String {
        String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
               as: UTF8.self)
    }

    private static func decodeClip(_ raw: PBBlurayClipInfo,
                                   streams: [BluRayStream]) -> BluRayClip {
        BluRayClip(
            clipID: stringFromTuple(raw.clipID),
            startTimeSeconds: Double(raw.startTime90k) / 90_000,
            inTimeSeconds: Double(raw.inTime90k) / 90_000,
            outTimeSeconds: Double(raw.outTime90k) / 90_000,
            byteStart: raw.byteStart,
            byteEnd: raw.byteEnd,
            packetCount: raw.packetCount,
            streams: streams
        )
    }

    private static func decodeStream(_ raw: PBBlurayStreamInfo) -> BluRayStream? {
        let kind: BluRayStreamKind
        switch UInt32(raw.kind) {
        case PBBlurayStreamVideo.rawValue: kind = .video
        case PBBlurayStreamAudio.rawValue: kind = .audio
        case PBBlurayStreamSubtitle.rawValue: kind = .subtitle
        default: return nil
        }
        let language = stringFromTuple(raw.language)
        return BluRayStream(pid: raw.pid, codingType: raw.codingType,
                            kind: kind, language: language.isEmpty ? nil : language)
    }

    private static func stringFromTuple<T>(_ tuple: T) -> String {
        withUnsafeBytes(of: tuple) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
