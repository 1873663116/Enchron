@preconcurrency import AVFoundation
import CoreMedia
import Foundation

struct PlaybackActivationObservationPhase: Equatable, Sendable {
    var phase: String
    var delayMilliseconds: Int
}

struct PlaybackActivationReapplyVerificationConfiguration: Equatable, Sendable {
    static let environmentKey = "ENCHRON_VERIFY_SUFFICIENT_RATE_REAPPLY"

    var isEnabled: Bool
    var pollIntervalMilliseconds: Int
    var timeoutMilliseconds: Int

    static var processDefault: Self {
        #if DEBUG
        Self(environment: ProcessInfo.processInfo.environment)
        #else
        .disabled
        #endif
    }

    static let disabled = Self(
        isEnabled: false,
        pollIntervalMilliseconds: 10,
        timeoutMilliseconds: 2_000
    )

    init(
        isEnabled: Bool,
        pollIntervalMilliseconds: Int = 10,
        timeoutMilliseconds: Int = 2_000
    ) {
        #if DEBUG
        self.isEnabled = isEnabled
        #else
        self.isEnabled = false
        #endif
        self.pollIntervalMilliseconds = max(1, pollIntervalMilliseconds)
        self.timeoutMilliseconds = max(1, timeoutMilliseconds)
    }

    init(environment: [String: String]) {
        self.init(isEnabled: environment[Self.environmentKey] == "1")
    }
}

struct PlaybackActivationReapplyVerificationFacts: Equatable, Sendable {
    var videoHasSufficientMedia: Bool
    var audioHasSufficientMedia: Bool
    var directRate: Float64
    var effectiveRate: Float64
}

struct PlaybackActivationReapplyVerificationHooks: @unchecked Sendable {
    var automaticallySchedulesTimer = true
    var uptimeNanoseconds: @Sendable () -> UInt64 = {
        DispatchTime.now().uptimeNanoseconds
    }
    var readFacts: @Sendable (SampleBufferPlaybackSession) -> PlaybackActivationReapplyVerificationFacts = {
        session in
        var directTime = CMTime.invalid
        var directRate: Float64 = .nan
        _ = CMTimebaseGetTimeAndRate(
            session.synchronizer.timebase,
            timeOut: &directTime,
            rateOut: &directRate
        )
        return PlaybackActivationReapplyVerificationFacts(
            videoHasSufficientMedia:
                session.renderer.hasSufficientMediaDataForReliablePlaybackStart,
            audioHasSufficientMedia:
                session.audioRenderer.hasSufficientMediaDataForReliablePlaybackStart,
            directRate: directRate,
            effectiveRate: CMTimebaseGetEffectiveRate(session.synchronizer.timebase)
        )
    }
    var enqueueOnDeliveryQueue: @Sendable (
        SampleBufferPlaybackSession,
        @escaping @Sendable () -> Void
    ) -> Void = { session, operation in
        session.deliveryQueue.async(execute: operation)
    }
    var reapplyRate: @Sendable (
        SampleBufferPlaybackSession,
        Float,
        CMTime
    ) -> Void = { session, rate, anchorTime in
        // This verification path must exercise the same rate application
        // primitive as normal playback. On visionOS, a media-time-only setter
        // can report a requested rate while leaving the effective timebase at
        // zero after the renderers are already fed.
        session.setRateAtHostTime(rate, time: anchorTime)
    }
}

final class PlaybackActivationObservation: @unchecked Sendable {
    static let delayedTaskMarkerPhases = [
        "delayedTask.enter",
        "delayedTask.sleepReturned",
        "delayedTask.beforeStateRead",
    ]
    static let immediatePhases = [
        PlaybackActivationObservationPhase(
            phase: "call.before",
            delayMilliseconds: 0
        ),
        PlaybackActivationObservationPhase(
            phase: "call.returned",
            delayMilliseconds: 0
        ),
    ]
    static let delayedPhases = [10, 50, 100, 500, 2_000].map {
        PlaybackActivationObservationPhase(
            phase: "scheduledSample",
            delayMilliseconds: $0
        )
    }
    static let samplingPhases = immediatePhases + delayedPhases

    private struct LaneCoverage {
        var epoch: UInt64 = 0
        var count: UInt64 = 0
        var firstPresentationTime: CMTime?
        var firstDecodeTime: CMTime?
        var minimumPresentationTime: CMTime?
        var maximumPresentationTime: CMTime?
        var minimumDecodeTime: CMTime?
        var maximumDecodeTime: CMTime?
        var maximumPresentationEnd: CMTime?

