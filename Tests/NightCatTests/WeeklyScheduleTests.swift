import XCTest

final class WeeklyScheduleTests: XCTestCase {

    /// GMT so a "minute of day" is also a UTC hour — no DST, no ambiguity.
    private var calendar = Calendar(identifier: .gregorian)

    override func setUpWithError() throws {
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    // 2026-10-05 is a Monday; offsets run from there.
    private func date(dayOffset: Int, hour: Int, minute: Int = 0) -> Date {
        let monday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5))!
        let day = calendar.date(byAdding: .day, value: dayOffset, to: monday)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    /// Weekday mask helpers (Calendar weekday: 1 = Sunday … 7 = Saturday).
    private var monFri: Int { 0b0111110 }
    private func mask(_ weekday: Int) -> Int { WeeklySchedule.mask(forWeekday: weekday) }

    private var workdays: WeeklySchedule {
        WeeklySchedule(weekdayMask: monFri, startMinute: 9 * 60, endMinute: 17 * 60)
    }

    /// Monday 22:00 – 06:00 next morning.
    private var overnightMonday: WeeklySchedule {
        WeeklySchedule(weekdayMask: mask(2), startMinute: 22 * 60, endMinute: 6 * 60)
    }

    private func makeDirector(handled: Date? = nil) -> ScheduleDirector {
        ScheduleDirector(lastHandledWindowStart: handled)
    }

    // MARK: WeeklySchedule.contains

    func testWorkdayWindowContainsMidday() {
        XCTAssertTrue(workdays.contains(date(dayOffset: 2, hour: 12), calendar: calendar))  // Wed
    }

    func testWindowExcludesBeforeStartAndEnd() {
        XCTAssertFalse(workdays.contains(date(dayOffset: 2, hour: 8, minute: 59), calendar: calendar))
        XCTAssertFalse(workdays.contains(date(dayOffset: 2, hour: 17), calendar: calendar))
    }

    func testWindowBoundariesAreHalfOpen() {
        XCTAssertTrue(workdays.contains(date(dayOffset: 2, hour: 9), calendar: calendar))
        XCTAssertFalse(workdays.contains(date(dayOffset: 2, hour: 17), calendar: calendar))
    }

    func testWindowExcludesUnselectedWeekday() {
        XCTAssertFalse(workdays.contains(date(dayOffset: 5, hour: 12), calendar: calendar))  // Sat
    }

    func testOvernightWindowEveningHalf() {
        XCTAssertTrue(overnightMonday.contains(date(dayOffset: 0, hour: 23), calendar: calendar))
    }

    func testOvernightWindowMorningTailBelongsToStartDay() {
        XCTAssertTrue(overnightMonday.contains(date(dayOffset: 1, hour: 2), calendar: calendar))
        XCTAssertTrue(overnightMonday.contains(date(dayOffset: 1, hour: 5, minute: 59), calendar: calendar))
        XCTAssertFalse(overnightMonday.contains(date(dayOffset: 1, hour: 6), calendar: calendar))
    }

    func testOvernightWindowEveningHalfNeedsTheDaySelected() {
        // Tuesday is not selected: its own evening is outside the window.
        XCTAssertFalse(overnightMonday.contains(date(dayOffset: 1, hour: 23), calendar: calendar))
        // Select Tuesday and its evening is in.
        var both = overnightMonday
        both.weekdayMask |= mask(3)
        XCTAssertTrue(both.contains(date(dayOffset: 1, hour: 23), calendar: calendar))
    }

    func testZeroLengthWindowNeverFires() {
        let empty = WeeklySchedule(weekdayMask: monFri, startMinute: 9 * 60, endMinute: 9 * 60)
        XCTAssertFalse(empty.contains(date(dayOffset: 2, hour: 12), calendar: calendar))
    }

    func testNoWeekdaysSelectedNeverFires() {
        let none = WeeklySchedule(weekdayMask: 0, startMinute: 9 * 60, endMinute: 17 * 60)
        XCTAssertFalse(none.contains(date(dayOffset: 2, hour: 12), calendar: calendar))
    }

    // MARK: WeeklySchedule.windowStart

