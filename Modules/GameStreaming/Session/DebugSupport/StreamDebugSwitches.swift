import Foundation

enum StreamDebugSwitches {
    static let disabled: Set<String> = {
#if DEBUG
        let raw = ProcessInfo.processInfo.environment["ENCHRON_STREAM_DISABLE"] ?? ""
        return Set(raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
#else
        return []
#endif
    }()

    static func isDisabled(_ name: String) -> Bool {
        disabled.contains(name)
    }
}

final class StreamStallWatch: @unchecked Sendable {
    static let shared = StreamStallWatch()

    private let lock = NSLock()
    private var running = false
    private var generation = 0
    private var stalls: [String: (count: Int, maxMs: Int)] = [:]

    func start() {
#if DEBUG
        lock.lock()
        defer { lock.unlock() }
        guard !running else { return }
        running = true
        generation += 1
        let current = generation
        for (name, qos) in [("hi", QualityOfService.userInteractive), ("def", QualityOfService.default)] {
            let thread = Thread { [weak self] in self?.run(name: name, generation: current) }
            thread.qualityOfService = qos
            thread.name = "StreamStallWatch.\(name)"
            thread.start()
        }
#endif
    }

    func stop() {
        lock.lock()
        running = false
        lock.unlock()
    }

    func drain() -> String {
        lock.lock()
        defer { lock.unlock() }
        let text = ["hi", "def"].map { name in
            let value = stalls[name] ?? (0, 0)
            return "stall\(name)=\(value.count) stall\(name)MaxMs=\(value.maxMs)"
        }.joined(separator: " ")
        stalls = [:]
        return text
    }

    private func run(name: String, generation current: Int) {
        var last = DispatchTime.now().uptimeNanoseconds
        while true {
            usleep(2_000)
            let now = DispatchTime.now().uptimeNanoseconds
            let late = Int((now - last) / 1_000_000) - 2
            last = now
            lock.lock()
            guard running, generation == current else {
                lock.unlock()
                return
            }
            if late > 50 {
                var value = stalls[name] ?? (0, 0)
                value.count += 1
                value.maxMs = max(value.maxMs, late)
                stalls[name] = value
            }
            lock.unlock()
        }
    }
}
