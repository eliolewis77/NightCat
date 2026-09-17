import XCTest

final class SafetyEvaluatorTests: XCTestCase {

    private let defaults = SafetySettings.default

    /// Defaults with auto-enable mode switched on.
    private var auto: SafetySettings {
        var s = SafetySettings.default
        s.autoEnableWhenCharging = true
        return s
    }

    func testSafeWhenChargingAndCool() {
        let info = BatteryInfo(percent: 50, onAC: true)
        XCTAssertNil(SafetyEvaluator.reasonToDisable(battery: info, thermalSerious: false, settings: defaults))
    }

    func testThermalTakesPriority() {
        let info = BatteryInfo(percent: 100, onAC: true)
        XCTAssertEqual(
            SafetyEvaluator.reasonToDisable(battery: info, thermalSerious: true, settings: defaults),
            .highThermal
        )
    }

    func testThermalIgnoredWhenSettingOff() {
        var s = defaults
        s.thermalPolicy = .ignore
        let info = BatteryInfo(percent: 100, onAC: true)
        XCTAssertNil(SafetyEvaluator.reasonToDisable(battery: info, thermalSerious: true, settings: s))
    }

    func testOnlyWhileChargingTriggersOnBattery() {
        var s = defaults
        s.onlyWhileCharging = true
        let info = BatteryInfo(percent: 90, onAC: false)
        XCTAssertEqual(
            SafetyEvaluator.reasonToDisable(battery: info, thermalSerious: false, settings: s),
            .notCharging
        )
    }

    func testLowBatteryTriggers() {
        let info = BatteryInfo(percent: 15, onAC: false)
        XCTAssertEqual(
            SafetyEvaluator.reasonToDisable(battery: info, thermalSerious: false, settings: defaults),
            .lowBattery(15)
        )
    }

    func testChargingOverridesLowBattery() {
        let info = BatteryInfo(percent: 5, onAC: true)
        XCTAssertNil(SafetyEvaluator.reasonToDisable(battery: info, thermalSerious: false, settings: defaults))
    }

    func testReasonMessages() {
        XCTAssertEqual(SafetyReason.highThermal.message, "已自动暂停：Mac 正在过热。")
        XCTAssertEqual(SafetyReason.notCharging.message, "已自动暂停：未连接充电器。")
        XCTAssertEqual(SafetyReason.lowBattery(12).message, "已自动暂停：使用电池，电量 12%。")
        XCTAssertEqual(SafetyReason.notOnPower.message, "已自动暂停：未连接电源。")
    }

    func testNotOnPowerPhrasing() {
        XCTAssertEqual(SafetyReason.notOnPower.blockedMessage,
                       "请连接电源后再保持唤醒。")
        XCTAssertEqual(SafetyReason.notOnPower.checkLabel, "未连接电源")
    }

    // MARK: Low-battery cutoff = "Never" (0)

    func testThresholdZeroNeverTriggersLowBattery() {
        var s = defaults
        s.lowBatteryThreshold = 0
        let info = BatteryInfo(percent: 1, onAC: false)
        XCTAssertNil(SafetyEvaluator.reasonToDisable(battery: info, thermalSerious: false, settings: s))
    }

    // MARK: AutoEnablePolicy

    func testAutoEnableActivatesOnPowerWhenSafe() {
        XCTAssertTrue(AutoEnablePolicy.canActivate(
            battery: BatteryInfo(percent: 5, onAC: true), thermalSerious: false, settings: defaults))
    }

    func testAutoEnableNeverActivatesOnBattery() {
        // Even at full charge, auto mode requires external power.
        XCTAssertFalse(AutoEnablePolicy.canActivate(
            battery: BatteryInfo(percent: 100, onAC: false), thermalSerious: false, settings: defaults))
    }

    func testAutoEnableBlockedByThermalOnPower() {
        XCTAssertFalse(AutoEnablePolicy.canActivate(
            battery: BatteryInfo(percent: 100, onAC: true), thermalSerious: true, settings: defaults))
    }

    func testOnlyWhileChargingIsMootOnPower() {
        var s = defaults
        s.onlyWhileCharging = true
        XCTAssertTrue(AutoEnablePolicy.canActivate(
            battery: BatteryInfo(percent: 50, onAC: true), thermalSerious: false, settings: s))
    }

    // MARK: AutoEnablePolicy.target — the state reconcile() acts on

    /// `auto` mode off: never our call to make, whatever else is true.
    func testTargetIsNilWhenAutoModeOff() {
        XCTAssertNil(AutoEnablePolicy.target(
            armed: true, currentlyEnabled: false,
            battery: BatteryInfo(percent: 90, onAC: true),
            thermalSerious: false, settings: defaults))
    }

    func testTargetTurnsOnWhenArmedAndPluggedIn() {
        XCTAssertEqual(AutoEnablePolicy.target(
            armed: true, currentlyEnabled: false,
            battery: BatteryInfo(percent: 90, onAC: true),
            thermalSerious: false, settings: auto), true)
    }

    func testTargetTurnsOffWhenUnplugged() {
        XCTAssertEqual(AutoEnablePolicy.target(
            armed: true, currentlyEnabled: true,
            battery: BatteryInfo(percent: 90, onAC: false),
            thermalSerious: false, settings: auto), false)
    }

