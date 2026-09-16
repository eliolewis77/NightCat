import XCTest

final class SharedLogicTests: XCTestCase {

    // MARK: PowerParsers.isSleepDisabled

    func testSleepDisabledTrue() {
        let out = """
        System-wide power settings:
         SleepDisabled        1
        Currently in use:
         standby              1
        """
        XCTAssertTrue(PowerParsers.isSleepDisabled(pmsetG: out))
    }

    func testSleepDisabledFalse() {
        let out = """
        System-wide power settings:
         SleepDisabled        0
        """
        XCTAssertFalse(PowerParsers.isSleepDisabled(pmsetG: out))
    }

    func testSleepDisabledMissing() {
        XCTAssertFalse(PowerParsers.isSleepDisabled(pmsetG: "Currently in use:\n standby 1"))
    }

    // MARK: PowerParsers.sleepDisabled — output that doesn't state the flag

    func testStrictSleepDisabledReadsTheFlag() {
        XCTAssertEqual(PowerParsers.sleepDisabled(pmsetG: " SleepDisabled        1"), true)
        XCTAssertEqual(PowerParsers.sleepDisabled(pmsetG: " SleepDisabled        0"), false)
    }

    /// `pmset` failing usually means empty stdout, which must not read as "off" —
    /// that would claim the Mac is free to sleep on the strength of no data.
    func testStrictSleepDisabledIsUnknownWhenOutputIsEmpty() {
        XCTAssertNil(PowerParsers.sleepDisabled(pmsetG: ""))
    }

    func testStrictSleepDisabledIsUnknownWhenKeyIsMissing() {
        XCTAssertNil(PowerParsers.sleepDisabled(pmsetG: "Currently in use:\n standby 1"))
    }

    func testStrictSleepDisabledIsUnknownWhenValueIsMalformed() {
        XCTAssertNil(PowerParsers.sleepDisabled(pmsetG: " SleepDisabled        yes"))
        XCTAssertNil(PowerParsers.sleepDisabled(pmsetG: " SleepDisabled"))
        XCTAssertNil(PowerParsers.sleepDisabled(pmsetG: " SleepDisabled        "))
    }

    /// Truncated output — the process died mid-write — states nothing.
    func testStrictSleepDisabledIsUnknownWhenOutputIsTruncated() {
        XCTAssertNil(PowerParsers.sleepDisabled(pmsetG: "System-wide power settings:\n Sleep"))
    }

    /// The lenient wrapper still exists for the helper's `Bool`-only XPC reply,
    /// and must keep collapsing unknown to false rather than changing behaviour.
    func testLenientFormCollapsesUnknownToFalse() {
        XCTAssertFalse(PowerParsers.isSleepDisabled(pmsetG: ""))
        XCTAssertFalse(PowerParsers.isSleepDisabled(pmsetG: " SleepDisabled        yes"))
        XCTAssertTrue(PowerParsers.isSleepDisabled(pmsetG: " SleepDisabled        1"))
    }

    // MARK: BatteryParsers

    func testBatteryOnAC() {
        let out = "Now drawing from 'AC Power'\n -InternalBattery-0 (id=123)\t87%; charging; 0:42 remaining present: true"
        let info = BatteryParsers.parse(pmsetBatt: out)
        XCTAssertEqual(info.percent, 87)
        XCTAssertTrue(info.onAC)
        XCTAssertEqual(info.source, "AC")
    }

    func testBatteryOnBattery() {
        let out = "Now drawing from 'Battery Power'\n -InternalBattery-0 (id=123)\t19%; discharging; 1:05 remaining present: true"
        let info = BatteryParsers.parse(pmsetBatt: out)
        XCTAssertEqual(info.percent, 19)
        XCTAssertFalse(info.onAC)
        XCTAssertEqual(info.source, "Battery")
    }

    // MARK: Watchdog

    func testWatchdogFiresAfterTimeout() {
        let last = Date(timeIntervalSince1970: 1000)
        let now = Date(timeIntervalSince1970: 1100) // 100s later
        XCTAssertTrue(Watchdog.shouldAutoRestore(lastHeartbeat: last, now: now, timeout: 90))
    }

