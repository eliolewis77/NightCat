import XCTest

/// Covers the decision logic behind issue #21: keeping the UI in step with the
/// real `SleepDisabled` flag without ever asserting a state we haven't read.
final class StateReconcilerTests: XCTestCase {

    // MARK: Reconciling a fresh read

    func testExternalEnableIsAdoptedAsDrift() {
        XCTAssertEqual(StateReconciler.reconcile(shown: false, hasBaseline: true, observed: true),
                       .drift(.enabledOutside))
        XCTAssertTrue(ExternalChange.enabledOutside.nowEnabled)
    }

    func testExternalDisableInvalidatesStaleEnabledState() {
        XCTAssertEqual(StateReconciler.reconcile(shown: true, hasBaseline: true, observed: false),
                       .drift(.disabledOutside))
        XCTAssertFalse(ExternalChange.disabledOutside.nowEnabled)
    }

    func testUnknownReadKeepsShownEnabledState() {
        XCTAssertEqual(StateReconciler.reconcile(shown: true, hasBaseline: true, observed: nil), .unknown)
    }

    func testUnknownReadKeepsShownDisabledState() {
        XCTAssertEqual(StateReconciler.reconcile(shown: false, hasBaseline: true, observed: nil), .unknown)
    }

    /// Guards idempotence: a steady-state poll must report nothing adoptable, or
    /// every pass would re-arm the auto-off timer and restart the heartbeat.
    func testAgreeingReadIsInSyncEvenWithoutBaseline() {
        XCTAssertEqual(StateReconciler.reconcile(shown: true, hasBaseline: true, observed: true), .inSync)
        XCTAssertEqual(StateReconciler.reconcile(shown: false, hasBaseline: true, observed: false), .inSync)
        XCTAssertEqual(StateReconciler.reconcile(shown: false, hasBaseline: false, observed: false), .inSync)
    }

    func testFirstDifferingObservationAdoptsWithoutWarning() {
        XCTAssertEqual(StateReconciler.reconcile(shown: false, hasBaseline: false, observed: true),
                       .adopt(enabled: true))
    }

    func testFirstObservationUnknownStaysUnknown() {
        XCTAssertEqual(StateReconciler.reconcile(shown: false, hasBaseline: false, observed: nil), .unknown)
    }

    /// End to end across the two pure layers: unreadable `pmset` output must
    /// reach the reconciler as "unknown" and leave the shown state alone, rather
    /// than parsing into a confident "off" that flips the toggle.
    func testUnreadablePmsetOutputReconcilesToUnknown() {
        for output in ["", "Currently in use:\n standby 1", " SleepDisabled        yes"] {
            let observed = PowerParsers.sleepDisabled(pmsetG: output)
            XCTAssertNil(observed, "\(output.debugDescription) states nothing about the flag")
            XCTAssertEqual(StateReconciler.reconcile(shown: true, hasBaseline: true, observed: observed),
                           .unknown)
        }
    }

    // MARK: Stale replies — reads

    func testFreshReadApplies() {
        var sync = StateSync()
        let token = sync.beginRead()
        XCTAssertTrue(sync.shouldApply(token))
    }

    func testNewerReadInvalidatesTheOlderReply() {
        var sync = StateSync()
        let first = sync.beginRead()
        let second = sync.beginRead()
        XCTAssertFalse(sync.shouldApply(first), "an out-of-order reply must not win")
        XCTAssertTrue(sync.shouldApply(second))
    }

    func testMutationInvalidatesAnInFlightRead() {
        var sync = StateSync()
        let read = sync.beginRead()
        sync.beginMutation()
        XCTAssertFalse(sync.shouldApply(read))
    }

    /// Two mutations put the value back where it started; comparing observed
    /// values could never tell that anything happened, but the counter can.
    func testABARoundTripStillInvalidatesTheRead() {
        var sync = StateSync()
        let read = sync.beginRead()
        sync.beginMutation()
        sync.beginMutation()
        XCTAssertFalse(sync.shouldApply(read))
    }

    // MARK: Stale replies — writes

    func testStaleWriteCompletionIsRejected() {
        var sync = StateSync()
        let first = sync.beginMutation()
        let second = sync.beginMutation()
        XCTAssertFalse(sync.shouldApply(first))
        XCTAssertTrue(sync.shouldApply(second))
    }

    func testOutOfOrderWriteRepliesApplyOnlyTheLatest() {
        var sync = StateSync()
        let older = sync.beginMutation()
        let newer = sync.beginMutation()
        // The older write replies last; it must still lose.
        XCTAssertTrue(sync.shouldApply(newer))
        XCTAssertFalse(sync.shouldApply(older))
    }

