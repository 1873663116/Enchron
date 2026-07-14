import Foundation

enum VisionPresentationCoordinatorTests {
  private struct ExpectedFailure: Error {}

  @MainActor
  static func run() async {
    await testTargetFirstOrder()
    await testTargetFailurePreservesSourceStep()
    await testRollbackOrder()
    await testRollbackFailureIsExplicit()
    await testCloseNeedsDetachAcknowledgement()
    await testLateAttachIsRejected()
    await testRetryRejectsStaleAndDuplicateAttachments()
    await testCloseTimeoutCannotClaimReopen()
    await testSceneAttachDuringTimeoutDismissIsRejected()
    await testSceneAttachOutranksContradictoryOpenResult()
  }

  @MainActor
  private static func testTargetFirstOrder() async {
    var events = [String]()
    do {
      try await VisionPresentationTransaction.presentTarget(
        prepareTarget: { events.append("targetAttached") },
        migrateAndBind: { events.append("targetBound") },
        requestAndAwaitMode: { events.append("targetModeAcknowledged") },
        awaitTargetSettled: { events.append("targetSettled") },
        closeSource: { events.append("sourceClosed") }
      )
    } catch {
      fail("target-first transaction unexpectedly failed")
    }
    expect(
      events == [
        "targetAttached", "targetBound", "targetModeAcknowledged", "targetSettled",
        "sourceClosed",
      ],
      "source closes only after the target is settled"
    )
  }

  @MainActor
  private static func testTargetFailurePreservesSourceStep() async {
    var events = [String]()
    do {
      try await VisionPresentationTransaction.presentTarget(
        prepareTarget: { events.append("targetAttached") },
        migrateAndBind: {
          events.append("targetBindingFailed")
          throw ExpectedFailure()
        },
        requestAndAwaitMode: { events.append("unexpectedMode") },
        awaitTargetSettled: { events.append("unexpectedSettle") },
        closeSource: { events.append("unexpectedSourceClose") }
      )
      fail("target failure was swallowed")
    } catch is ExpectedFailure {
    } catch {
      fail("target failure changed type")
    }
    expect(
      events == ["targetAttached", "targetBindingFailed"],
      "a failed target never closes the healthy source"
    )
  }

  @MainActor
  private static func testRollbackOrder() async {
    var events = [String]()
    do {
      try await VisionPresentationTransaction.restoreSource(
        ensureSourceContainers: { events.append("sourceAttached") },
        restoreIntentAndBinding: { events.append("sourceBound") },
        requestAndAwaitMode: { events.append("sourceModeAcknowledged") },
        awaitSourceSettled: { events.append("sourceSettled") },
        closeFailedTarget: { events.append("failedTargetClosed") }
      )
    } catch {
      fail("rollback transaction unexpectedly failed")
    }
    expect(
      events == [
        "sourceAttached", "sourceBound", "sourceModeAcknowledged", "sourceSettled",
        "failedTargetClosed",
      ],
      "rollback restores and settles the source before cleaning up the failed target"
    )
  }

  @MainActor
  private static func testRollbackFailureIsExplicit() async {
    var events = [String]()
    do {
      try await VisionPresentationTransaction.restoreSource(
        ensureSourceContainers: { events.append("sourceAttached") },
        restoreIntentAndBinding: { events.append("sourceBound") },
        requestAndAwaitMode: { events.append("sourceModeAcknowledged") },
        awaitSourceSettled: {
          events.append("sourceSettleFailed")
          throw ExpectedFailure()
        },
        closeFailedTarget: { events.append("unexpectedTargetClose") }
      )
      fail("rollback failure was swallowed")
    } catch is ExpectedFailure {
    } catch {
      fail("rollback failure changed type")
    }
    expect(
      events == [
        "sourceAttached", "sourceBound", "sourceModeAcknowledged", "sourceSettleFailed",
      ],
      "rollback failure propagates and does not claim target cleanup"
    )
  }