    func testWindowStartInsideNormalWindowIsSameDay() {
        XCTAssertEqual(workdays.windowStart(containing: date(dayOffset: 2, hour: 12), calendar: calendar),
                       date(dayOffset: 2, hour: 9))
    }

    func testWindowStartInOvernightTailIsPreviousDay() {
        XCTAssertEqual(overnightMonday.windowStart(containing: date(dayOffset: 1, hour: 2), calendar: calendar),
                       date(dayOffset: 0, hour: 22))
    }

    func testWindowStartOutsideEveryWindowIsNil() {
        XCTAssertNil(workdays.windowStart(containing: date(dayOffset: 5, hour: 12), calendar: calendar))
    }

    // MARK: WeeklySchedule.nextStart

    func testNextStartSkipsToNextSelectedDay() {
        XCTAssertEqual(workdays.nextStart(after: date(dayOffset: 0, hour: 18), calendar: calendar),
                       date(dayOffset: 1, hour: 9))
    }

    func testNextStartWrapsPastWeekend() {
        XCTAssertEqual(workdays.nextStart(after: date(dayOffset: 4, hour: 18), calendar: calendar),
                       date(dayOffset: 7, hour: 9))
    }

    func testNextStartSameDayBeforeStart() {
        XCTAssertEqual(workdays.nextStart(after: date(dayOffset: 2, hour: 7), calendar: calendar),
                       date(dayOffset: 2, hour: 9))
    }

    func testNextStartInsideWindowPointsPastIt() {
        XCTAssertEqual(workdays.nextStart(after: date(dayOffset: 2, hour: 12), calendar: calendar),
                       date(dayOffset: 3, hour: 9))
    }

    func testNextStartNilWithoutWeekdays() {
        let none = WeeklySchedule(weekdayMask: 0, startMinute: 9 * 60, endMinute: 17 * 60)
        XCTAssertNil(none.nextStart(after: date(dayOffset: 2, hour: 12), calendar: calendar))
    }

    // MARK: ScheduleDirector — edges and ownership

    private func tick(_ director: inout ScheduleDirector,
                      _ at: Date,
                      schedule: WeeklySchedule? = nil,
                      tierActive: Bool = false) -> ScheduleDirective {
        director.tick(now: at, schedule: schedule ?? workdays, tierActive: tierActive,
                      autoModeOn: false, calendar: calendar)
    }

    func testWindowStartEdgeEnablesWhenNoTierActive() {
        var director = makeDirector()
        XCTAssertEqual(tick(&director, date(dayOffset: 2, hour: 9, minute: 0)), .enableLid)
        XCTAssertTrue(director.ownsActivation)
    }

    func testWindowStartEdgeStaysSilentWhenTierAlreadyActive() {
        var director = makeDirector()
        XCTAssertEqual(tick(&director, date(dayOffset: 2, hour: 9), tierActive: true), .none)
        XCTAssertFalse(director.ownsActivation)
        // And it doesn't undo the stranger's hold at window end.
        XCTAssertEqual(tick(&director, date(dayOffset: 2, hour: 17, minute: 0), tierActive: true), .none)
    }

    func testSubsequentTicksInsideWindowDoNothing() {
        var director = makeDirector()
        XCTAssertEqual(tick(&director, date(dayOffset: 2, hour: 9, minute: 1)), .enableLid)
        XCTAssertEqual(tick(&director, date(dayOffset: 2, hour: 12)), .none)
        XCTAssertEqual(tick(&director, date(dayOffset: 2, hour: 16, minute: 59)), .none)
    }

    func testManualOffMidWindowKeepsTheWindowSilent() {
        var director = makeDirector()
        XCTAssertEqual(tick(&director, date(dayOffset: 2, hour: 9)), .enableLid)
        director.noteWrite(origin: .user, landedActive: false)
        XCTAssertEqual(tick(&director, date(dayOffset: 2, hour: 12)), .none)
        XCTAssertEqual(tick(&director, date(dayOffset: 2, hour: 17)), .none)
    }

    func testUserEnabledHoldIsNotUndoneAtWindowEnd() {
        var director = makeDirector()
        XCTAssertEqual(tick(&director, date(dayOffset: 2, hour: 12), tierActive: true), .none)
        director.noteWrite(origin: .user, landedActive: true)
        XCTAssertEqual(tick(&director, date(dayOffset: 2, hour: 17), tierActive: true), .none)
    }

