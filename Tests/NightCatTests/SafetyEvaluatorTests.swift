import XCTest

final class SafetyEvaluatorTests: XCTestCase {

    private let defaults = SafetySettings.default

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
        XCTAssertEqual(SafetyReason.highThermal.localizedMessage(), "已自动暂停：Mac 正在过热。")
        XCTAssertEqual(SafetyReason.notCharging.localizedMessage(), "已自动暂停：未连接充电器。")
        XCTAssertEqual(SafetyReason.lowBattery(12).localizedMessage(), "已自动暂停：使用电池，电量 12%。")
    }

    // MARK: Low-battery cutoff = "Never" (0)

    func testThresholdZeroNeverTriggersLowBattery() {
        var s = defaults
        s.lowBatteryThreshold = 0
        let info = BatteryInfo(percent: 1, onAC: false)
        XCTAssertNil(SafetyEvaluator.reasonToDisable(battery: info, thermalSerious: false, settings: s))
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
        store.save(s)
        XCTAssertEqual(store.load(), s)
        d.removePersistentDomain(forName: suite)
    }
}