  @MainActor
  private static func testCloseNeedsDetachAcknowledgement() async {
    let policy = VisionPresentationWaitPolicy(
      windowOpen: .milliseconds(1),
      windowClose: .milliseconds(1),
      sceneOpen: .milliseconds(1),
      sceneClose: .milliseconds(1)
    )
    let coordinator = VisionPresentationCoordinator(waitPolicy: policy)
    var windowAttachment: VisionSurfaceAttachment?
    var sceneAttachment: VisionSurfaceAttachment?
    let actions = VisionPresentationActions(
      openWindow: { _, request in
        let attachment = VisionSurfaceAttachment(request: request)
        windowAttachment = attachment
        coordinator.surfaceDidAttach(.playbackWindow, attachment: attachment)
      },
      dismissWindow: { _, _ in },
      openImmersiveSpace: { _, request in
        let attachment = VisionSurfaceAttachment(request: request)
        sceneAttachment = attachment
        coordinator.surfaceDidAttach(.scene, attachment: attachment)
        return .opened
      },
      dismissImmersiveSpace: {}
    )

    await coordinator.openPlaybackWindow(actions: actions)
    expect(coordinator.isWindowOpen, "window setup attaches")
    await coordinator.closePlaybackWindow(actions: actions)
    expect(coordinator.isWindowOpen, "window remains actually attached after close timeout")
    expect(
      coordinator.windowLifecycle == .failed("playbackWindowDidNotDetach"),
      "window timeout is failed rather than closed"
    )
    coordinator.surfaceDidDetach(.playbackWindow, attachment: windowAttachment!)
    expect(
      !coordinator.isWindowOpen && coordinator.windowLifecycle == .closed,
      "window becomes closed only after detach"
    )

    await coordinator.openScene(actions: actions)
    expect(coordinator.isSceneOpen, "scene setup attaches")
    await coordinator.closeScene(actions: actions)
    expect(coordinator.isSceneOpen, "scene remains actually attached after close timeout")
    expect(
      coordinator.facts.sceneLifecycle == .failed("sceneDidNotDetach"),
      "scene timeout is failed rather than closed"
    )
    coordinator.surfaceDidDetach(.scene, attachment: sceneAttachment!)
    expect(
      !coordinator.isSceneOpen && coordinator.facts.sceneLifecycle == .closed,
      "scene becomes closed only after detach"
    )
  }

  @MainActor
  private static func testLateAttachIsRejected() async {
    let coordinator = VisionPresentationCoordinator(
      waitPolicy: VisionPresentationWaitPolicy(
        windowOpen: .milliseconds(1),
        windowClose: .milliseconds(1),
        sceneOpen: .milliseconds(1),
        sceneClose: .milliseconds(1)
      )
    )
    var lateWindowRequest: VisionSurfaceRequest?
    let actions = VisionPresentationActions(
      openWindow: { _, request in lateWindowRequest = request },
      dismissWindow: { _, _ in },
      openImmersiveSpace: { _, _ in .opened },
      dismissImmersiveSpace: {}
    )
    await coordinator.openPlaybackWindow(actions: actions)
    expect(
      coordinator.windowLifecycle == .failed("playbackWindowDidNotAttach"),
      "window open timeout is explicit"
    )
    expect(
      !coordinator.surfaceDidAttach(
        .playbackWindow,
        attachment: VisionSurfaceAttachment(request: lateWindowRequest!)
      ),
      "late window attach is rejected after the request times out"
    )
    expect(
      coordinator.windowLifecycle == .failed("unexpectedPlaybackWindowAttach"),
      "late window attach remains a failure until the view dismisses"
    )
  }

