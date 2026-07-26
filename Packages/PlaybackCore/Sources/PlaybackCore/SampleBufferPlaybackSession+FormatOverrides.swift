@preconcurrency import AVFoundation
import Foundation
import OSLog

extension SampleBufferPlaybackSession {
    public var effectiveStereoLayout: VideoStereoLayout {
        let snapshot = debugStore.snapshot()
        if let sample = snapshot.lastVideoSample,
           let input = snapshot.lastAcceptedRendererInput,
           input.sourceEventID == sample.sourceEventID,
           input.formatRevision == sample.formatRevision,
           input.outcome == .accepted {
            return Self.stereoLayout(
                forViewPackingKind: sample.formatSignaling.viewPackingKind.value
            )
        }
        let explicit = deliveryQueue.sync { stereoLayoutOverride }
        if let explicit { return explicit }
        let packing = snapshot.providerOpen?.formatSignaling.viewPackingKind.value
        return Self.stereoLayout(forViewPackingKind: packing)
    }

    @discardableResult
    func setStereoLayout(_ layout: VideoStereoLayout) async throws -> UInt64 {
        try await setStereoLayoutOverride(layout)
    }

    @discardableResult
    func clearStereoLayoutOverride() async throws -> UInt64 {
        try await setStereoLayoutOverride(nil)
    }

    func setStereoLayoutOverride(
        _ layout: VideoStereoLayout?
    ) async throws -> UInt64 {
        guard !isClosed else { throw PlaybackControlError.mediaSessionClosed }
        let currentOverride = deliveryQueue.sync { stereoLayoutOverride }
        if currentOverride == layout {
            let state = deliveryQueue.sync { (hasRequestedVideoData, formatRevision) }
            if !state.0 { return state.1 }
            return try await waitForStereoLayout(
                layout,
                minimumRevision: state.1
            )
        }
        if deliveryQueue.sync(execute: { hasRequestedVideoData }), videoProviderHasEnded {
            throw CorePlaybackError.stereoOverrideUnavailable(layout)
        }

        let change = applyStereoLayoutOverride(layout)
        debugStore.emit(
            mediaSessionID: traceID,
            node: .rendererInputCoordination,
            kind: "control.stereo.started",
            outcome: .succeeded,
            details: [
                "layout": layout?.rawValue ?? "source",
                "formatRevision": String(change.revision),
            ]
        )
        guard change.awaitsSample else {
            debugStore.emit(
                mediaSessionID: traceID,
                node: .rendererInputCoordination,
                kind: "control.stereo.completed",
                outcome: .succeeded,
                details: [
                    "layout": layout?.rawValue ?? "source",
                    "formatRevision": String(change.revision),
                    "boundary": "beforeFirstSample",
                ]
            )
            return change.revision
        }

        let effectiveRevision: UInt64
        do {
            effectiveRevision = try await waitForStereoLayout(
                layout,
                minimumRevision: change.revision
            )
        } catch {
            if error is CancellationError || Task.isCancelled {
                debugStore.emit(
                    mediaSessionID: traceID,
                    node: .rendererInputCoordination,
                    kind: "control.stereo.cancelled",
                    outcome: .terminatedByCleanup,
                    details: ["layout": layout?.rawValue ?? "source"]
                )
                throw error
            }
            let rollback = applyStereoLayoutOverride(change.previous)
            var rollbackState = "restoredBeforeFirstSample"
            if rollback.awaitsSample {
                do {
                    _ = try await waitForStereoLayout(
                        change.previous,
                        minimumRevision: rollback.revision
                    )
                    rollbackState = "restored"
                } catch {
                    rollbackState = "failed"
                }
            }
            debugStore.emit(
                mediaSessionID: traceID,
                node: .rendererInputCoordination,
                kind: "control.stereo.failed",
                outcome: .failed,
                details: [
                    "layout": layout?.rawValue ?? "source",
                    "rollback": rollbackState,
                    "error": error.localizedDescription,
                ]
            )
            throw error
        }

        debugStore.emit(
            mediaSessionID: traceID,
            node: .rendererInputCoordination,
            kind: "control.stereo.completed",
            outcome: .succeeded,
            details: [
                "layout": layout?.rawValue ?? "source",
                "formatRevision": String(effectiveRevision),
            ]
        )
        return effectiveRevision
    }

    struct StereoLayoutChange {
        let previous: VideoStereoLayout?
        let revision: UInt64
        let awaitsSample: Bool
        let shouldResumeDelivery: Bool
    }