    func testForeignWriteClearsOwnership() {
        for origin in [SetOrigin.safety, .autoOff, .user] {
            var director = makeDirector()
            XCTAssertEqual(tick(&director, date(dayOffset: 2, hour: 9)), .enableLid)
            director.noteWrite(origin: origin, landedActive: false)
            XCTAssertEqual(tick(&director, date(dayOffset: 2, hour: 17), tierActive: true), .none,
                           "origin \(origin) must cancel the schedule's claim")
        }
    }

    func testWindowEndDisablesItsOwnHold() {
        var director = makeDirector()
        XCTAssertEqual(tick(&director, date(dayOffset: 2, hour: 9)), .enableLid)
        XCTAssertEqual(tick(&director, date(dayOffset: 2, hour: 17), tierActive: true), .disableLid)
        director.noteWrite(origin: .schedule, landedActive: false)
        XCTAssertFalse(director.ownsActivation)
    }

    func testWindowEndSkipsTheWriteWhenHoldAlreadyDark() {
        var director = makeDirector()
        XCTAssertEqual(tick(&director, date(dayOffset: 2, hour: 9)), .enableLid)
        // The safety pause turned it off mid-window (ownership silently gone).
        XCTAssertEqual(tick(&director, date(dayOffset: 2, hour: 12), tierActive: false), .none)
        XCTAssertFalse(director.ownsActivation)
        XCTAssertEqual(tick(&director, date(dayOffset: 2, hour: 17)), .none)
    }

    func testOvernightWindowFullCycle() {
        var director = makeDirector()
        XCTAssertEqual(tick(&director, date(dayOffset: 0, hour: 23), schedule: overnightMonday), .enableLid)
        XCTAssertEqual(tick(&director, date(dayOffset: 0, hour: 23, minute: 30), schedule: overnightMonday, tierActive: true), .none)
        XCTAssertEqual(tick(&director, date(dayOffset: 1, hour: 2), schedule: overnightMonday, tierActive: true), .none)
        XCTAssertEqual(tick(&director, date(dayOffset: 1, hour: 6), schedule: overnightMonday, tierActive: true), .disableLid)
    }

    // MARK: ScheduleDirector — restart alignment

    func testHandledWindowIsNotReplayedAfterRestart() {
        let windowStart = date(dayOffset: 2, hour: 9)
        var director = makeDirector()
        XCTAssertEqual(tick(&director, windowStart), .enableLid)
        // The app relaunches; the persisted marker comes back in a fresh director.
        var restarted = makeDirector(handled: director.lastHandledWindowStart)
        XCTAssertEqual(tick(&restarted, date(dayOffset: 2, hour: 12)), .none)
        XCTAssertEqual(tick(&restarted, date(dayOffset: 2, hour: 17), tierActive: true), .none)
    }

    func testUnobservedWindowStartBackfillsOnLaunch() {
        // The Mac was off (or the app quit) across the boundary: no marker, so
        // the first tick inside the window is the observed start.
        var director = makeDirector(handled: date(dayOffset: 1, hour: 9))  // yesterday's window
        XCTAssertEqual(tick(&director, date(dayOffset: 2, hour: 12)), .enableLid)
    }

    func testNextWindowFiresAfterAHandledOne() {
        var director = makeDirector()
        XCTAssertEqual(tick(&director, date(dayOffset: 2, hour: 9)), .enableLid)
        XCTAssertEqual(tick(&director, date(dayOffset: 2, hour: 17), tierActive: true), .disableLid)
        XCTAssertEqual(tick(&director, date(dayOffset: 3, hour: 9)), .enableLid)
    }

    // MARK: ScheduleDirector — suspension

    func testAutoModeSuspendsTheDirector() {
        var director = makeDirector()
        let before = director
        let directive = director.tick(now: date(dayOffset: 2, hour: 12),
                                      schedule: workdays,
                                      tierActive: false,
                                      autoModeOn: true,
                                      calendar: calendar)
        XCTAssertEqual(directive, .none)
        XCTAssertEqual(director, before, "a suspended tick must change nothing")
    }

