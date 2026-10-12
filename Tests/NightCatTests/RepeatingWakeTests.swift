import XCTest

final class RepeatingWakeTests: XCTestCase {

    // MARK: weekdayLetters

    func testSingleWeekdayLetters() {
        XCTAssertEqual(RepeatingWake.weekdayLetters(weekdayMask: 0b0000001), "U")  // Sun
        XCTAssertEqual(RepeatingWake.weekdayLetters(weekdayMask: 0b0000010), "M")  // Mon
        XCTAssertEqual(RepeatingWake.weekdayLetters(weekdayMask: 0b1000000), "S")  // Sat
        XCTAssertEqual(RepeatingWake.weekdayLetters(weekdayMask: 0b0010000), "R")  // Thu
    }

    func testCanonicalLetterOrder() {
        XCTAssertEqual(RepeatingWake.weekdayLetters(weekdayMask: 0b0111110), "MTWRF")
        XCTAssertEqual(RepeatingWake.weekdayLetters(weekdayMask: 0b1111111), "MTWRFSU")
        // Sunday's letter travels last regardless of mask position.
        XCTAssertEqual(RepeatingWake.weekdayLetters(weekdayMask: 0b1000001), "SU")
    }

    func testEmptyAndIllegalMasksProduceNoLetters() {
        XCTAssertNil(RepeatingWake.weekdayLetters(weekdayMask: 0))
        XCTAssertNil(RepeatingWake.weekdayLetters(weekdayMask: 0b10000000))
        XCTAssertNil(RepeatingWake.weekdayLetters(weekdayMask: -1))
    }

    // MARK: pmsetArguments

    private var workdays: WeeklySchedule {
        WeeklySchedule(weekdayMask: 0b0111110, startMinute: 9 * 60, endMinute: 17 * 60)
    }

    func testRegisterArguments() {
        XCTAssertEqual(RepeatingWake.pmsetArguments(weekdayMask: 0b0111110, minutes: 9 * 60, enabled: true),
                       ["repeat", "wake", "MTWRF", "09:00:00"])
    }

    func testMinuteBoundaries() {
        XCTAssertEqual(RepeatingWake.pmsetArguments(weekdayMask: 0b0000010, minutes: 0, enabled: true)?[3],
                       "00:00:00")
        XCTAssertEqual(RepeatingWake.pmsetArguments(weekdayMask: 0b0000010, minutes: 1439, enabled: true)?[3],
                       "23:59:00")
        XCTAssertEqual(RepeatingWake.pmsetArguments(weekdayMask: 0b0000010, minutes: 22 * 60, enabled: true)?[3],
                       "22:00:00")
    }

    func testCancelIgnoresTheRuleEntirely() {
        XCTAssertEqual(RepeatingWake.pmsetArguments(weekdayMask: -999, minutes: 99_999, enabled: false),
                       ["repeat", "cancel"])
    }

    func testIllegalRegisterParametersAreRefused() {
        XCTAssertNil(RepeatingWake.pmsetArguments(weekdayMask: 0, minutes: 600, enabled: true))
        XCTAssertNil(RepeatingWake.pmsetArguments(weekdayMask: 0b10000000, minutes: 600, enabled: true))
        XCTAssertNil(RepeatingWake.pmsetArguments(weekdayMask: 0b0000010, minutes: 1440, enabled: true))
        XCTAssertNil(RepeatingWake.pmsetArguments(weekdayMask: 0b0000010, minutes: -1, enabled: true))
    }

    // MARK: shellScript

