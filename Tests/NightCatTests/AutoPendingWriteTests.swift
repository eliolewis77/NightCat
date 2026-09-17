import XCTest

/// Decisions taken while an auto-mode write is still travelling.
///
/// A dispatched write hasn't moved `isEnabled` yet — that happens in its reply —
/// so anything deciding against the shown state during that window is comparing
/// against a state the system has already left. These pin the four sequences
/// where that distinction decides the outcome.
final class AutoPendingWriteTests: XCTestCase {

    private var auto: SafetySettings {
        var s = SafetySettings.default
        s.autoEnableWhenCharging = true
        return s
    }

    private let onPower = BatteryInfo(percent: 80, onAC: true)
    private let offPower = BatteryInfo(percent: 80, onAC: false)

    /// Where the system is heading, which is what every decision compares to.
    private func effective(pending: Bool?, live: Bool) -> Bool {
        AutoEnablePolicy.effectiveState(pendingTarget: pending, live: live)
    }

    // MARK: 1 — pending ON + disarm ⇒ corrective OFF

    /// The user flips the master toggle off while the "on" write is in flight.
    /// Against the shown state this reads as "already off, nothing to do", and
    /// the earlier write then lands and turns keep-awake on moments after they
    /// turned it off. Against the effective state it yields a corrective write.
    func testDisarmingDuringAPendingOnWriteIssuesACorrectiveOff() {
        let live = false                        // the reply hasn't landed yet
        let pending: Bool? = true

        XCTAssertTrue(effective(pending: pending, live: live))

        let corrective = AutoEnablePolicy.target(
            armed: false,
            currentlyEnabled: effective(pending: pending, live: live),
            battery: onPower, thermalSerious: false, settings: auto)
        XCTAssertEqual(corrective, false, "disarming mid-flight must issue a corrective off")
    }

    /// The same inputs judged against the shown state instead — the bug this
    /// guards, kept explicit so the distinction can't quietly regress.
    func testDecidingAgainstTheShownStateWouldDropTheDisarm() {
        let dropped = AutoEnablePolicy.target(
            armed: false, currentlyEnabled: false,           // shown, not effective
            battery: onPower, thermalSerious: false, settings: auto)
        XCTAssertNil(dropped, "this is precisely why the decision can't use the shown state")
    }

    // MARK: 2 — pending ON + auto mode disabled ⇒ settled now, not late

    /// Leaving auto mode settles on where the system was heading, decided at the
    /// transition. The point is that a write is issued at all: it supersedes the
    /// auto reply, so the state can't move afterwards in a mode that's gone.
    func testDisablingAutoModeSettlesOnThePendingTarget() {
        XCTAssertTrue(AutoEnablePolicy.handoffToManual(
            pendingTarget: true, conditions: SafetySnapshot(battery: onPower, thermalSerious: false),
            settings: auto))
    }

    /// Inheriting "on" is only honest while it's still allowed. Unplugged with a
    /// cutoff in reach, the settle is "off" — which is also what keeps the write
    /// unconditional: `setEnabled(true)` can be refused by the safety check
    /// *before* it claims a mutation, and a refused write supersedes nothing.
    func testDisablingAutoModeSettlesOffWhenTheTargetIsNoLongerAllowed() {
        var s = auto
        s.lowBatteryThreshold = 90                          // 80% is at/below it
        XCTAssertFalse(AutoEnablePolicy.handoffToManual(
            pendingTarget: true, conditions: SafetySnapshot(battery: offPower, thermalSerious: false),
            settings: s))

        XCTAssertFalse(AutoEnablePolicy.handoffToManual(
            pendingTarget: true, conditions: SafetySnapshot(battery: onPower, thermalSerious: true),
            settings: auto), "running hot blocks the inheritance too")
    }

    /// A pending "off" settles off, and never trips the refusal path.
    func testDisablingAutoModeDuringAPendingOffSettlesOff() {
        XCTAssertFalse(AutoEnablePolicy.handoffToManual(
            pendingTarget: false, conditions: SafetySnapshot(battery: onPower, thermalSerious: false),
            settings: auto))
    }

    // MARK: 3 — pending ON + a change that still wants ON ⇒ no duplicate

    /// Toggling something the decision doesn't depend on, while the "on" write is
    /// still travelling. The new intent agrees with what's already on its way, so
    /// there must be no second write.
    func testASettingsChangeThatStillWantsOnIssuesNoDuplicateWrite() {
        var s = auto
        s.thermalPolicy = .ignore               // irrelevant while cool and on power

        XCTAssertNil(AutoEnablePolicy.target(
            armed: true,
            currentlyEnabled: effective(pending: true, live: false),
            battery: onPower, thermalSerious: false, settings: s),
            "the write already on its way is heading where we want it")
    }

    /// And the claim on that write must survive the decision. Clearing it would
    /// lose the pending target and let the next tick dispatch a duplicate
    /// alongside a request that is still live.
    func testTheClaimSurvivesADecisionThatChangesNothing() {
        var c = AutoWriteCoordinator()
        c.issued(target: true)

        // A user-driven reconcile that concludes `nil` touches nothing.
        XCTAssertEqual(c.state, .inFlight(target: true))
        XCTAssertEqual(c.inFlightTarget, true, "the pending target must remain readable")
        XCTAssertFalse(c.mayWrite, "and the poll must still be locked out")
    }