    func testDisabledScheduleSuspendsThenResumesWithALateEdge() {
        var director = makeDirector()
        // Frozen while off…
        XCTAssertEqual(director.tick(now: date(dayOffset: 2, hour: 9),
                                     schedule: nil,
                                     tierActive: false,
                                     autoModeOn: false,
                                     calendar: calendar), .none)
        // …so enabling mid-window with nothing running *is* the request.
        XCTAssertEqual(tick(&director, date(dayOffset: 2, hour: 12)), .enableLid)
    }

    func testSwitchOffOnWithinTheSameWindowDoesNotRelight() {
        var director = makeDirector()
        XCTAssertEqual(tick(&director, date(dayOffset: 2, hour: 9)), .enableLid)
        director.noteWrite(origin: .user, landedActive: false)
        director.relinquish()
        // Off: frozen. Back on mid-window: the edge was already consumed.
        XCTAssertEqual(director.tick(now: date(dayOffset: 2, hour: 12),
                                     schedule: nil,
                                     tierActive: false,
                                     autoModeOn: false,
                                     calendar: calendar), .none)
        XCTAssertEqual(tick(&director, date(dayOffset: 2, hour: 14)), .none)
    }

    func testAdoptedOffClearsOwnership() {
        var director = makeDirector()
        XCTAssertEqual(tick(&director, date(dayOffset: 2, hour: 9)), .enableLid)
        director.noteAdopted(active: false)
        XCTAssertEqual(tick(&director, date(dayOffset: 2, hour: 17), tierActive: true), .none)
    }

    func testAdoptedOnKeepsOwnershipDecisionUntouched() {
        var director = makeDirector()
        XCTAssertEqual(tick(&director, date(dayOffset: 2, hour: 9)), .enableLid)
        director.noteAdopted(active: true)
        XCTAssertTrue(director.ownsActivation)
    }

    // MARK: WeeklySchedule.sanitized

    func testSanitizedClampsOutOfRangeFields() {
        let raw = WeeklySchedule(weekdayMask: 0b1111111 | 0b1_0000_0000,
                                 startMinute: -5, endMinute: 2000)
        XCTAssertEqual(raw.sanitized, WeeklySchedule(weekdayMask: 0b1111111,
                                                     startMinute: 0, endMinute: 1439))
    }

    // MARK: SettingsStore — schedule persistence

    private func freshStore(_ name: String) -> (SettingsStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (SettingsStore(defaults: defaults), defaults)
    }

    func testAbsentKeysFallBackToDefaults() {
        let (store, _) = freshStore("lidless.test.schedule.absent")
        XCTAssertFalse(store.loadScheduleEnabled())
        XCTAssertEqual(store.loadSchedule(), .default)
        XCTAssertNil(store.loadHandledWindowStart())
    }

    func testScheduleRoundTripIncludingOvernight() {
        let (store, _) = freshStore("lidless.test.schedule.roundtrip")
        let rule = WeeklySchedule(weekdayMask: mask(1) | mask(3), startMinute: 22 * 60, endMinute: 6 * 60)
        store.saveSchedule(rule)
        store.saveScheduleEnabled(true)
        XCTAssertTrue(store.loadScheduleEnabled())
        XCTAssertEqual(store.loadSchedule(), rule)
    }

    func testSavedScheduleIsSanitizedOnRead() {
        let (store, _) = freshStore("lidless.test.schedule.sanitize")
        store.saveSchedule(WeeklySchedule(weekdayMask: 0b1111111 | 0b10000_0000,
                                          startMinute: 9 * 60, endMinute: 9 * 60))
        XCTAssertEqual(store.loadSchedule(),
                       WeeklySchedule(weekdayMask: 0b1111111, startMinute: 9 * 60, endMinute: 9 * 60))
    }

    func testHandledWindowStartRoundTripAndClear() {
        let (store, _) = freshStore("lidless.test.schedule.handled")
        let at = date(dayOffset: 2, hour: 9)
        store.saveHandledWindowStart(at)
        XCTAssertEqual(store.loadHandledWindowStart(), at)
        store.saveHandledWindowStart(nil)
        XCTAssertNil(store.loadHandledWindowStart())
    }
}