    func testWatchdogQuietWithinTimeout() {
        let last = Date(timeIntervalSince1970: 1000)
        let now = Date(timeIntervalSince1970: 1060) // 60s later
        XCTAssertFalse(Watchdog.shouldAutoRestore(lastHeartbeat: last, now: now, timeout: 90))
    }

    // MARK: SafetyPolicy

    func testSafetyDisablesOnLowBattery() {
        let info = BatteryInfo(percent: 15, onAC: false)
        XCTAssertTrue(SafetyPolicy.shouldDisableForBattery(info, threshold: 20))
    }

    func testSafetyAllowsOnAC() {
        let info = BatteryInfo(percent: 5, onAC: true)
        XCTAssertFalse(SafetyPolicy.shouldDisableForBattery(info, threshold: 20))
    }

    func testSafetyAllowsAboveThreshold() {
        let info = BatteryInfo(percent: 80, onAC: false)
        XCTAssertFalse(SafetyPolicy.shouldDisableForBattery(info, threshold: 20))
    }

    // MARK: AutoOff

    func testAutoOffDeadlineIsStartPlusMinutes() {
        let start = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(AutoOff.deadline(from: start, minutes: 30),
                       Date(timeIntervalSince1970: 1000 + 1800))
    }

    func testAutoOffRemainingClampsToZero() {
        let deadline = Date(timeIntervalSince1970: 1000)
        let now = Date(timeIntervalSince1970: 1100) // already past
        XCTAssertEqual(AutoOff.remaining(deadline: deadline, now: now), 0)
    }

    func testAutoOffRemainingCountsDown() {
        let deadline = Date(timeIntervalSince1970: 1100)
        let now = Date(timeIntervalSince1970: 1040)
        XCTAssertEqual(AutoOff.remaining(deadline: deadline, now: now), 60)
    }

    func testAutoOffExpiry() {
        let deadline = Date(timeIntervalSince1970: 1000)
        XCTAssertTrue(AutoOff.isExpired(deadline: deadline, now: deadline))
        XCTAssertTrue(AutoOff.isExpired(deadline: deadline, now: Date(timeIntervalSince1970: 1001)))
        XCTAssertFalse(AutoOff.isExpired(deadline: deadline, now: Date(timeIntervalSince1970: 999)))
    }

    func testAutoOffCountdownFormatting() {
        XCTAssertEqual(AutoOff.formatCountdown(30), "0:30")
        XCTAssertEqual(AutoOff.formatCountdown(582), "9:42")
        XCTAssertEqual(AutoOff.formatCountdown(3909), "1:05:09")
        XCTAssertEqual(AutoOff.formatCountdown(0), "0:00")
    }

    // MARK: AutoOff.request — "keep awake for N minutes" as one gesture

    /// The point of the change: asking for fifteen minutes of keep-awake turns
    /// keep-awake on. Before, it only armed a countdown for a switch the user
    /// still had to find and flip themselves.
    func testRequestEnablesKeepAwakeWhenNoTierIsActive() {
        XCTAssertEqual(AutoOff.request(minutes: 15, anyTierActive: false, autoModeOn: false),
                       .enableThenArmTimer(minutes: 15))
    }

    /// Any tier counts: the gesture extends whatever is running, not just the
    /// lid tier the old `isEnabled` flag described.
    func testRequestJustArmsTimerWhenAnyTierIsActive() {
        XCTAssertEqual(AutoOff.request(minutes: 30, anyTierActive: true, autoModeOn: false),
                       .armTimer(minutes: 30))
    }

    /// "No limit" removes the countdown. It must not also turn every tier off —
    /// that's a different request, and the mode picker already expresses it.
    func testRequestForNoLimitCancelsTimerWithoutDisabling() {
        XCTAssertEqual(AutoOff.request(minutes: 0, anyTierActive: true, autoModeOn: false),
                       .cancelTimer)
        XCTAssertEqual(AutoOff.request(minutes: 0, anyTierActive: false, autoModeOn: false),
                       .cancelTimer)
    }