    /// Both writes ask for the same target, so only the counter distinguishes
    /// them — the payload is identical.
    func testDuplicateTargetWritesStillInvalidateTheOlder() {
        var sync = StateSync()
        let first = sync.beginMutation()
        let second = sync.beginMutation()
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(sync.shouldApply(first))
    }

    func testABAWriteSequenceRejectsTheFirstCompletion() {
        var sync = StateSync()
        let on = sync.beginMutation()
        sync.beginMutation()               // off
        sync.beginMutation()               // on again
        XCTAssertFalse(sync.shouldApply(on))
    }

    func testAdoptionInvalidatesAnInFlightWrite() {
        var sync = StateSync()
        let write = sync.beginMutation()
        sync.beginMutation()               // a reconciled read adopting a new state
        XCTAssertFalse(sync.shouldApply(write))
    }

    // MARK: Notice lifecycle

    /// The regression test for external-enable followed by a low-battery pause:
    /// the pause must not erase the notice that explains where the state came from.
    func testOnlyUserActionClearsTheExternalNotice() {
        XCTAssertTrue(StateReconciler.clearsExternalNotice(.user))
        XCTAssertFalse(StateReconciler.clearsExternalNotice(.safety))
        XCTAssertFalse(StateReconciler.clearsExternalNotice(.autoOff))
    }

    func testDriftMessagesDescribeTheEventNotTheResultingState() {
        // Must stay true after a safety pause flips the state straight back, so
        // it may not promise anything about what the Mac is doing now.
        for change in [ExternalChange.enabledOutside, .disabledOutside] {
            XCTAssertTrue(change.message.contains("NightCat 之外"))
            XCTAssertFalse(change.message.contains("will"))
        }
    }

    // MARK: Verifying a write

    func testVerifiedWhenReadBackMatchesTarget() {
        XCTAssertEqual(StateReconciler.verifyAfterSet(target: true, observed: true), .verified)
        XCTAssertEqual(StateReconciler.verifyAfterSet(target: false, observed: false), .verified)
    }

    /// A timed-out read-back must produce neither a false positive nor a false
    /// negative — the write did report success, we just can't confirm it.
    func testUnknownReadBackIsUnverifiedNotFailure() {
        XCTAssertEqual(StateReconciler.verifyAfterSet(target: true, observed: nil), .unverified)
        XCTAssertEqual(StateReconciler.verifyAfterSet(target: false, observed: nil), .unverified)
    }

    func testMismatchedReadBackReportsActualState() {
        XCTAssertEqual(StateReconciler.verifyAfterSet(target: true, observed: false), .mismatch(actual: false))
        XCTAssertEqual(StateReconciler.verifyAfterSet(target: false, observed: true), .mismatch(actual: true))
    }

    func testUnverifiedMessageDoesNotClaimSuccess() {
        XCTAssertTrue(StateReconciler.unverifiedMessage(target: true).contains("无法"))
        XCTAssertTrue(StateReconciler.unverifiedMessage(target: false).contains("无法"))
        XCTAssertNotEqual(StateReconciler.unverifiedMessage(target: true),
                          StateReconciler.unverifiedMessage(target: false))
    }

    // MARK: Resolving a pending verification

    /// This is what stops the "couldn't confirm" caveat sticking forever.
    func testPendingConfirmsOnMatchingFreshRead() {
        let pending = PendingVerification(target: true)
        XCTAssertEqual(StateReconciler.resolve(pending, observed: true), .confirmed)
    }

    /// We never confirmed our own write landed, so a later disagreement is a
    /// write that didn't hold — not somebody else's doing.
    func testPendingResolvesToWriteMismatchNotExternalDrift() {
        let pending = PendingVerification(target: true)
        XCTAssertEqual(StateReconciler.resolve(pending, observed: false), .writeMismatch(actual: false))

        let pendingOff = PendingVerification(target: false)
        XCTAssertEqual(StateReconciler.resolve(pendingOff, observed: true), .writeMismatch(actual: true))
    }

    func testPendingStaysUnverifiedWhenTheReadFailsAgain() {
        let pending = PendingVerification(target: true)
        XCTAssertEqual(StateReconciler.resolve(pending, observed: nil), .stillUnverified)
    }

    /// Pins the two channels apart: verification text must never read as an
    /// accusation that something else changed the flag.
    func testVerificationMessagesAreDistinctFromExternalChangeMessages() {
        let external = [ExternalChange.enabledOutside.message, ExternalChange.disabledOutside.message]
        let verification = [StateReconciler.unverifiedMessage(target: true),
                            StateReconciler.unverifiedMessage(target: false),
                            StateReconciler.writeMismatchMessage(actual: true),
                            StateReconciler.writeMismatchMessage(actual: false)]

        for message in verification {
            XCTAssertFalse(external.contains(message))
            XCTAssertFalse(message.contains("NightCat 之外"))
        }
    }
}
