import AVFoundation
import CoreMedia
import Foundation
import Testing

@testable import Playback

@MainActor
struct RendererTransferCoordinatorTests {
    @Test("successful handoff changes ownership only after cutover")
    func successfulHandoffOrdering() async throws {
        let coordinator = RendererTransferCoordinator()
        let source = try await Self.openedDriver(named: "handoff-source")
        let replacement = try await Self.openedDriver(named: "handoff-replacement")
        defer {
            try? FileManager.default.removeItem(at: source.url)
            try? FileManager.default.removeItem(at: replacement.url)
        }
        let key = RendererTransferCoordinator.TransferKey(
            generation: 7,
            logicalSessionID: "logical",
            sourceTechnicalSessionID: source.resource.sessionID
        )
        try coordinator.installActive(source.resource)
        #expect(
            coordinator.claimConsumer(
                presentation: .portal,
                entityID: "source-entity"
            ) == .granted(discarded: nil)
        )
        #expect(
            coordinator.recordRendererTargetBinding(
                revision: 4,
                currentRevision: 4,
                entityID: "source-entity"
            ) != nil
        )
        try coordinator.beginTransfer(key: key, mode: .technicalSession)
        try coordinator.finishTechnicalSessionPreparation(
            key: key,
            replacement: .init(
                resource: replacement.resource,
                speed: .default,
                selectedAudioTrackID: "1",
                selectedSubtitleTrackID: "subtitle"
            )
        )
        var cutoverObservations: [RendererTransferCoordinator.Phase] = []

        let activation = try coordinator.activateTechnicalSession(
            key: key,
            cutoverTime: CMTime(seconds: 12, preferredTimescale: 600),
            endedContinuity: nil,
            sourcePresentation: .portal,
            naturalEndNotificationWasPublished: false,
            beforeCutover: {
                cutoverObservations.append(coordinator.phase)
                #expect(coordinator.activeDriver === source.driver)
                #expect(coordinator.activeRenderer === source.resource.renderer)
                #expect(
                    coordinator.consumerSnapshot.presentation == .portal
                )
            }
        )

        #expect(cutoverObservations == [.prepared])
        #expect(coordinator.phase == .cutover)
        #expect(coordinator.activeDriver === replacement.driver)
        #expect(coordinator.activeRenderer === replacement.resource.renderer)
        #expect(coordinator.consumerSnapshot.presentation == nil)
        #expect(coordinator.consumerSnapshot.entityID == nil)
        #expect(
            coordinator.consumerSnapshot.boundVideoComponentRevision == nil
        )
        #expect(activation.activeResource.driver === replacement.driver)
        #expect(coordinator.completeCutover(activation.token))
        #expect(coordinator.phase == .settled)
        #expect(
            await coordinator.retireDepartingAfterSceneDisappearance()
                == .technicalSession
        )
        #expect(coordinator.phase == .active)
        await coordinator.beginClose()?.value
    }

    @Test("replacement failure preserves the prior active renderer")
    func replacementFailurePreservesActiveRenderer() async throws {
        let coordinator = RendererTransferCoordinator()
        let source = try await Self.openedDriver(named: "failure-source")
        let replacement = try await Self.openedDriver(named: "failure-replacement")
        defer {
            try? FileManager.default.removeItem(at: source.url)
            try? FileManager.default.removeItem(at: replacement.url)
        }
        let key = RendererTransferCoordinator.TransferKey(
            generation: 2,
            logicalSessionID: "logical",
            sourceTechnicalSessionID: source.resource.sessionID
        )
        try coordinator.installActive(source.resource)
        try coordinator.beginTransfer(key: key, mode: .technicalSession)
        try coordinator.finishTechnicalSessionPreparation(
            key: key,
            replacement: .init(
                resource: replacement.resource,
                speed: .default,
                selectedAudioTrackID: nil,
                selectedSubtitleTrackID: nil
            )
        )

        #expect(await coordinator.cancelPreparedTransfer())
        #expect(coordinator.phase == .active)
        #expect(coordinator.activeDriver === source.driver)
        #expect(coordinator.activeRenderer === source.resource.renderer)
        await coordinator.beginClose()?.value
    }

    @Test("stale generation callbacks cannot commit a prepared transfer")
    func staleCallbackIsRejected() async throws {
        let coordinator = RendererTransferCoordinator()
        let source = try await Self.openedDriver(named: "stale-source")
        defer { try? FileManager.default.removeItem(at: source.url) }
        let currentKey = RendererTransferCoordinator.TransferKey(
            generation: 11,
            logicalSessionID: "logical",
            sourceTechnicalSessionID: source.resource.sessionID
        )
        let staleKey = RendererTransferCoordinator.TransferKey(
            generation: 10,
            logicalSessionID: "logical",
            sourceTechnicalSessionID: source.resource.sessionID
        )
        try coordinator.installActive(source.resource)
        try coordinator.beginTransfer(key: currentKey, mode: .rendererGraph)
        try coordinator.finishRendererGraphPreparation(key: currentKey)
        let replacement = try await source.driver.replaceVideoRendererGraph()

        #expect(throws: RendererTransferCoordinator.TransferError.staleTransfer) {
            try coordinator.activateRendererGraph(
                key: staleKey,
                replacement: replacement,
                cutoverTime: .zero,
                endedContinuity: nil,
                sourcePresentation: .window,
                naturalEndNotificationWasPublished: false,
                beforeCutover: {}
            )
        }
        #expect(coordinator.phase == .prepared)
        #expect(coordinator.activeDriver === source.driver)
        #expect(coordinator.activeRenderer === source.resource.renderer)
        #expect(await coordinator.cancelPreparedTransfer())
        #expect(coordinator.activeRenderer === replacement.renderer)
        #expect(await coordinator.cancelPreparedTransfer() == false)
        await coordinator.beginClose()?.value
    }

    @Test("repeated cleanup converges on one empty state")
    func repeatedCleanupConverges() async throws {
        let coordinator = RendererTransferCoordinator()
        let source = try await Self.openedDriver(named: "cleanup-source")
        defer { try? FileManager.default.removeItem(at: source.url) }
        try coordinator.installActive(source.resource)

        let firstClose = coordinator.beginClose()
        let repeatedClose = coordinator.beginClose()
        #expect(coordinator.phase == .closing)
        await firstClose?.value
        await repeatedClose?.value

        #expect(coordinator.phase == .empty)
        #expect(coordinator.activeDriver == nil)
        #expect(coordinator.activeRenderer == nil)
        #expect(coordinator.beginClose() == nil)
    }

    @Test("one driver cannot own both sides of a technical-session transfer")
    func oneDriverCannotBeDoublyOwned() async throws {
        let coordinator = RendererTransferCoordinator()
        let source = try await Self.openedDriver(named: "single-owner")
        defer { try? FileManager.default.removeItem(at: source.url) }
        let key = RendererTransferCoordinator.TransferKey(
            generation: 3,
            logicalSessionID: "logical",
            sourceTechnicalSessionID: source.resource.sessionID
        )
        try coordinator.installActive(source.resource)
        try coordinator.beginTransfer(key: key, mode: .technicalSession)

        #expect(throws: RendererTransferCoordinator.TransferError.staleTransfer) {
            try coordinator.finishTechnicalSessionPreparation(
                key: key,
                replacement: .init(
                    resource: source.resource,
                    speed: .default,
                    selectedAudioTrackID: nil,
                    selectedSubtitleTrackID: nil
                )
            )
        }
        #expect(coordinator.phase == .preparing)
        #expect(coordinator.activeDriver === source.driver)
        #expect(await coordinator.cancelPreparedTransfer())
        await coordinator.beginClose()?.value
    }

    private struct OpenedDriver {
        let driver: PlaybackMediaSessionDriver
        let resource: PlaybackMediaSessionDriver.SessionResource
        let url: URL
    }

    private static func openedDriver(named name: String) async throws -> OpenedDriver {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(name)-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        try pcmWaveData().write(to: url, options: .atomic)
        let driver = PlaybackMediaSessionDriver()
        let result = try await driver.open(
            .init(url: url, startsPaused: true)
        )
        return OpenedDriver(driver: driver, resource: result.resource, url: url)
    }

    private static func pcmWaveData() -> Data {
        let sampleRate: UInt32 = 8_000
        let sampleCount: UInt32 = 800
        let audioByteCount = sampleCount * 2
        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        appendLittleEndian(36 + audioByteCount, to: &data)
        data.append(contentsOf: "WAVEfmt ".utf8)
        appendLittleEndian(UInt32(16), to: &data)
        appendLittleEndian(UInt16(1), to: &data)
        appendLittleEndian(UInt16(1), to: &data)
        appendLittleEndian(sampleRate, to: &data)
        appendLittleEndian(sampleRate * 2, to: &data)
        appendLittleEndian(UInt16(2), to: &data)
        appendLittleEndian(UInt16(16), to: &data)
        data.append(contentsOf: "data".utf8)
        appendLittleEndian(audioByteCount, to: &data)
        data.append(Data(count: Int(audioByteCount)))
        return data
    }

    private static func appendLittleEndian<Value: FixedWidthInteger>(
        _ value: Value,
        to data: inout Data
    ) {
        var value = value.littleEndian
        Swift.withUnsafeBytes(of: &value) {
            data.append(contentsOf: $0)
        }
    }
}
