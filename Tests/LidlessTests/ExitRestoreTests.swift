import XCTest

/// Pins the exit-restoration baseline policy for the `SleepDisabled` flag
/// (SPEC §9): restore what the flag was before we took it over — and only
/// when we actually took it over.
final class ExitRestoreTests: XCTestCase {

    // MARK: capture

    /// The only capture that counts: we are about to write 1 while the flag
    /// still reads 0, so the 0→1 transition is genuinely ours.
    func testCaptureWhenFlagIsOffRecordsThePreTakeoverValue() {
        XCTAssertEqual(ExitRestore.capture(current: false),
                       ExitRestore.Baseline(previous: false))
    }

    /// The boundary the whole policy turns on: the flag already reads 1 when
    /// we would enable — Amphetamine or another tool holds it. nil is the
    /// entire message: we never owned the state, so the restore on exit is
    /// not ours to issue either (writing 0 would stomp the other tool's
    /// session). The crash path is unaffected — the helper's 90-second
    /// watchdog still writes 0 there, deliberately.
    func testCaptureRefusedWhenTheFlagIsAlreadyOn() {
        XCTAssertNil(ExitRestore.capture(current: true))
    }

    // MARK: restoreValue

    func testCapturedBaselineRestoresItsOwnValue() {
        let baseline = ExitRestore.capture(current: false)
        XCTAssertEqual(ExitRestore.restoreValue(of: baseline), false)
    }

    /// SPEC's fallback: never captured → restore 0. A harmless no-op when we
    /// never wrote 1; callers that know `capture` refused ownership (external
    /// takeover) don't issue a restore at all — nil is their signal.
    func testMissingBaselineFallsBackToRestoringOff() {
        XCTAssertFalse(ExitRestore.restoreValue(of: nil))
    }
}