    func testTargetTurnsOffWhenDisarmed() {
        XCTAssertEqual(AutoEnablePolicy.target(
            armed: false, currentlyEnabled: true,
            battery: BatteryInfo(percent: 90, onAC: true),
            thermalSerious: false, settings: auto), false)
    }

    func testTargetTurnsOffWhenRunningHot() {
        XCTAssertEqual(AutoEnablePolicy.target(
            armed: true, currentlyEnabled: true,
            battery: BatteryInfo(percent: 90, onAC: true),
            thermalSerious: true, settings: auto), false)
    }

    /// The poll runs every 30s; a target equal to the live state must report
    /// "nothing to do" so we never rewrite the system flag on an idle tick.
    func testTargetIsNilWhenAlreadyCorrect() {
        XCTAssertNil(AutoEnablePolicy.target(
            armed: true, currentlyEnabled: true,
            battery: BatteryInfo(percent: 90, onAC: true),
            thermalSerious: false, settings: auto))
        XCTAssertNil(AutoEnablePolicy.target(
            armed: false, currentlyEnabled: false,
            battery: BatteryInfo(percent: 90, onAC: true),
            thermalSerious: false, settings: auto))
        XCTAssertNil(AutoEnablePolicy.target(
            armed: true, currentlyEnabled: false,
            battery: BatteryInfo(percent: 90, onAC: false),
            thermalSerious: false, settings: auto))
    }

    /// Armed and plugged in, but the cutoff can't fire on power — so it stays on.
    func testTargetIgnoresCutoffWhileOnPower() {
        var s = auto
        s.lowBatteryThreshold = 95
        XCTAssertEqual(AutoEnablePolicy.target(
            armed: true, currentlyEnabled: false,
            battery: BatteryInfo(percent: 10, onAC: true),
            thermalSerious: false, settings: s), true)
    }

    // MARK: allUnmetReasons

    func testAllUnmetReasonsEmptyWhenSafeOnPower() {
        let info = BatteryInfo(percent: 80, onAC: true)
        XCTAssertTrue(SafetyEvaluator.allUnmetReasons(
            battery: info, thermalSerious: false, settings: defaults, requirePower: true).isEmpty)
    }

    func testAllUnmetReasonsListsPowerAndBatteryOffPower() {
        var s = defaults
        s.lowBatteryThreshold = 50
        let info = BatteryInfo(percent: 34, onAC: false)
        let reasons = SafetyEvaluator.allUnmetReasons(
            battery: info, thermalSerious: false, settings: s, requirePower: true)
        XCTAssertEqual(reasons, [.notOnPower, .lowBattery(34)])
    }

    func testAllUnmetReasonsDedupesPowerBullet() {
        // With requirePower and onlyWhileCharging both implying power, only the
        // power bullet appears — never both it and .notCharging.
        var s = defaults
        s.onlyWhileCharging = true
        s.lowBatteryThreshold = 0
        let info = BatteryInfo(percent: 90, onAC: false)
        let reasons = SafetyEvaluator.allUnmetReasons(
            battery: info, thermalSerious: false, settings: s, requirePower: true)
        XCTAssertEqual(reasons, [.notOnPower])
    }

    /// `reasonToDisable` and `allUnmetReasons` share one low-battery predicate;
    /// this pins them together across the whole threshold boundary so a future
    /// edit to one can't quietly diverge from the other.
    func testLowBatteryAgreesAcrossBothEvaluators() {
        var s = defaults
        s.lowBatteryThreshold = 20
        for percent in [0, 1, 19, 20, 21, 100] {
            let info = BatteryInfo(percent: percent, onAC: false)
            let single = SafetyEvaluator.reasonToDisable(
                battery: info, thermalSerious: false, settings: s) == .lowBattery(percent)
            let listed = SafetyEvaluator.allUnmetReasons(
                battery: info, thermalSerious: false, settings: s,
                requirePower: false).contains(.lowBattery(percent))
            XCTAssertEqual(single, listed, "disagreement at \(percent)%")
        }
    }

    func testAllUnmetReasonsIncludesThermal() {
        let info = BatteryInfo(percent: 90, onAC: false)
        let reasons = SafetyEvaluator.allUnmetReasons(
            battery: info, thermalSerious: true, settings: defaults, requirePower: true)
        XCTAssertEqual(reasons.first, .highThermal)
        XCTAssertTrue(reasons.contains(.notOnPower))
    }

    // MARK: SettingsStore

    func testSettingsStoreDefaultsWhenUnseeded() {
        let suite = "test.lidless.unseeded"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        XCTAssertEqual(SettingsStore(defaults: d).load(), .default)
    }

    func testSettingsStoreRoundTrip() {
        let suite = "test.lidless.roundtrip"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        let store = SettingsStore(defaults: d)
        var s = SafetySettings.default
        s.onlyWhileCharging = true
        s.thermalPolicy = .ignore
        s.lowBatteryThreshold = 35
        s.autoEnableWhenCharging = true
        store.save(s)
        XCTAssertEqual(store.load(), s)
        d.removePersistentDomain(forName: suite)
    }

    func testArmedRoundTrip() {
        let suite = "test.lidless.armed"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        let store = SettingsStore(defaults: d)
        XCTAssertFalse(store.loadArmed())
        store.saveArmed(true)
        XCTAssertTrue(store.loadArmed())
        d.removePersistentDomain(forName: suite)
    }
}