    func applyStereoLayoutOverride(
        _ layout: VideoStereoLayout?
    ) -> StereoLayoutChange {
        stopVideoDelivery()
        let change = deliveryQueue.sync {
            let providerResetIsInFlight = isResetting
            let previous = stereoLayoutOverride
            stereoLayoutOverride = layout
            if diagnostics.enqueuedSampleCount > 0 {
                formatRevision += 1
            }
            didRecordFormat = false
            let awaitsSample = hasRequestedVideoData
                && !videoProviderHasEnded
                && !isClosed
                && !isVideoRendererFailed
            return StereoLayoutChange(
                previous: previous,
                revision: formatRevision,
                awaitsSample: awaitsSample,
                shouldResumeDelivery: awaitsSample && !providerResetIsInFlight
            )
        }
        if change.shouldResumeDelivery {
            startVideoDelivery()
        }
        return change
    }

    func waitForStereoLayout(
        _ layout: VideoStereoLayout?,
        minimumRevision: UInt64
    ) async throws -> UInt64 {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            let snapshot = debugStore.snapshot()
            if let sample = snapshot.lastVideoSample,
               let input = snapshot.lastAcceptedRendererInput,
               sample.formatRevision >= minimumRevision,
               input.formatRevision == sample.formatRevision,
               input.sourceEventID == sample.sourceEventID,
               input.outcome == .accepted,
               stereoLayout(layout, matches: sample.formatSignaling.viewPackingKind.value) {
                return sample.formatRevision
            }
            if videoProviderHasEnded {
                break
            }
            if isClosed { throw CancellationError() }
            if isVideoRendererFailed {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw CorePlaybackError.stereoOverrideTimedOut(layout)
    }

    func stereoLayout(
        _ layout: VideoStereoLayout?,
        matches viewPackingKind: String?
    ) -> Bool {
        guard let layout else {
            let sourcePacking = debugStore.snapshot().providerOpen?
                .formatSignaling.viewPackingKind.value
            return Self.normalizedPacking(viewPackingKind) == Self.normalizedPacking(sourcePacking)
        }
        switch layout {
        case .mono:
            return viewPackingKind == nil
        case .sideBySide:
            return Self.normalizedPacking(viewPackingKind).contains("sidebyside")
        case .overUnder:
            return Self.normalizedPacking(viewPackingKind).contains("overunder")
        }
    }

    static func stereoLayout(forViewPackingKind value: String?) -> VideoStereoLayout {
        let normalized = normalizedPacking(value)
        if normalized.contains("sidebyside") { return .sideBySide }
        if normalized.contains("overunder") || normalized.contains("topbottom") {
            return .overUnder
        }
        return .mono
    }

    static func normalizedPacking(_ value: String?) -> String {
        (value ?? "")
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    public var effectiveProjectionKind: String? {
        let snapshot = debugStore.snapshot()
        if let sample = snapshot.lastVideoSample,
           let input = snapshot.lastAcceptedRendererInput,
           input.sourceEventID == sample.sourceEventID,
           input.formatRevision == sample.formatRevision,
           input.outcome == .accepted {
            return sample.formatSignaling.projectionKind.value
        }
        if let projection = deliveryQueue.sync(execute: { projectionOverride }) {
            return Self.projectionKind(for: projection)
        }
        return snapshot.providerOpen?.formatSignaling.projectionKind.value
    }

    @discardableResult
    func setProjectionOverride(_ projection: VideoProjectionOverride) async throws -> UInt64 {
        try await setProjectionOverrideValue(projection)
    }

    @discardableResult
    func clearProjectionOverride() async throws -> UInt64 {
        try await setProjectionOverrideValue(nil)
    }

    func setProjectionOverrideValue(
        _ projection: VideoProjectionOverride?
    ) async throws -> UInt64 {
        guard !isClosed else { throw PlaybackControlError.mediaSessionClosed }
        let currentOverride = deliveryQueue.sync { projectionOverride }
        if currentOverride == projection {
            let state = deliveryQueue.sync { (hasRequestedVideoData, formatRevision) }
            if !state.0 { return state.1 }
            return try await waitForProjectionOverride(
                projection,
                minimumRevision: state.1
            )
        }
        if deliveryQueue.sync(execute: { hasRequestedVideoData }), videoProviderHasEnded {
            throw CorePlaybackError.projectionOverrideUnavailable(projection)
        }

        let change = applyProjectionOverride(projection)
        debugStore.emit(
            mediaSessionID: traceID,
            node: .rendererInputCoordination,
            kind: "control.projection.started",
            outcome: .succeeded,
            details: [
                "projection": projection?.rawValue ?? "source",
                "formatRevision": String(change.revision),
            ]
        )
        guard change.awaitsSample else {
            debugStore.emit(
                mediaSessionID: traceID,
                node: .rendererInputCoordination,
                kind: "control.projection.completed",
                outcome: .succeeded,
                details: [
                    "projection": projection?.rawValue ?? "source",
                    "formatRevision": String(change.revision),
                    "boundary": "beforeFirstSample",
                ]
            )
            return change.revision
        }

        let effectiveRevision: UInt64
        do {
            effectiveRevision = try await waitForProjectionOverride(
                projection,
                minimumRevision: change.revision
            )
        } catch {
            if error is CancellationError || Task.isCancelled {
                debugStore.emit(
                    mediaSessionID: traceID,
                    node: .rendererInputCoordination,
                    kind: "control.projection.cancelled",
                    outcome: .terminatedByCleanup,
                    details: ["projection": projection?.rawValue ?? "source"]
                )
                throw error
            }
            let rollback = applyProjectionOverride(change.previous)
            var rollbackState = "restoredBeforeFirstSample"
            if rollback.awaitsSample {
                do {
                    _ = try await waitForProjectionOverride(
                        change.previous,
                        minimumRevision: rollback.revision
                    )
                    rollbackState = "restored"
                } catch {
                    rollbackState = "failed"
                }
            }
            debugStore.emit(
                mediaSessionID: traceID,
                node: .rendererInputCoordination,
                kind: "control.projection.failed",
                outcome: .failed,
                details: [
                    "projection": projection?.rawValue ?? "source",
                    "rollback": rollbackState,
                    "error": error.localizedDescription,
                ]
            )
            throw error
        }

        debugStore.emit(
            mediaSessionID: traceID,
            node: .rendererInputCoordination,
            kind: "control.projection.completed",
            outcome: .succeeded,
            details: [
                "projection": projection?.rawValue ?? "source",
                "formatRevision": String(effectiveRevision),
            ]
        )
        return effectiveRevision
    }

    struct ProjectionChange {
        let previous: VideoProjectionOverride?
        let revision: UInt64
        let awaitsSample: Bool
        let shouldResumeDelivery: Bool
    }

    func applyProjectionOverride(
        _ projection: VideoProjectionOverride?
    ) -> ProjectionChange {
        stopVideoDelivery()
        let change = deliveryQueue.sync {
            let providerResetIsInFlight = isResetting
            let previous = projectionOverride
            projectionOverride = projection
            if diagnostics.enqueuedSampleCount > 0 {
                formatRevision += 1
            }
            didRecordFormat = false
            let awaitsSample = hasRequestedVideoData
                && !videoProviderHasEnded
                && !isClosed
                && !isVideoRendererFailed
            return ProjectionChange(
                previous: previous,
                revision: formatRevision,
                awaitsSample: awaitsSample,
                shouldResumeDelivery: awaitsSample && !providerResetIsInFlight
            )
        }
        if change.shouldResumeDelivery {
            startVideoDelivery()
        }
        return change
    }

    func waitForProjectionOverride(
        _ projection: VideoProjectionOverride?,
        minimumRevision: UInt64
    ) async throws -> UInt64 {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            let snapshot = debugStore.snapshot()
            if let sample = snapshot.lastVideoSample,
               let input = snapshot.lastAcceptedRendererInput,
               sample.formatRevision >= minimumRevision,
               input.formatRevision == sample.formatRevision,
               input.sourceEventID == sample.sourceEventID,
               input.outcome == .accepted,
               projectionOverride(
                   projection,
                   matches: sample.formatSignaling.projectionKind.value,
                   source: snapshot.providerOpen?.formatSignaling.projectionKind.value
               ) {
                return sample.formatRevision
            }
            if isClosed { throw CancellationError() }
            if videoProviderHasEnded || isVideoRendererFailed { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw CorePlaybackError.projectionOverrideTimedOut(projection)
    }

    func projectionOverride(
        _ projection: VideoProjectionOverride?,
        matches projectionKind: String?,
        source sourceProjectionKind: String?
    ) -> Bool {
        let normalized = Self.normalizedProjection(projectionKind)
        switch projection {
        case .rectilinear:
            return normalized.contains("rectilinear")
        case .equirectangular:
            return normalized.contains("equirectangular")
                && !normalized.contains("halfequirectangular")
        case .halfEquirectangular:
            return normalized.contains("halfequirectangular")
        case nil:
            return normalized == Self.normalizedProjection(sourceProjectionKind)
        }
    }

    static func projectionKind(for projection: VideoProjectionOverride) -> String {
        switch projection {
        case .rectilinear:
            kCMFormatDescriptionProjectionKind_Rectilinear as String
        case .equirectangular:
            kCMFormatDescriptionProjectionKind_Equirectangular as String
        case .halfEquirectangular:
            kCMFormatDescriptionProjectionKind_HalfEquirectangular as String
        }
    }

    static func normalizedProjection(_ value: String?) -> String {
        (value ?? "")
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

}
