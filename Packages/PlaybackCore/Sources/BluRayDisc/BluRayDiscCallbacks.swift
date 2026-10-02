import BluRayDiscBridge
import Foundation

private final class BlockingValue<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var result: Result<Value, any Error>?

    func complete(_ result: Result<Value, any Error>) {
        lock.withLock { self.result = result }
        semaphore.signal()
    }

    func wait(untilCancelled: () -> Bool, cancel: () -> Void) throws -> Value {
        while true {
            if untilCancelled() {
                cancel()
                throw CancellationError()
            }
            if semaphore.wait(timeout: .now() + .milliseconds(25)) == .success {
                if untilCancelled() {
                    cancel()
                    throw CancellationError()
                }
                return try lock.withLock { result! }.get()
            }
        }
    }
}

func waitFor<Value: Sendable>(
    box: CallbackBox,
    _ operation: @escaping @Sendable () async throws -> Value
) throws -> Value {
    let generation = box.cancellationGeneration
    if box.isInterrupted(since: generation) { throw CancellationError() }
    let value = BlockingValue<Value>()
    let task = Task.detached(priority: .utility) {
        do { value.complete(.success(try await operation())) }
        catch { value.complete(.failure(error)) }
    }
    return try value.wait(
        untilCancelled: { box.isInterrupted(since: generation) },
        cancel: { task.cancel() }
    )
}

final class CallbackBox: @unchecked Sendable {
    enum Storage: Sendable {
        case image(any BluRayDiscRandomAccessFile)
        case files(any BluRayDiscFileSystem)
    }

    let storage: Storage
    private let lock = NSLock()
    private var cancelled = false
    private var generation: UInt64 = 0

    init(storage: Storage) { self.storage = storage }

    func cancel() { setInterrupted(true) }
    func setInterrupted(_ interrupted: Bool) {
        lock.withLock {
            cancelled = interrupted
            if interrupted { generation &+= 1 }
        }
    }
    var cancellationGeneration: UInt64 { lock.withLock { generation } }
    func isInterrupted(since generation: UInt64) -> Bool {
        lock.withLock { cancelled || self.generation != generation }
    }
    var isCancelled: Bool { lock.withLock { cancelled } }
}

private final class CallbackFile: @unchecked Sendable {
    let file: any BluRayDiscRandomAccessFile
    let size: Int64

    init(file: any BluRayDiscRandomAccessFile, size: Int64) {
        self.file = file
        self.size = size
    }
}

private final class CallbackDirectory: @unchecked Sendable {
    private let lock = NSLock()
    private let names: [String]
    private var index = 0

    init(names: [String]) { self.names = names }

    func next() -> String? {
        lock.withLock {
            guard index < names.count else { return nil }
            defer { index += 1 }
            return names[index]
        }
    }
}

private func context(_ pointer: UnsafeMutableRawPointer?) -> CallbackBox? {
    guard let pointer else { return nil }
    return Unmanaged<CallbackBox>.fromOpaque(pointer).takeUnretainedValue()
}

