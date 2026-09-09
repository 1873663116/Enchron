import ARKit
import QuartzCore
import simd

@MainActor
final class HeadPoseSource {
    enum Reading: Equatable {
        case pose(simd_float4x4)
        case unavailable(reason: String)

        static let trackingUnavailableReason = "headTrackingUnavailable"
        static let queryReturnedNilReason = "queryReturnedNil"
        static let anchorNotTrackedReason = "anchorNotTracked"
    }

    private struct Holder {
        let onReady: @MainActor () -> Void
        let onFailure: @MainActor (String) -> Void
    }

    private(set) var isRunning = false
    private var session: ARKitSession?
    private var provider: WorldTrackingProvider?
    private var generation = UUID()
    private var holders: [ObjectIdentifier: Holder] = [:]

    func retain(
        _ holder: AnyObject,
        onReady: @escaping @MainActor () -> Void = {},
        onFailure: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        holders[ObjectIdentifier(holder)] = Holder(onReady: onReady, onFailure: onFailure)
        startIfNeeded()
        if isRunning {
            onReady()
        }
    }

    func release(_ holder: AnyObject) {
        guard holders.removeValue(forKey: ObjectIdentifier(holder)) != nil else { return }
        guard holders.isEmpty else { return }
        stop()
    }

    func pose(atTimestamp timestamp: TimeInterval = CACurrentMediaTime()) -> Reading {
        guard isRunning, let provider else {
            return .unavailable(reason: Reading.trackingUnavailableReason)
        }
        guard let anchor = provider.queryDeviceAnchor(atTimestamp: timestamp) else {
            return .unavailable(reason: Reading.queryReturnedNilReason)
        }
        guard anchor.isTracked else {
            return .unavailable(reason: Reading.anchorNotTrackedReason)
        }
        return .pose(anchor.originFromAnchorTransform)
    }

    private func startIfNeeded() {
        guard session == nil,
              holders.isEmpty == false,
              WorldTrackingProvider.isSupported else {
            return
        }

        let session = ARKitSession()
        let provider = WorldTrackingProvider()
        let generation = UUID()
        self.session = session
        self.provider = provider
        self.generation = generation

        Task { @MainActor [weak self] in
            do {
                try await session.run([provider])
                guard let self, self.generation == generation else { return }
                self.isRunning = true
                for holder in self.holders.values { holder.onReady() }
            } catch {
                guard let self, self.generation == generation else { return }
                session.stop()
                self.session = nil
                self.provider = nil
                self.generation = UUID()
                self.isRunning = false
                let reason = error.localizedDescription
                for holder in self.holders.values { holder.onFailure(reason) }
            }
        }
    }

    private func stop() {
        session?.stop()
        session = nil
        provider = nil
        generation = UUID()
        isRunning = false
    }
}