  @MainActor
  private static func testRetryRejectsStaleAndDuplicateAttachments() async {
    let policy = shortPolicy()
    let coordinator = VisionPresentationCoordinator(waitPolicy: policy)
    var windowRequests = [VisionSurfaceRequest]()
    var activeWindow: VisionSurfaceAttachment?
    var sceneRequests = [VisionSurfaceRequest]()
    var activeScene: VisionSurfaceAttachment?
    let actions = VisionPresentationActions(
      openWindow: { _, request in
        windowRequests.append(request)
        guard windowRequests.count == 2 else { return }
        expect(
          !coordinator.surfaceDidAttach(
            .playbackWindow,
            attachment: VisionSurfaceAttachment(request: windowRequests[0])
          ),
          "a stale Window request cannot satisfy a retry"
        )
        let attachment = VisionSurfaceAttachment(request: request)
        activeWindow = attachment
        expect(
          coordinator.surfaceDidAttach(.playbackWindow, attachment: attachment),
          "the current Window request attaches"
        )
      },
      dismissWindow: { _, _ in },
      openImmersiveSpace: { _, request in
        sceneRequests.append(request)
        guard sceneRequests.count == 2 else { return .opened }
        expect(
          !coordinator.surfaceDidAttach(
            .scene,
            attachment: VisionSurfaceAttachment(request: sceneRequests[0])
          ),
          "a stale Scene request cannot satisfy a retry"
        )
        let attachment = VisionSurfaceAttachment(request: request)
        activeScene = attachment
        expect(
          coordinator.surfaceDidAttach(.scene, attachment: attachment),
          "the current Scene request attaches"
        )
        return .opened
      },
      dismissImmersiveSpace: {}
    )

    await coordinator.openPlaybackWindow(actions: actions)
    await coordinator.openPlaybackWindow(actions: actions)
    expect(coordinator.windowLifecycle == .open, "Window retry reaches the current attachment")
    let duplicateWindow = VisionSurfaceAttachment(request: activeWindow!.request)
    expect(
      !coordinator.surfaceDidAttach(.playbackWindow, attachment: duplicateWindow),
      "a second Window instance for one request is rejected"
    )
    expect(
      !coordinator.surfaceDidDetach(.playbackWindow, attachment: duplicateWindow)
        && coordinator.isWindowOpen,
      "a rejected Window instance cannot detach the active one"
    )
    coordinator.surfaceDidDetach(.playbackWindow, attachment: activeWindow!)

    await coordinator.openScene(actions: actions)
    await coordinator.openScene(actions: actions)
    expect(coordinator.facts.sceneLifecycle == .open, "Scene retry reaches the current attachment")
    let duplicateScene = VisionSurfaceAttachment(request: activeScene!.request)
    expect(
      !coordinator.surfaceDidAttach(.scene, attachment: duplicateScene),
      "a second Scene instance for one request is rejected"
    )
    expect(
      !coordinator.surfaceDidDetach(.scene, attachment: duplicateScene)
        && coordinator.isSceneOpen,
      "a rejected Scene instance cannot detach the active one"
    )
  }

