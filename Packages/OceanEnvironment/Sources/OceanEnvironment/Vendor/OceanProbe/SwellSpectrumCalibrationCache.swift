@MainActor
final class SwellSpectrumCalibrationCache {
    static let shared = SwellSpectrumCalibrationCache()

    private enum Entry {
        case preparing(Task<SwellSpectrumCalibration, Never>)
        case ready(SwellSpectrumCalibration)
    }

    private var entries: [SwellSpectrumCalibration.Input: Entry] = [:]

    func value(for parameters: OceanProbeParameters) async -> SwellSpectrumCalibration {
        switch entry(for: .init(parameters)) {
        case .ready(let calibration):
            return calibration
        case .preparing(let task):
            return await task.value
        }
    }

    func readyValue(for parameters: OceanProbeParameters) -> SwellSpectrumCalibration? {
        switch entry(for: .init(parameters)) {
        case .ready(let calibration): calibration
        case .preparing: nil
        }
    }

    private func entry(for input: SwellSpectrumCalibration.Input) -> Entry {
        if let existing = entries[input] { return existing }
        let task = Task {
            let calibration = await Task.detached(priority: .userInitiated) {
                SwellSpectrumCalibration(parameters: input)
            }.value
            entries[input] = .ready(calibration)
            return calibration
        }
        let entry = Entry.preparing(task)
        entries[input] = entry
        return entry
    }
}