        mutating func record(
            epoch: UInt64,
            presentationTime: CMTime,
            decodeTime: CMTime?,
            presentationEnd: CMTime
        ) {
            if self.epoch != epoch {
                self = LaneCoverage(epoch: epoch)
            }
            count &+= 1
            if firstPresentationTime == nil, presentationTime.isNumeric {
                firstPresentationTime = presentationTime
            }
            if firstDecodeTime == nil, let decodeTime, decodeTime.isNumeric {
                firstDecodeTime = decodeTime
            }
            if presentationTime.isNumeric {
                if let minimumPresentationTime {
                    if CMTimeCompare(presentationTime, minimumPresentationTime) < 0 {
                        self.minimumPresentationTime = presentationTime
                    }
                } else {
                    minimumPresentationTime = presentationTime
                }
                if let maximumPresentationTime {
                    if CMTimeCompare(presentationTime, maximumPresentationTime) > 0 {
                        self.maximumPresentationTime = presentationTime
                    }
                } else {
                    maximumPresentationTime = presentationTime
                }
            }
            if let decodeTime, decodeTime.isNumeric {
                if let minimumDecodeTime {
                    if CMTimeCompare(decodeTime, minimumDecodeTime) < 0 {
                        self.minimumDecodeTime = decodeTime
                    }
                } else {
                    minimumDecodeTime = decodeTime
                }
                if let maximumDecodeTime {
                    if CMTimeCompare(decodeTime, maximumDecodeTime) > 0 {
                        self.maximumDecodeTime = decodeTime
                    }
                } else {
                    maximumDecodeTime = decodeTime
                }
            }
            if presentationEnd.isNumeric {
                if let maximumPresentationEnd {
                    if CMTimeCompare(presentationEnd, maximumPresentationEnd) > 0 {
                        self.maximumPresentationEnd = presentationEnd
                    }
                } else {
                    maximumPresentationEnd = presentationEnd
                }
            }
        }
    }

    private struct ActivationContext {
        var sequence: UInt64
        var videoStreamEpoch: UInt64
        var audioStreamEpoch: UInt64
        var requestedRate: Float
        var anchorTime: CMTime
        var startUptimeNanoseconds: UInt64
    }

    private struct ReapplyVerificationContext {
        var activationSequence: UInt64
        var videoStreamEpoch: UInt64
        var audioStreamEpoch: UInt64
        var requestedRate: Float
        var anchorTime: CMTime
        var startUptimeNanoseconds: UInt64
        var attemptCount = 0
        var isQueued = false
        var isClaimed = false
    }

    private weak var session: SampleBufferPlaybackSession?
    private let notificationCenter: NotificationCenter
    private let reapplyConfiguration: PlaybackActivationReapplyVerificationConfiguration
    private let reapplyHooks: PlaybackActivationReapplyVerificationHooks
    private lazy var reapplyTimerQueue = DispatchQueue(
        label: "PlaybackCore.activation-reapply-verification"
    )
    private let lock = NSLock()
    private var notificationTokens: [NSObjectProtocol] = []
    private var scheduledTasks: [UUID: Task<Void, Never>] = [:]
    private var context: ActivationContext?
    private var sequence: UInt64 = 0
    private var isStopped = false
    private var videoCoverage = LaneCoverage()
    private var audioCoverage = LaneCoverage()
    private var reapplyVerificationContext: ReapplyVerificationContext?
    private var reapplyTimer: DispatchSourceTimer?
    private var lastReapplyStartedSequence: UInt64?

    init(
        session: SampleBufferPlaybackSession,
        notificationCenter: NotificationCenter = .default,
        reapplyConfiguration: PlaybackActivationReapplyVerificationConfiguration = .processDefault,
        reapplyHooks: PlaybackActivationReapplyVerificationHooks = .init()
    ) {
        self.session = session
        self.notificationCenter = notificationCenter
        self.reapplyConfiguration = reapplyConfiguration
        self.reapplyHooks = reapplyHooks
    }

