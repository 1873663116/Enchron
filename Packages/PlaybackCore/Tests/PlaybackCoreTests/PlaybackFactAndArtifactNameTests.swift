import Foundation
import Testing
@testable import PlaybackCore

@Test func observedFactsPreserveTheAvailabilityValueJSONShape() throws {
    let stringFact = ObservedStringFact(known: "PQ")
    let booleanFact = ObservedBooleanFact(known: false)

    let stringObject = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(stringFact))
            as? [String: Any]
    )
    let booleanObject = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(booleanFact))
            as? [String: Any]
    )

    #expect(stringObject["availability"] as? String == "known")
    #expect(stringObject["value"] as? String == "PQ")
    #expect(booleanObject["availability"] as? String == "known")
    #expect(booleanObject["value"] as? Bool == false)
}

@Test func unavailableObservedFactsPreserveTheLegacyJSONKeyShape() throws {
    let legacyString = Data(#"{"availability":"unknown","value":"guessed"}"#.utf8)
    let legacyBoolean = Data(#"{"availability":"none","value":false}"#.utf8)

    let stringFact = try JSONDecoder().decode(ObservedStringFact.self, from: legacyString)
    let booleanFact = try JSONDecoder().decode(ObservedBooleanFact.self, from: legacyBoolean)

    #expect(stringFact.availability == .unknown)
    #expect(stringFact.value == nil)
    #expect(booleanFact.availability == .none)
    #expect(booleanFact.value == nil)

    let encodedString = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(stringFact))
            as? [String: Any]
    )
    let encodedBoolean = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(booleanFact))
            as? [String: Any]
    )
    #expect(encodedString["availability"] as? String == "unknown")
    #expect(encodedString.keys.contains("value") == false)
    #expect(encodedBoolean["availability"] as? String == "none")
    #expect(encodedBoolean.keys.contains("value") == false)
}

@Test func presenceFactsDistinguishMissingFromObservedPresence() {
    let session = SampleBufferPlaybackSession(traceID: "presence-fact-tests")
    let missing = session.presenceFact(nil)
    let present = session.presenceFact(NSNull())

    #expect(missing.availability == .none)
    #expect(missing.value == nil)
    #expect(present.availability == .known)
    #expect(present.value == true)
}

@Test func knownObservedFactsRequireAValueWhenDecoding() {
    let missingString = Data(#"{"availability":"known","value":null}"#.utf8)
    let missingBoolean = Data(#"{"availability":"known"}"#.utf8)

    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(ObservedStringFact.self, from: missingString)
    }
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(ObservedBooleanFact.self, from: missingBoolean)
    }
}

@Test func operationStartedArtifactNamesCoverEveryOperationKind() {
    let expected: [(PlaybackOperationKind, String)] = [
        (.open, "operation.open.started"),
        (.play, "operation.play.started"),
        (.pause, "operation.pause.started"),
        (.setRate, "operation.setRate.started"),
        (.setStereoLayout, "operation.setStereoLayout.started"),
        (.setProjection, "operation.setProjection.started"),
        (.seek, "operation.seek.started"),
        (.close, "operation.close.started"),
    ]

    #expect(expected.count == 8)
    for (kind, rawValue) in expected {
        #expect(PlaybackArtifactEventName.operationStarted(kind).rawValue == rawValue)
    }
}

@Test func operationTerminalArtifactNamesCoverEveryKindAndTerminalState() {
    let expected: [(PlaybackOperationKind, PlaybackOperationState, String)] = [
        (.open, .completed, "operation.open.completed"),
        (.open, .failed, "operation.open.failed"),
        (.open, .terminatedByCleanup, "operation.open.terminatedByCleanup"),
        (.play, .completed, "operation.play.completed"),
        (.play, .failed, "operation.play.failed"),
        (.play, .terminatedByCleanup, "operation.play.terminatedByCleanup"),
        (.pause, .completed, "operation.pause.completed"),
        (.pause, .failed, "operation.pause.failed"),
        (.pause, .terminatedByCleanup, "operation.pause.terminatedByCleanup"),
        (.setRate, .completed, "operation.setRate.completed"),
        (.setRate, .failed, "operation.setRate.failed"),
        (.setRate, .terminatedByCleanup, "operation.setRate.terminatedByCleanup"),
        (.setStereoLayout, .completed, "operation.setStereoLayout.completed"),
        (.setStereoLayout, .failed, "operation.setStereoLayout.failed"),
        (
            .setStereoLayout,
            .terminatedByCleanup,
            "operation.setStereoLayout.terminatedByCleanup"
        ),
        (.setProjection, .completed, "operation.setProjection.completed"),
        (.setProjection, .failed, "operation.setProjection.failed"),
        (
            .setProjection,
            .terminatedByCleanup,
            "operation.setProjection.terminatedByCleanup"
        ),
        (.seek, .completed, "operation.seek.completed"),
        (.seek, .failed, "operation.seek.failed"),
        (.seek, .terminatedByCleanup, "operation.seek.terminatedByCleanup"),
        (.close, .completed, "operation.close.completed"),
        (.close, .failed, "operation.close.failed"),
        (.close, .terminatedByCleanup, "operation.close.terminatedByCleanup"),
    ]

    #expect(expected.count == 8 * 3)
    for (kind, state, rawValue) in expected {
        #expect(
            PlaybackArtifactEventName.operationFinished(kind, as: state).rawValue
                == rawValue
        )
    }
}

@Test func rendererArtifactNamesCoverEveryRendererAndSeverity() {
    let expected: [(RendererFailureKind, Bool, String)] = [
        (.video, false, "videoRenderer.failed"),
        (.video, true, "videoRenderer.warning"),
        (.audio, false, "audioRenderer.failed"),
        (.audio, true, "audioRenderer.warning"),
    ]

    #expect(expected.count == 2 * 2)
    for (kind, warning, rawValue) in expected {
        #expect(
            PlaybackArtifactEventName.renderer(kind, warning: warning).rawValue
                == rawValue
        )
    }
}

@Test func rejectedControlArtifactNamesCoverEveryOperationKind() {
    let expected: [(PlaybackOperationKind, String)] = [
        (.open, "control.open.rejected"),
        (.play, "control.play.rejected"),
        (.pause, "control.pause.rejected"),
        (.setRate, "control.setRate.rejected"),
        (.setStereoLayout, "control.setStereoLayout.rejected"),
        (.setProjection, "control.setProjection.rejected"),
        (.seek, "control.seek.rejected"),
        (.close, "control.close.rejected"),
    ]

    #expect(expected.count == 8)
    for (kind, rawValue) in expected {
        #expect(PlaybackArtifactEventName.controlRejected(kind).rawValue == rawValue)
    }
}

@Test func providerControlArtifactNamesRemainStable() {
    #expect(
        PlaybackArtifactEventName.providerControl(.formatChanged).rawValue
            == "provider.formatChanged"
    )
    #expect(
        PlaybackArtifactEventName.providerControl(.flush).rawValue
            == "provider.flush"
    )
}