    // MARK: 4 — a late reply cannot overwrite the corrective write

    /// The corrective write claims a new mutation, which is what strips the
    /// superseded reply of its authority. Without a write being issued at all —
    /// the `nil` decision in test 2 — there is no `beginMutation`, and the old
    /// reply stays valid: that is the whole failure.
    func testCorrectiveWriteSupersedesTheEarlierReply() {
        var sync = StateSync()
        let auto = sync.beginMutation()                     // the "on" write
        XCTAssertTrue(sync.shouldApply(auto))

        let corrective = sync.beginMutation()               // the corrective "off"
        XCTAssertFalse(sync.shouldApply(auto), "the late auto reply must be rejected")
        XCTAssertTrue(sync.shouldApply(corrective))
    }

    /// Ordering is the other half: the reply can arrive after the corrective
    /// write was issued, and must still lose.
    func testLateReplyLosesRegardlessOfArrivalOrder() {
        var sync = StateSync()
        let stale = sync.beginMutation()
        sync.beginMutation()

        // …time passes, the stale reply finally arrives…
        XCTAssertFalse(sync.shouldApply(stale))
    }

    // MARK: 5 — the decision/write seam

    /// Conditions moving between deciding and writing is what the snapshot is
    /// for. Decided while plugged in, the "on" write is permitted; re-sampled a
    /// moment later on battery below the cutoff, the very same write is refused —
    /// and a refusal claims no mutation, so it supersedes nothing.
    func testResamplingAcrossTheSeamWouldRefuseAWriteTheDecisionAllowed() {
        var s = auto
        s.lowBatteryThreshold = 90

        let decided = SafetySnapshot(battery: onPower, thermalSerious: false)
        XCTAssertTrue(AutoEnablePolicy.writeIsPermitted(target: true, conditions: decided, settings: s),
                      "the decision was taken on power, where 'on' is allowed")

        let resampled = SafetySnapshot(battery: offPower, thermalSerious: false)
        XCTAssertFalse(AutoEnablePolicy.writeIsPermitted(target: true, conditions: resampled, settings: s),
                       "re-reading a moment later can refuse the write the decision authorised")
    }

    /// So the write is checked against the snapshot it was decided from, which
    /// makes "decided allowed ⇒ not refused" hold by construction.
    func testAWriteDecidedFromASnapshotIsPermittedUnderThatSnapshot() {
        var decisions = 0
        for onAC in [true, false] {
            for percent in [0, 15, 50, 100] {
                for hot in [true, false] {
                    for threshold in [0, 20, 90] {
                        var s = auto
                        s.lowBatteryThreshold = threshold
                        let conditions = SafetySnapshot(
                            battery: BatteryInfo(percent: percent, onAC: onAC),
                            thermalSerious: hot)

                        guard let target = AutoEnablePolicy.target(
                            armed: true, currentlyEnabled: false,
                            battery: conditions.battery,
                            thermalSerious: conditions.thermalSerious,
                            settings: s) else { continue }

                        decisions += 1
                        XCTAssertTrue(
                            AutoEnablePolicy.writeIsPermitted(target: target,
                                                              conditions: conditions,
                                                              settings: s),
                            "decided \(target) from \(conditions) but the write would be refused")
                    }
                }
            }
        }
        XCTAssertGreaterThan(decisions, 0, "the `continue` must not have skipped every case")
    }

    /// The same guarantee for the handoff, which is where a refusal would be
    /// worst: it settles the mode transition, so a write that never claims a
    /// mutation leaves the auto reply free to land afterwards.
    func testEveryHandoffDecisionYieldsAPermittedWrite() {
        for pending in [true, false] {
            for onAC in [true, false] {
                for hot in [true, false] {
                    for threshold in [0, 20, 90] {
                        var s = auto
                        s.lowBatteryThreshold = threshold
                        let conditions = SafetySnapshot(
                            battery: BatteryInfo(percent: 15, onAC: onAC),
                            thermalSerious: hot)

                        let settled = AutoEnablePolicy.handoffToManual(
                            pendingTarget: pending, conditions: conditions, settings: s)

                        XCTAssertTrue(
                            AutoEnablePolicy.writeIsPermitted(target: settled,
                                                              conditions: conditions,
                                                              settings: s),
                            "handoff settled on \(settled) from \(conditions) but would be refused")
                    }
                }
            }
        }
    }

    /// And the property the corrective "off" leans on, stated on its own: an
    /// "off" write is permitted under any conditions whatsoever, so it can always
    /// claim its mutation and supersede a pending "on".
    func testAnOffWriteIsNeverRefused() {
        for onAC in [true, false] {
            for hot in [true, false] {
                for threshold in [0, 50] {
                    var s = auto
                    s.lowBatteryThreshold = threshold
                    let conditions = SafetySnapshot(
                        battery: BatteryInfo(percent: 5, onAC: onAC), thermalSerious: hot)
                    XCTAssertTrue(AutoEnablePolicy.writeIsPermitted(
                        target: false, conditions: conditions, settings: s))
                }
            }
        }
    }
}
