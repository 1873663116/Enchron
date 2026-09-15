import Foundation
import PlaybackCore
import Testing

@testable import Playback

@MainActor
struct DeveloperStatsLineTests {
    private static let mib: UInt64 = 1_048_576

    @Test("memory group renders decomposition fields in order")
    func memoryGroupRendersDecompositionFieldsInOrder() {
        let metrics = DeveloperProcessMetrics(
            footprintBytes: 300 * Self.mib,
            graphicsFootprintBytes: 7 * Int64(Self.mib),
            internalBytes: 120 * Self.mib,
            untaggedResidualBytes: 160 * Int64(Self.mib),
            ioSurfaceResidentBytes: 150 * Self.mib,
            coreMediaResidentBytes: 30 * Self.mib
        )

        let text = DeveloperStatsLine.text(
            metrics: metrics,
            sceneUpdatesPerSecond: nil,
            enqueuedSamplesPerSecond: nil,
            playback: nil,
            sessionIsActive: false, showsDetails: true
        )

        let tokens = ["Memory 300MB", "Internal 120MB", "Graphics 7MB", "IOSurface 150MB", "CoreMedia 30MB"]
        for token in tokens {
            #expect(text.contains(token))
        }
        let positions = tokens.compactMap { text.range(of: $0)?.lowerBound }
        #expect(positions.count == 5)
        #expect(positions == positions.sorted())
    }

    @Test("missing region summaries hide the optional tags")
    func missingRegionSummariesHideOptionalTags() {
        let metrics = DeveloperProcessMetrics(
            footprintBytes: 300 * Self.mib,
            internalBytes: 120 * Self.mib,
            untaggedResidualBytes: 160 * Int64(Self.mib)
        )

        let text = DeveloperStatsLine.text(
            metrics: metrics,
            sceneUpdatesPerSecond: nil,
            enqueuedSamplesPerSecond: nil,
            playback: nil,
            sessionIsActive: false, showsDetails: true
        )

        for token in ["IOSurface", "GPU buffers", "CoreMedia", "Bitstream"] {
            #expect(text.contains(token) == false)
        }
    }

    @Test("zero-counted regions stay off the overlay")
    func zeroCountedRegionsStayOffTheOverlay() {
        let metrics = DeveloperProcessMetrics(
            footprintBytes: 300 * Self.mib,
            graphicsFootprintBytes: 61 * Int64(Self.mib),
            internalBytes: 120 * Self.mib,
            ioSurfaceResidentBytes: 0,
            ioAcceleratorResidentBytes: 0,
            coreMediaResidentBytes: 0,
            videoBitstreamResidentBytes: 0
        )

        let text = DeveloperStatsLine.text(
            metrics: metrics,
            sceneUpdatesPerSecond: nil,
            enqueuedSamplesPerSecond: nil,
            playback: nil,
            sessionIsActive: false, showsDetails: true
        )

        for token in ["IOSurface", "GPU buffers", "CoreMedia", "Bitstream"] {
            #expect(text.contains(token) == false)
        }
        #expect(text.contains("Graphics 61MB"))
    }

    @Test("the overlay no longer carries a residual or a decoded-pool estimate")
    func overlayCarriesNoResidualOrPoolEstimate() {
        var playback = PlaybackDiagnostics()
        playback.videoPixelWidth = 3840
        playback.videoPixelHeight = 2160
        playback.decodedBytesPerPixel = 3
        playback.videoReorderDepth = 3

        let metrics = DeveloperProcessMetrics(
            footprintBytes: 300 * Self.mib,
            graphicsFootprintBytes: 219 * Int64(Self.mib),
            internalBytes: 80 * Self.mib,
            untaggedResidualBytes: -5 * Int64(Self.mib)
        )

        let text = DeveloperStatsLine.text(
            metrics: metrics,
            sceneUpdatesPerSecond: nil,
            enqueuedSamplesPerSecond: nil,
            playback: playback,
            sessionIsActive: true, showsDetails: true
        )

        #expect(text.contains("VID") == false)
        #expect(text.contains("RES") == false)
    }

    @Test("untagged residual subtracts every accounted bucket")
    func untaggedResidualSubtractsEveryAccountedBucket() {
        let reading = ProcessMemoryFootprint.Reading(
            footprintBytes: 500 * Self.mib,
            availableBytes: 0,
            mediaFootprintBytes: 40 * Int64(Self.mib),
            mediaUnchargedBytes: nil,
            graphicsFootprintBytes: 10 * Int64(Self.mib),
            graphicsUnchargedBytes: nil,
            compressedBytes: 30 * Self.mib,
            swapInBytes: nil,
            internalBytes: 100 * Self.mib,
            externalBytes: 0,
            purgeableNonvolatileBytes: 20 * Int64(Self.mib)
        )

        #expect(reading.untaggedResidualBytes == 300 * Int64(Self.mib))
    }

    @Test("host region walk returns populated summary")
    func hostRegionWalkReturnsPopulatedSummary() {
        let summary = ProcessMemoryRegions.read()

        #expect(summary != nil)
        #expect((summary?.regionCount ?? 0) > 0)
        #expect(summary?.resident(ProcessMemoryRegions.mallocTags) ?? 0 > 0)
    }

    @Test("basic overlay has three rows and hides memory internals")
    func basicOverlayGroupsAndRequestStatus() {
        var playback = PlaybackDiagnostics()
        playback.nominalFrameRate = 25.00073007621996
        let metrics = DeveloperProcessMetrics(footprintBytes: 300 * Self.mib, internalBytes: 120 * Self.mib)
        let groups = DeveloperStatsLine.groups(
            metrics: metrics, sceneUpdatesPerSecond: 90, enqueuedSamplesPerSecond: 25,
            playback: playback, sessionIsActive: true, requestedRefreshHz: 100
        )
        #expect(groups.map(\.id) == ["cadence", "session", "application"])
        #expect(groups[0].fields.map(\.key) == ["Video", "Requested", "DisplayLink"])
        #expect(groups.flatMap(\.fields).contains { $0.key == "Internal" } == false)
        let disabled = DeveloperStatsLine.text(
            metrics: metrics, sceneUpdatesPerSecond: nil, enqueuedSamplesPerSecond: nil,
            playback: nil, sessionIsActive: false, requestStatus: "Off"
        )
        #expect(disabled.contains("Requested Off"))
        #expect(disabled.contains("OffHz") == false)
    }

}