    func start() {
        guard let session else { return }
        let registrations: [(Notification.Name, Any, String)] = [
            (
                AVSampleBufferRenderSynchronizer.rateDidChangeNotification,
                session.synchronizer,
                "notification.synchronizerRateDidChange"
            ),
            (
                CMTimebase.effectiveRateChanged,
                session.synchronizer.timebase,
                "notification.timebaseEffectiveRateChanged"
            ),
            (
                CMTimebase.timeJumped,
                session.synchronizer.timebase,
                "notification.timebaseTimeJumped"
            ),
            (
                AVSampleBufferVideoRenderer
                    .requiresFlushToResumeDecodingDidChangeNotification,
                session.renderer,
                "notification.videoRequiresFlushChanged"
            ),
            (
                .AVSampleBufferAudioRendererWasFlushedAutomatically,
                session.audioRenderer,
                "notification.audioFlushedAutomatically"
            ),
            (
                .AVSampleBufferAudioRendererOutputConfigurationDidChange,
                session.audioRenderer,
                "notification.audioOutputConfigurationChanged"
            ),
        ]
        let tokens = registrations.map { name, object, phase in
            notificationCenter.addObserver(
                forName: name,
                object: object,
                queue: nil
            ) { [weak self] _ in
                self?.recordNotification(phase: phase)
            }
        }
        lock.withLock {
            guard !isStopped else {
                tokens.forEach(notificationCenter.removeObserver)
                return
            }
            notificationTokens.append(contentsOf: tokens)
        }
    }

    func stop() {
        invalidateReapplyVerification(outcome: .invalidatedByStop)
        let state = lock.withLock { () -> ([NSObjectProtocol], [Task<Void, Never>]) in
            guard !isStopped else { return ([], []) }
            isStopped = true
            context = nil
            let tokens = notificationTokens
            notificationTokens.removeAll()
            let tasks = Array(scheduledTasks.values)
            scheduledTasks.removeAll()
            return (tokens, tasks)
        }
        state.0.forEach(notificationCenter.removeObserver)
        state.1.forEach { $0.cancel() }
    }

    func beginActivation(requestedRate: Float, anchorTime: CMTime) -> UInt64? {
        invalidateReapplyVerification(outcome: .invalidatedByNewActivation)
        let result = lock.withLock { () -> (ActivationContext, [Task<Void, Never>])? in
            guard !isStopped else { return nil }
            sequence &+= 1
            let previousTasks = Array(scheduledTasks.values)
            scheduledTasks.removeAll()
            let newContext = ActivationContext(
                sequence: sequence,
                videoStreamEpoch: session?.streamEpoch ?? 0,
                audioStreamEpoch: session?.audioStreamEpoch ?? 0,
                requestedRate: requestedRate,
                anchorTime: anchorTime,
                startUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds
            )
            context = newContext
            return (newContext, previousTasks)
        }
        guard let result else { return nil }
        result.1.forEach { $0.cancel() }
        let phase = Self.immediatePhases[0]
        record(
            context: result.0,
            phase: phase.phase,
            delayMilliseconds: phase.delayMilliseconds
        )
        return result.0.sequence
    }

    func rateApplicationReturned(sequence: UInt64) {
        guard let context = currentContext(sequence: sequence) else { return }
        let returnedPhase = Self.immediatePhases[1]
        record(
            context: context,
            phase: returnedPhase.phase,
            delayMilliseconds: returnedPhase.delayMilliseconds
        )
        for phase in Self.delayedPhases {
            schedule(context: context, phase: phase)
        }
        beginReapplyVerification(for: context)
    }

    func invalidateReapplyVerification(
        outcome: PlaybackActivationReapplyVerificationOutcome
    ) {
        guard reapplyConfiguration.isEnabled else { return }
        let result = lock.withLock { () -> (
            ReapplyVerificationContext,
            DispatchSourceTimer?
        )? in
            guard let context = reapplyVerificationContext else { return nil }
            reapplyVerificationContext = nil
            let timer = reapplyTimer
            reapplyTimer = nil
            return (context, timer)
        }
        result?.1?.cancel()
        guard let context = result?.0, let session else { return }
        recordReapplyVerification(
            context: context,
            facts: reapplyHooks.readFacts(session),
            outcome: outcome
        )
    }

    func fireReapplyVerificationTimerForTesting() {
        guard let sequence = lock.withLock({ reapplyVerificationContext?.activationSequence }) else {
            return
        }
        reapplyVerificationTimerFired(sequence: sequence)
    }