func makeCallbacks(_ box: CallbackBox) -> PBBlurayIOCallbacks {
    var io = PBBlurayIOCallbacks()
    io.context = Unmanaged.passRetained(box).toOpaque()
    io.imageReadAt = { contextPointer, offset, buffer, count in
        guard let box = context(contextPointer), !box.isCancelled,
              let buffer, offset >= 0, count >= 0, count <= Int.max,
              case .image(let image) = box.storage else { return -1 }
        do {
            let data = try waitFor(box: box) { try await image.read(at: offset, count: Int(count)) }
            guard !box.isCancelled, data.count <= count else { return -1 }
            data.withUnsafeBytes { source in
                if let base = source.baseAddress { memcpy(buffer, base, data.count) }
            }
            return Int64(data.count)
        } catch { return -1 }
    }
    io.fileOpen = { contextPointer, relativePath, size in
        guard let box = context(contextPointer), !box.isCancelled,
              let relativePath, let size,
              case .files(let files) = box.storage else { return nil }
        let path = String(cString: relativePath)
        do {
            let opened = try waitFor(box: box) {
                let file = try await files.openFile(at: path)
                return CallbackFile(file: file, size: try await file.size)
            }
            guard !box.isCancelled else { return nil }
            size.pointee = opened.size
            return Unmanaged.passRetained(opened).toOpaque()
        } catch { return nil }
    }
    io.fileReadAt = { contextPointer, filePointer, offset, buffer, count in
        guard let box = context(contextPointer), !box.isCancelled,
              let filePointer, let buffer, offset >= 0, count >= 0, count <= Int.max else {
            return -1
        }
        let opened = Unmanaged<CallbackFile>.fromOpaque(filePointer).takeUnretainedValue()
        do {
            let data = try waitFor(box: box) { try await opened.file.read(at: offset, count: Int(count)) }
            guard !box.isCancelled, data.count <= count else { return -1 }
            data.withUnsafeBytes { source in
                if let base = source.baseAddress { memcpy(buffer, base, data.count) }
            }
            return Int64(data.count)
        } catch { return -1 }
    }
    io.fileClose = { _, filePointer in
        guard let filePointer else { return }
        Unmanaged<CallbackFile>.fromOpaque(filePointer).release()
    }
    io.directoryOpen = { contextPointer, relativePath in
        guard let box = context(contextPointer), !box.isCancelled,
              let relativePath, case .files(let files) = box.storage else { return nil }
        let path = String(cString: relativePath)
        do {
            let names = try waitFor(box: box) { try await files.contents(of: path) }
            guard !box.isCancelled else { return nil }
            return Unmanaged.passRetained(CallbackDirectory(names: names)).toOpaque()
        } catch { return nil }
    }
    io.directoryNext = { _, directoryPointer, name, capacity in
        guard let directoryPointer, let name else { return -1 }
        let directory = Unmanaged<CallbackDirectory>
            .fromOpaque(directoryPointer).takeUnretainedValue()
        guard let next = directory.next() else { return 1 }
        let bytes = next.utf8CString
        guard bytes.count <= capacity else { return -1 }
        bytes.withUnsafeBufferPointer { source in
            if let base = source.baseAddress {
                name.update(from: base, count: bytes.count)
            }
        }
        return 0
    }
    io.directoryClose = { _, directoryPointer in
        guard let directoryPointer else { return }
        Unmanaged<CallbackDirectory>.fromOpaque(directoryPointer).release()
    }
    io.isCancelled = { contextPointer in
        context(contextPointer)?.isCancelled ?? true
    }
    io.setInterrupted = { contextPointer, interrupted in
        context(contextPointer)?.setInterrupted(interrupted)
    }
    io.contextClose = { contextPointer in
        guard let contextPointer else { return }
        Unmanaged<CallbackBox>.fromOpaque(contextPointer).release()
    }
    return io
}

actor HTTPRangeFile: BluRayDiscRandomAccessFile {
    private let url: URL
    private var knownSize: Int64?

    init(url: URL) { self.url = url }

    var size: Int64 {
        get async throws {
            if let knownSize { return knownSize }
            _ = try await read(at: 0, count: 1)
            guard let knownSize else { throw BluRayDiscError.io("Range response has no size.") }
            return knownSize
        }
    }

    func read(at offset: Int64, count: Int) async throws -> Data {
        guard offset >= 0, count >= 0,
              count == 0 || offset <= Int64.max - Int64(count) else {
            throw BluRayDiscError.io("Invalid image range.")
        }
        if count == 0 { return Data() }
        var request = URLRequest(url: url)
        request.setValue("bytes=\(offset)-\(offset + Int64(count) - 1)",
                         forHTTPHeaderField: "Range")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 206,
              let range = response.value(forHTTPHeaderField: "Content-Range"),
              range.hasPrefix("bytes "),
              let dash = range.firstIndex(of: "-"),
              let slash = range.lastIndex(of: "/"), dash < slash,
              let start = Int64(range[range.index(range.startIndex, offsetBy: 6)..<dash]),
              let end = Int64(range[range.index(after: dash)..<slash]),
              let total = Int64(range[range.index(after: slash)...]),
              start == offset, end >= start, end < total,
              end - start + 1 == Int64(data.count), data.count <= count else {
            throw BluRayDiscError.io("Disc source did not honor the byte range request.")
        }
        knownSize = total
        return data
    }
}