  @MainActor
  private static func testCloseTimeoutCannotClaimReopen() async {
    let coordinator = VisionPresentationCoordinator(waitPolicy: shortPolicy())
    var windowRequests = [VisionSurfaceRequest]()
    var windowAttachments = [VisionSurfaceAttachment]()
    var sceneRequests = [VisionSurfaceRequest]()
    var sceneAttachments = [VisionSurfaceAttachment]()
    let actions = VisionPresentationActions(
      openWindow: { _, request in
        windowRequests.append(request)
        let attachment = VisionSurfaceAttachment(request: request)
        windowAttachments.append(attachment)
        coordinator.surfaceDidAttach(.playbackWindow, attachment: attachment)
      },
      dismissWindow: { _, _ in },
      openImmersiveSpace: { _, request in
        sceneRequests.append(request)
        let attachment = VisionSurfaceAttachment(request: request)
        sceneAttachments.append(attachment)
        coordinator.surfaceDidAttach(.scene, attachment: attachment)
        return .opened
      },
      dismissImmersiveSpace: {}
    )

    await coordinator.openPlaybackWindow(actions: actions)
    await coordinator.closePlaybackWindow(actions: actions)
    await coordinator.openPlaybackWindow(actions: actions)
    expect(
      windowRequests.count == 1
        && coordinator.windowLifecycle == .failed("playbackWindowDidNotDetach"),
      "a Window close timeout cannot be reported as a successful reopen"
    )
    coordinator.surfaceDidDetach(.playbackWindow, attachment: windowAttachments[0])
    await coordinator.openPlaybackWindow(actions: actions)
    expect(
      windowRequests.count == 2 && coordinator.windowLifecycle == .open,
      "Window may reopen only after the timed-out attachment detaches"
    )
    coordinator.surfaceDidDetach(.playbackWindow, attachment: windowAttachments[1])

    await coordinator.openScene(actions: actions)
    await coordinator.closeScene(actions: actions)
    await coordinator.openScene(actions: actions)
    expect(
      sceneRequests.count == 1
        && coordinator.facts.sceneLifecycle == .failed("sceneDidNotDetach"),
      "a Scene close timeout cannot be reported as a successful reopen"
    )
    coordinator.surfaceDidDetach(.scene, attachment: sceneAttachments[0])
    await coordinator.openScene(actions: actions)
    expect(
      sceneRequests.count == 2 && coordinator.facts.sceneLifecycle == .open,
      "Scene may reopen only after the timed-out attachment detaches"
    )
  }

  @MainActor
  private static func testSceneAttachDuringTimeoutDismissIsRejected() async {
    let coordinator = VisionPresentationCoordinator(waitPolicy: shortPolicy())
    var request: VisionSurfaceRequest?
    var lateAttachAccepted = true
    let actions = VisionPresentationActions(
      openWindow: { _, _ in },
      dismissWindow: { _, _ in },
      openImmersiveSpace: { _, value in
        request = value
        return .opened
      },
      dismissImmersiveSpace: {
        lateAttachAccepted = coordinator.surfaceDidAttach(
          .scene,
          attachment: VisionSurfaceAttachment(request: request!)
        )
      }
    )

    await coordinator.openScene(actions: actions)
    expect(!lateAttachAccepted, "Scene timeout revokes its request before awaiting dismissal")
    expect(
      !coordinator.isSceneOpen
        && coordinator.facts.sceneLifecycle == .failed("sceneDidNotAttach")
        && coordinator.facts.sceneContent == nil,
      "a timeout cannot leave an attached failed Scene"
    )
  }

  @MainActor
  private static func testSceneAttachOutranksContradictoryOpenResult() async {
    let coordinator = VisionPresentationCoordinator(waitPolicy: shortPolicy())
    var attachment: VisionSurfaceAttachment?
    let actions = VisionPresentationActions(
      openWindow: { _, _ in },
      dismissWindow: { _, _ in },
      openImmersiveSpace: { _, request in
        let value = VisionSurfaceAttachment(request: request)
        attachment = value
        coordinator.surfaceDidAttach(.scene, attachment: value)
        return .failed("contradictoryResult")
      },
      dismissImmersiveSpace: {}
    )

    await coordinator.openScene(actions: actions)
    expect(
      coordinator.isSceneOpen
        && coordinator.facts.sceneLifecycle == .open
        && coordinator.facts.sceneContent == .customScene,
      "an actually attached Scene cannot be rewritten into a mixed failed state"
    )
    coordinator.surfaceDidDetach(.scene, attachment: attachment!)
  }

  private static func shortPolicy() -> VisionPresentationWaitPolicy {
    VisionPresentationWaitPolicy(
      windowOpen: .milliseconds(1),
      windowClose: .milliseconds(1),
      sceneOpen: .milliseconds(1),
      sceneClose: .milliseconds(1)
    )
  }

  private static func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String
  ) {
    if !condition() { fail(message) }
  }

  private static func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("RED \(message)\n".utf8))
    exit(EXIT_FAILURE)
  }
}