    func recordAcceptedVideo(
        epoch: UInt64,
        presentationTime: CMTime,
        decodeTime: CMTime,
        presentationEnd: CMTime
    ) {
        lock.withLock {
            videoCoverage.record(
                epoch: epoch,
                presentationTime: presentationTime,
                decodeTime: decodeTime,
                presentationEnd: presentationEnd
            )
        }
    }

    func recordAcceptedAudio(
        epoch: UInt64,
        presentationTime: CMTime,
        presentationEnd: CMTime
    ) {
        lock.withLock {
            audioCoverage.record(
                epoch: epoch,
                presentationTime: presentationTime,
                decodeTime: nil,
                presentationEnd: presentationEnd
            )
        }
    }

    private func beginReapplyVerification(for context: ActivationContext) {
        guard reapplyConfiguration.isEnabled,
              context.requestedRate > 0,
              let session else { return }
        let verificationContext = ReapplyVerificationContext(
            activationSequence: context.sequence,
            videoStreamEpoch: context.videoStreamEpoch,
            audioStreamEpoch: context.audioStreamEpoch,
            requestedRate: context.requestedRate,
            anchorTime: context.anchorTime,
            startUptimeNanoseconds: reapplyHooks.uptimeNanoseconds()
        )
        let installed = lock.withLock {
            guard !isStopped,
                  self.context?.sequence == context.sequence,
                  lastReapplyStartedSequence != context.sequence else { return false }
            lastReapplyStartedSequence = context.sequence
            reapplyVerificationContext = verificationContext
            return true
        }
        guard installed else { return }
        recordReapplyVerification(
            context: verificationContext,
            facts: reapplyHooks.readFacts(session),
            outcome: .monitoring
        )
        guard reapplyHooks.automaticallySchedulesTimer else { return }

        let interval = reapplyConfiguration.pollIntervalMilliseconds
        let timer = DispatchSource.makeTimerSource(queue: reapplyTimerQueue)
        timer.schedule(
            deadline: .now() + .milliseconds(interval),
            repeating: .milliseconds(interval)
        )
        timer.setEventHandler { [weak self] in
            self?.reapplyVerificationTimerFired(sequence: context.sequence)
        }
        timer.resume()
        let shouldCancel = lock.withLock {
            guard !isStopped,
                  reapplyVerificationContext?.activationSequence == context.sequence else {
                return true
            }
            reapplyTimer?.cancel()
            reapplyTimer = timer
            return false
        }
        if shouldCancel { timer.cancel() }
    }

    private func reapplyVerificationTimerFired(sequence: UInt64) {
        guard reapplyConfiguration.isEnabled, let session else { return }
        guard let context = lock.withLock({ () -> ReapplyVerificationContext? in
            guard !isStopped,
                  reapplyVerificationContext?.activationSequence == sequence else { return nil }
            return reapplyVerificationContext
        }) else { return }

        guard context.videoStreamEpoch == session.streamEpoch,
              context.audioStreamEpoch == session.audioStreamEpoch else {
            invalidateReapplyVerification(outcome: .invalidatedByEpochChange)
            return
        }
        let elapsed = reapplyHooks.uptimeNanoseconds() &- context.startUptimeNanoseconds
        if elapsed / 1_000_000 >= UInt64(reapplyConfiguration.timeoutMilliseconds) {
            invalidateReapplyVerification(outcome: .timedOut)
            return
        }

        let facts = reapplyHooks.readFacts(session)
        let sufficient = facts.videoHasSufficientMedia
            && (!session.hasAudio || facts.audioHasSufficientMedia)
        guard sufficient else {
            recordReapplyVerification(
                context: context,
                facts: facts,
                outcome: .waitingForSufficientMedia
            )
            return
        }
        guard facts.directRate == 0, facts.effectiveRate == 0 else {
            finishQueuedVerificationIfCurrent(
                context: context,
                session: session,
                facts: facts,
                outcome: .rateAlreadyActive
            )
            return
        }

        let queuedContext = lock.withLock { () -> ReapplyVerificationContext? in
            guard var current = reapplyVerificationContext,
                  current.activationSequence == sequence,
                  !current.isQueued,
                  !current.isClaimed else { return nil }
            current.isQueued = true
            reapplyVerificationContext = current
            reapplyTimer?.cancel()
            reapplyTimer = nil
            return current
        }
        guard let queuedContext else { return }
        recordReapplyVerification(context: queuedContext, facts: facts, outcome: .queued)
        reapplyHooks.enqueueOnDeliveryQueue(session) { [weak self, weak session] in
            guard let self, let session else { return }
            self.reapplyOnDeliveryQueueIfStillValid(
                context: queuedContext,
                session: session
            )
        }
    }