    /// Auto mode owns activation; a countdown there would disarm the feature
    /// behind its back. Nothing happens, including no persisted change.
    func testRequestIsIgnoredInAutoModeWhateverElseIsTrue() {
        for minutes in [0, 15, 240] {
            for active in [true, false] {
                XCTAssertEqual(AutoOff.request(minutes: minutes, anyTierActive: active, autoModeOn: true),
                               .ignoredInAutoMode,
                               "minutes=\(minutes) active=\(active)")
            }
        }
    }

    func testRequestCoversEveryPreset() {
        for minutes in AutoOff.presetMinutes {
            XCTAssertEqual(AutoOff.request(minutes: minutes, anyTierActive: false, autoModeOn: false),
                           .enableThenArmTimer(minutes: minutes))
        }
    }

    // MARK: AutoOff expiry — every tier releases at once (SPEC §7)

    /// The countdown lands on `off` from wherever it was running — never
    /// stepping down through lower tiers. Pins the behaviour the spec calls
    /// "predictable": no intermediate state between the running tier and off.
    func testExpiryReleasesEveryTierAtOnce() {
        for mode in KeepAwakeMode.allCases {
            XCTAssertEqual(AutoOff.modeOnExpiry(from: mode), .off,
                           "expiry must go straight to off from \(mode)")
        }
    }

    func testDurationLabelNamesTheNoLimitCase() {
        XCTAssertEqual(AutoOff.durationLabel(minutes: 0), "No limit")
        XCTAssertEqual(AutoOff.durationLabel(minutes: 15), "15 min")
        XCTAssertEqual(AutoOff.durationLabel(minutes: 60), "1 hour")
    }

    func testAutoOffOptionLabels() {
        XCTAssertEqual(AutoOff.optionLabel(minutes: 15), "15 min")
        XCTAssertEqual(AutoOff.optionLabel(minutes: 30), "30 min")
        XCTAssertEqual(AutoOff.optionLabel(minutes: 60), "1 hour")
        XCTAssertEqual(AutoOff.optionLabel(minutes: 120), "2 hours")
        XCTAssertEqual(AutoOff.optionLabel(minutes: 240), "4 hours")
    }

    // MARK: SettingsStore onboarding flag

    func testOnboardingDefaultsToIncomplete() {
        let defaults = UserDefaults(suiteName: "lidless.test.onboarding.default")!
        defaults.removePersistentDomain(forName: "lidless.test.onboarding.default")
        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.loadOnboardingComplete())
    }

    func testOnboardingCompletePersists() {
        let defaults = UserDefaults(suiteName: "lidless.test.onboarding.persist")!
        defaults.removePersistentDomain(forName: "lidless.test.onboarding.persist")
        let store = SettingsStore(defaults: defaults)
        store.saveOnboardingComplete(true)
        XCTAssertTrue(SettingsStore(defaults: defaults).loadOnboardingComplete())
    }

    // MARK: SettingsStore autoLockOnTimerStart

    /// An install from before the setting existed has `settingsSeeded` set but
    /// no `autoLockOnTimerStart` key; loading must fall back to off (the lock
    /// is opt-in), never to a zero-initialised `true`-adjacent default.
    func testAutoLockSettingFallsBackToFalseForOldInstalls() {
        let suite = "lidless.test.autolck.old"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(true, forKey: "settingsSeeded")   // seeded before the key existed
        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.load().autoLockOnTimerStart)
    }

    func testAutoLockSettingRoundTrips() {
        let suite = "lidless.test.autolck.roundtrip"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        var settings = SafetySettings.default
        settings.autoLockOnTimerStart = true
        SettingsStore(defaults: defaults).save(settings)
        XCTAssertTrue(SettingsStore(defaults: defaults).load().autoLockOnTimerStart)
        XCTAssertEqual(SettingsStore(defaults: defaults).load(), settings)
    }
}