    func testShellScriptEmbedsTheSameCommand() {
        let script = RepeatingWake.shellScript(weekdayMask: 0b0111110, minutes: 9 * 60, enabled: true)
        XCTAssertEqual(script,
                       #"do shell script "/usr/bin/pmset repeat wake MTWRF 09:00:00" with administrator privileges"#)
    }

    func testCancelShellScript() {
        XCTAssertEqual(RepeatingWake.shellScript(weekdayMask: 0, minutes: 0, enabled: false),
                       #"do shell script "/usr/bin/pmset repeat cancel" with administrator privileges"#)
    }

    // MARK: isHelperSupported

    func testVersionComparison() {
        XCTAssertTrue(RepeatingWake.isHelperSupported(version: "0.2.0"))
        XCTAssertTrue(RepeatingWake.isHelperSupported(version: "0.3.0"))
        XCTAssertTrue(RepeatingWake.isHelperSupported(version: "1.0"))
        XCTAssertTrue(RepeatingWake.isHelperSupported(version: "0.2"))
        XCTAssertTrue(RepeatingWake.isHelperSupported(version: "0.2.0.1"))
        XCTAssertFalse(RepeatingWake.isHelperSupported(version: "0.1.0"))
        XCTAssertFalse(RepeatingWake.isHelperSupported(version: "0.1.9"))
    }

    func testUnparsableVersionsFailClosed() {
        XCTAssertFalse(RepeatingWake.isHelperSupported(version: ""))
        XCTAssertFalse(RepeatingWake.isHelperSupported(version: "abc"))
        XCTAssertFalse(RepeatingWake.isHelperSupported(version: "0.x.0"))
    }

    // MARK: decision

    func testRegisterForAnActiveValidRule() {
        XCTAssertEqual(RepeatingWake.decision(enabled: true, autoModeOn: false, schedule: workdays),
                       .register(weekdayMask: 0b0111110, minutes: 9 * 60))
    }

    func testOvernightWindowWakesAtItsStartDay() {
        let overnight = WeeklySchedule(weekdayMask: 0b0000010, startMinute: 22 * 60, endMinute: 6 * 60)
        XCTAssertEqual(RepeatingWake.decision(enabled: true, autoModeOn: false, schedule: overnight),
                       .register(weekdayMask: 0b0000010, minutes: 22 * 60))
    }

    func testRulesThatCanNeverFireCancel() {
        let noDays = WeeklySchedule(weekdayMask: 0, startMinute: 9 * 60, endMinute: 17 * 60)
        let zeroLength = WeeklySchedule(weekdayMask: 0b0111110, startMinute: 9 * 60, endMinute: 9 * 60)
        XCTAssertEqual(RepeatingWake.decision(enabled: true, autoModeOn: false, schedule: noDays), .cancel)
        XCTAssertEqual(RepeatingWake.decision(enabled: true, autoModeOn: false, schedule: zeroLength), .cancel)
        XCTAssertEqual(RepeatingWake.decision(enabled: true, autoModeOn: false, schedule: nil), .cancel)
    }

    func testAutoModeSuspendsTheWake() {
        XCTAssertEqual(RepeatingWake.decision(enabled: true, autoModeOn: true, schedule: workdays), .cancel)
    }

    func testDisabledScheduleCancelsWhateverIsThere() {
        XCTAssertEqual(RepeatingWake.decision(enabled: false, autoModeOn: false, schedule: workdays), .cancel)
        XCTAssertEqual(RepeatingWake.decision(enabled: false, autoModeOn: true, schedule: nil), .cancel)
    }

    // MARK: Decision persistence

    func testDecisionCodableRoundTrip() throws {
        // The believed wake state persists as JSON across launches.
        let register = RepeatingWake.Decision.register(weekdayMask: 0b0111110, minutes: 540)
        let data = try JSONEncoder().encode(register)
        XCTAssertEqual(try JSONDecoder().decode(RepeatingWake.Decision.self, from: data), register)
        let cancel = RepeatingWake.Decision.cancel
        XCTAssertEqual(try JSONDecoder().decode(RepeatingWake.Decision.self,
                                                from: JSONEncoder().encode(cancel)), cancel)
        // register and cancel must not decode into each other.
        XCTAssertNotEqual(try JSONDecoder().decode(RepeatingWake.Decision.self, from: data), cancel)
    }

    // MARK: pmset -g sched read-back

    func testArmedDetectionInSchedOutput() {
        let armed = """
        Scheduled power events:
         [0] wake at 10/11/2026 11:11:41 by 'com.apple.alarm.user-invisible-com.apple.calaccessd.travelEngine.periodicRefreshTimer'
        Repeating power events:
          wake at 9:00:00 every MTWRF
        """
        XCTAssertTrue(RepeatingWake.isArmed(inSchedOutput: armed))
    }

    func testUnarmedDetectionInSchedOutput() {
        let oneShotOnly = """
        Scheduled power events:
         [0] wake at 10/11/2026 11:11:41 by 'com.apple.alarm.user-invisible-com.apple.calaccessd.travelEngine.periodicRefreshTimer'
        """
        XCTAssertFalse(RepeatingWake.isArmed(inSchedOutput: oneShotOnly))
        XCTAssertFalse(RepeatingWake.isArmed(inSchedOutput: ""))
    }
}