    private func reapplyOnDeliveryQueueIfStillValid(
        context: ReapplyVerificationContext,
        session: SampleBufferPlaybackSession
    ) {
        guard reapplyConfiguration.isEnabled else { return }
        guard context.videoStreamEpoch == session.streamEpoch,
              context.audioStreamEpoch == session.audioStreamEpoch else {
            finishQueuedVerificationIfCurrent(
                context: context,
                session: session,
                outcome: .invalidatedByEpochChange
            )
            return
        }
        guard
              !session.isClosed,
              !session.isResetting,
              !session.isCloseInProgress,
              session.mediaSessionRecord?.lifecycle == .playing,
              session.timelineStartRate == context.requestedRate else {
            finishQueuedVerificationIfCurrent(
                context: context,
                session: session,
                outcome: .staleBeforeReapply
            )
            return
        }

        let facts = reapplyHooks.readFacts(session)
        let sufficient = facts.videoHasSufficientMedia
            && (!session.hasAudio || facts.audioHasSufficientMedia)
        guard sufficient,
              facts.directRate == 0,
              facts.effectiveRate == 0 else {
            finishQueuedVerificationIfCurrent(
                context: context,
                session: session,
                facts: facts,
                outcome: facts.directRate == 0 && facts.effectiveRate == 0
                    ? .staleBeforeReapply
                    : .rateAlreadyActive
            )
            return
        }

        guard let claimed = lock.withLock({ () -> ReapplyVerificationContext? in
            guard var current = reapplyVerificationContext,
                  current.activationSequence == context.activationSequence,
                  current.videoStreamEpoch == context.videoStreamEpoch,
                  current.audioStreamEpoch == context.audioStreamEpoch,
                  current.requestedRate == context.requestedRate,
                  current.anchorTime == context.anchorTime,
                  current.isQueued,
                  !current.isClaimed else { return nil }
            current.isClaimed = true
            current.attemptCount += 1
            reapplyVerificationContext = nil
            return current
        }) else { return }

        reapplyHooks.reapplyRate(session, claimed.requestedRate, claimed.anchorTime)
        recordReapplyVerification(context: claimed, facts: facts, outcome: .reapplied)
    }

    private func finishQueuedVerificationIfCurrent(
        context: ReapplyVerificationContext,
        session: SampleBufferPlaybackSession,
        facts: PlaybackActivationReapplyVerificationFacts? = nil,
        outcome: PlaybackActivationReapplyVerificationOutcome
    ) {
        let result = lock.withLock { () -> (
            ReapplyVerificationContext,
            DispatchSourceTimer?
        )? in
            guard let current = reapplyVerificationContext,
                  current.activationSequence == context.activationSequence else { return nil }
            reapplyVerificationContext = nil
            let timer = reapplyTimer
            reapplyTimer = nil
            return (current, timer)
        }
        result?.1?.cancel()
        guard let finished = result?.0 else { return }
        recordReapplyVerification(
            context: finished,
            facts: facts ?? reapplyHooks.readFacts(session),
            outcome: outcome
        )
    }

    private func recordReapplyVerification(
        context: ReapplyVerificationContext,
        facts: PlaybackActivationReapplyVerificationFacts,
        outcome: PlaybackActivationReapplyVerificationOutcome
    ) {
        guard let session else { return }
        session.debugStore.recordActivationReapplyVerification(
            PlaybackActivationReapplyVerificationRecord(
                activationSequence: context.activationSequence,
                videoStreamEpoch: context.videoStreamEpoch,
                audioStreamEpoch: context.audioStreamEpoch,
                requestedRate: context.requestedRate,
                anchorValue: context.anchorTime.value,
                anchorTimescale: context.anchorTime.timescale,
                anchorFlags: context.anchorTime.flags.rawValue,
                anchorEpoch: context.anchorTime.epoch,
                audioRequired: session.hasAudio,
                videoHasSufficientMedia: facts.videoHasSufficientMedia,
                audioHasSufficientMedia: !session.hasAudio || facts.audioHasSufficientMedia,
                directRate: facts.directRate,
                effectiveRate: facts.effectiveRate,
                attemptCount: context.attemptCount,
                outcome: outcome
            )
        )
    }

