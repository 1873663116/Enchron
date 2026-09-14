import AudioToolbox
import RealityKit
import Testing
@testable import Playback
@testable import PlaybackCore

@MainActor
struct PlaybackSpatialAudioTests {
    @Test("window and docked renderer replacement keep the same front-anchored movie sound stage")
    func presentationChangesPreserveMovieSoundStage() async throws {
        let session = SampleBufferPlaybackSession(traceID: "spatial-audio-placement")
        let audioRenderer = session.audioRenderer
        defer { session.close() }

        for presentation: PlaybackPresentation in [.window, .docked, .window] {
            let renderer = try await session.replaceVideoRendererGraph()
            let entity = Entity()
            PlaybackRealityPresenter.configure(
                entity, renderer: renderer, presentation: presentation,
                requestsSpatialVideoMode: false
            )
            for distance: Float in [12, 13, 47] {
                entity.position = [0, 10, -distance]
                let experience = try #require(
                    session.synchronizer.intendedSpatialAudioExperience as? HeadTrackedSpatialAudio
                )
                #expect(experience.anchoringStrategy == .front)
                #expect(experience.soundStageSize == .large)
                #expect(session.audioRenderer === audioRenderer)
                #expect(audioRenderer.volume == 1)
                #expect(entity.components[SpatialAudioComponent.self] == nil)
                #expect(entity.components[VideoPlayerComponent.self]?.videoRenderer === renderer)
            }
            await session.retireDepartingVideoRendererGraph()
        }
    }
}
