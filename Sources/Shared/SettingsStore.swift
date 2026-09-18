import Foundation

/// Persists SafetySettings in UserDefaults. Returns `.default` until the user
/// has saved at least once (so first launch uses sane defaults, not zeros).
public struct SettingsStore {
    private let defaults: UserDefaults

    private enum Key {
        static let lowBattery   = "lowBatteryThreshold"
        static let onlyCharging = "onlyWhileCharging"
        static let pauseThermal = "pauseOnHighThermal"
        static let thermalPolicy = "thermalPolicy"
        static let restoreLid  = "restoreLidTierOnLaunch"
        static let autoEnable   = "autoEnableWhenCharging"
        static let autoLock     = "autoLockOnTimerStart"
        static let armed        = "keepAwakeArmed"
        static let seeded       = "settingsSeeded"
        static let autoOff      = "autoOffMinutes"
        static let onboarded    = "onboardingComplete"
        static let resumeOnboarding = "resumeOnboarding"
        static let helperBuild  = "lastRegisteredHelperBuild"
        static let licenseKey   = "LicenseKey"
        static let licensedEmail = "LicensedEmail"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> SafetySettings {
        guard defaults.bool(forKey: Key.seeded) else { return .default }
        // `bool(forKey:)` is false when the key is absent, so an install from
        // before `autoLockOnTimerStart` existed falls back to off on its own.
        // Thermal policy: read the new enum key; fall back to a one-shot
        // migration from the old boolean (absent → default). The old key is
        // left in place and simply stops being consulted once the new one
        // is written by the next save.
        let thermal: ThermalPolicy
        if let raw = defaults.string(forKey: Key.thermalPolicy), let p = ThermalPolicy(rawValue: raw) {
            thermal = p
        } else if defaults.object(forKey: Key.pauseThermal) != nil {
            thermal = defaults.bool(forKey: Key.pauseThermal) ? .pause : .ignore
        } else {
            thermal = .pause
        }
        return SafetySettings(
            lowBatteryThreshold: defaults.integer(forKey: Key.lowBattery),
            onlyWhileCharging: defaults.bool(forKey: Key.onlyCharging),
            thermalPolicy: thermal,
            autoEnableWhenCharging: defaults.bool(forKey: Key.autoEnable),
            autoLockOnTimerStart: defaults.bool(forKey: Key.autoLock),
            restoreLidTierOnLaunch: defaults.bool(forKey: Key.restoreLid)
        )
    }

    public func save(_ settings: SafetySettings) {
        defaults.set(settings.lowBatteryThreshold, forKey: Key.lowBattery)
        defaults.set(settings.onlyWhileCharging, forKey: Key.onlyCharging)
        defaults.set(settings.thermalPolicy.rawValue, forKey: Key.thermalPolicy)
        defaults.set(settings.restoreLidTierOnLaunch, forKey: Key.restoreLid)
        defaults.set(settings.autoEnableWhenCharging, forKey: Key.autoEnable)
        defaults.set(settings.autoLockOnTimerStart, forKey: Key.autoLock)
        defaults.set(true, forKey: Key.seeded)
    }

    /// The master-toggle intent in auto mode: whether the user wants keep-awake
    /// armed (the live state is then gated by power + safety). Defaults to false.
    public func loadArmed() -> Bool {
        defaults.bool(forKey: Key.armed)
    }

    public func saveArmed(_ armed: Bool) {
        defaults.set(armed, forKey: Key.armed)
    }

    /// Auto-off duration in minutes (`0` = no auto-off). Defaults to 0.
    public func loadAutoOffMinutes() -> Int {
        defaults.integer(forKey: Key.autoOff)
    }

    public func saveAutoOffMinutes(_ minutes: Int) {
        defaults.set(minutes, forKey: Key.autoOff)
    }

    /// Whether the user has been through first-run onboarding. Defaults to false.
    public func loadOnboardingComplete() -> Bool {
        defaults.bool(forKey: Key.onboarded)
    }

    public func saveOnboardingComplete(_ complete: Bool) {
        defaults.set(complete, forKey: Key.onboarded)
    }

    /// Whether onboarding should be re-shown on the next launch — set when the app
    /// relaunches itself mid-onboarding (after the helper is enabled) so the flow
    /// resumes instead of being lost. Defaults to false.
    public func loadResumeOnboarding() -> Bool {
        defaults.bool(forKey: Key.resumeOnboarding)
    }

    public func saveResumeOnboarding(_ resume: Bool) {
        defaults.set(resume, forKey: Key.resumeOnboarding)
    }

    /// The app build (`CFBundleVersion`) for which the privileged helper was last
    /// (re-)registered. Used to refresh the launchd registration after an update,
    /// so the daemon keeps launching with the new binary's requirement. Empty
    /// until the first registration.
    public func loadLastHelperBuild() -> String {
        defaults.string(forKey: Key.helperBuild) ?? ""
    }

    public func saveLastHelperBuild(_ build: String) {
        defaults.set(build, forKey: Key.helperBuild)
    }

    // MARK: License cache

    /// The pasted Gumroad license key, persisted only after a verified
    /// activation; nil until then and after a revoked verdict.
    public func loadLicenseKey() -> String? {
        defaults.string(forKey: Key.licenseKey)
    }

    public func saveLicenseKey(_ key: String) {
        defaults.set(key, forKey: Key.licenseKey)
    }

    /// Buyer email shown on the About row; only meaningful alongside a key.
    public func loadLicensedEmail() -> String? {
        defaults.string(forKey: Key.licensedEmail)
    }

    public func saveLicensedEmail(_ email: String) {
        defaults.set(email, forKey: Key.licensedEmail)
    }

    /// Clears both halves of the license cache together — leaving a dead key
    /// behind would re-verify it against Gumroad on every launch.
    public func removeLicense() {
        defaults.removeObject(forKey: Key.licenseKey)
        defaults.removeObject(forKey: Key.licensedEmail)
    }
}