    private func schedule(
        context: ActivationContext,
        phase: PlaybackActivationObservationPhase
    ) {
        let taskID = UUID()
        let task = Task.detached { [weak self] in
            guard self?.recordStageMarkerIfCurrent(
                sequence: context.sequence,
                phase: Self.delayedTaskMarkerPhases[0],
                delayMilliseconds: phase.delayMilliseconds
            ) == true else { return }
            do {
                try await Task.sleep(for: .milliseconds(phase.delayMilliseconds))
            } catch {
                return
            }
            guard self?.recordStageMarkerIfCurrent(
                sequence: context.sequence,
                phase: Self.delayedTaskMarkerPhases[1],
                delayMilliseconds: phase.delayMilliseconds
            ) == true else { return }
            guard let self,
                  !Task.isCancelled else { return }
            guard self.recordStageMarkerIfCurrent(
                sequence: context.sequence,
                phase: Self.delayedTaskMarkerPhases[2],
                delayMilliseconds: phase.delayMilliseconds
            ) else { return }
            self.recordScheduledSample(
                sequence: context.sequence,
                delayMilliseconds: phase.delayMilliseconds
            )
            self.lock.withLock { self.scheduledTasks.removeValue(forKey: taskID) }
        }
        lock.withLock {
            guard !isStopped, self.context?.sequence == context.sequence else {
                task.cancel()
                return
            }
            scheduledTasks[taskID] = task
        }
    }

    func recordScheduledSample(sequence: UInt64, delayMilliseconds: Int) {
        guard let context = currentContext(sequence: sequence) else { return }
        record(
            context: context,
            phase: "scheduledSample",
            delayMilliseconds: delayMilliseconds
        )
    }

    @discardableResult
    func recordStageMarkerIfCurrent(
        sequence: UInt64,
        phase: String,
        delayMilliseconds: Int
    ) -> Bool {
        guard let session, !session.isClosed,
              currentContext(sequence: sequence) != nil else { return false }
        session.debugStore.emit(
            mediaSessionID: session.traceID,
            node: .rendererInputCoordination,
            kind: "playbackActivation.stageMarker",
            outcome: .succeeded,
            details: [
                "streamEpoch": String(session.streamEpoch),
                "audioStreamEpoch": String(session.audioStreamEpoch),
                "activationSequence": String(sequence),
                "phase": phase,
                "delayMs": String(delayMilliseconds),
            ]
        )
        return true
    }

    private func recordNotification(phase: String) {
        guard let sequence = lock.withLock({ isStopped ? nil : context?.sequence }),
              let context = currentContext(sequence: sequence) else { return }
        let elapsed = DispatchTime.now().uptimeNanoseconds - context.startUptimeNanoseconds
        record(
            context: context,
            phase: phase,
            delayMilliseconds: Int(elapsed / 1_000_000)
        )
    }

    private func currentContext(sequence: UInt64) -> ActivationContext? {
        guard let session else { return nil }
        return lock.withLock { () -> ActivationContext? in
            guard !isStopped,
                  context?.sequence == sequence,
                  context?.videoStreamEpoch == session.streamEpoch,
                  context?.audioStreamEpoch == session.audioStreamEpoch else { return nil }
            return context
        }
    }

    private func record(
        context: ActivationContext,
        phase: String,
        delayMilliseconds: Int
    ) {
        guard let session, !session.isClosed,
              currentContext(sequence: context.sequence) != nil else { return }
        var directTime = CMTime.invalid
        var directRate: Float64 = .nan
        let directStatus = CMTimebaseGetTimeAndRate(
            session.synchronizer.timebase,
            timeOut: &directTime,
            rateOut: &directRate
        )
        let source = CMTimebaseCopySource(session.synchronizer.timebase)
        let sourceTime = CMSyncGetTime(source)
        let sourceType: String
        if CFGetTypeID(source) == CMTimebaseGetTypeID() {
            sourceType = "CMTimebase"
        } else if CFGetTypeID(source) == CMClockGetTypeID() {
            sourceType = "CMClock"
        } else {
            sourceType = "unknownCFType"
        }
        let ultimateClock = CMTimebaseCopyUltimateSourceClock(session.synchronizer.timebase)
        let ultimateTime = CMClockGetTime(ultimateClock)
        let coverage = lock.withLock {
            let video = videoCoverage.epoch == session.streamEpoch
                ? videoCoverage
                : LaneCoverage(epoch: session.streamEpoch)
            let audio = audioCoverage.epoch == session.audioStreamEpoch
                ? audioCoverage
                : LaneCoverage(epoch: session.audioStreamEpoch)
            return (video, audio)
        }
        let details: [String: String] = [
            "streamEpoch": String(session.streamEpoch),
            "audioStreamEpoch": String(session.audioStreamEpoch),
            "activationSequence": String(context.sequence),
            "phase": phase,
            "delayMs": String(delayMilliseconds),
            "requestedRate": String(context.requestedRate),
            "anchorTimeSeconds": seconds(context.anchorTime),
            "delaysRateChangeUntilHasSufficientMediaData": String(
                session.synchronizer.delaysRateChangeUntilHasSufficientMediaData
            ),
            "synchronizerRate": String(session.synchronizer.rate),
            "directTimebaseStatus": String(directStatus),
            "directTimebaseTimeSeconds": seconds(directTime),
            "directTimebaseRate": String(directRate),
            "effectiveTimebaseRate": String(
                CMTimebaseGetEffectiveRate(session.synchronizer.timebase)
            ),
            "synchronizerCurrentTimeSeconds": seconds(session.synchronizer.currentTime()),
            "directSourceType": sourceType,
            "directSourceTimeSeconds": seconds(sourceTime),
            "ultimateSourceType": "CMClock",
            "ultimateSourceTimeSeconds": seconds(ultimateTime),
            "videoStatus": videoStatus(session.renderer.status),
            "videoError": session.renderer.error?.localizedDescription ?? "none",
            "videoHasSufficientMedia": String(
                session.renderer.hasSufficientMediaDataForReliablePlaybackStart
            ),
            "videoReadyForMoreMedia": String(session.renderer.isReadyForMoreMediaData),
            "videoRequiresFlush": String(session.renderer.requiresFlushToResumeDecoding),
            "audioStatus": audioStatus(session.audioRenderer.status),
            "audioError": session.audioRenderer.error?.localizedDescription ?? "none",
            "audioHasSufficientMedia": String(
                session.audioRenderer.hasSufficientMediaDataForReliablePlaybackStart
            ),
            "audioReadyForMoreMedia": String(session.audioRenderer.isReadyForMoreMediaData),
            "statusErrorObservation": "sampledOnly.noPublicChangeNotification",
            "videoAcceptedEpoch": String(coverage.0.epoch),
            "videoAcceptedFirstPTSSeconds": seconds(coverage.0.firstPresentationTime),
            "videoAcceptedFirstDTSSeconds": seconds(coverage.0.firstDecodeTime),
            "videoAcceptedMinPTSSeconds": seconds(coverage.0.minimumPresentationTime),
            "videoAcceptedMaxPTSSeconds": seconds(coverage.0.maximumPresentationTime),
            "videoAcceptedMinDTSSeconds": seconds(coverage.0.minimumDecodeTime),
            "videoAcceptedMaxDTSSeconds": seconds(coverage.0.maximumDecodeTime),
            "videoAcceptedMaxEndSeconds": seconds(coverage.0.maximumPresentationEnd),
            "videoAcceptedCount": String(coverage.0.count),
            "audioAcceptedEpoch": String(coverage.1.epoch),
            "audioAcceptedMinPTSSeconds": seconds(coverage.1.minimumPresentationTime),
            "audioAcceptedMaxEndSeconds": seconds(coverage.1.maximumPresentationEnd),
            "audioAcceptedCount": String(coverage.1.count),
        ]
        session.debugStore.emit(
            mediaSessionID: session.traceID,
            node: .rendererInputCoordination,
            kind: "playbackActivation.observation",
            outcome: .succeeded,
            details: details
        )
    }

    private func seconds(_ time: CMTime?) -> String {
        guard let time, time.isNumeric else { return "invalid" }
        return String(time.seconds)
    }

    private func videoStatus(_ status: AVQueuedSampleBufferRenderingStatus) -> String {
        switch status {
        case .unknown: "unknown"
        case .rendering: "rendering"
        case .failed: "failed"
        @unknown default: "unrecognized"
        }
    }

    private func audioStatus(_ status: AVQueuedSampleBufferRenderingStatus) -> String {
        videoStatus(status)
    }
}
