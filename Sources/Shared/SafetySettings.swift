import Foundation

/// User-tunable safety preferences for keep-awake.
public struct SafetySettings: Equatable {
    public var lowBatteryThreshold: Int
    public var onlyWhileCharging: Bool
    public var pauseOnHighThermal: Bool
    /// When true, keep-awake automatically (re-)activates while the Mac is on
    /// external power and every enabled safety check passes. See `AutoEnablePolicy`.
    public var autoEnableWhenCharging: Bool
    /// When true, a genuinely-armed auto-off timer also locks the current mode
    /// (SPEC §6's batch-run helper: a countdown running means something is
    /// mid-run, so pin the tier against stray clicks). The lock itself stays
    /// session-only — this only automates setting it.
    public var autoLockOnTimerStart: Bool

    public static let `default` = SafetySettings(
        lowBatteryThreshold: 20,
        onlyWhileCharging: false,
        pauseOnHighThermal: true,
        autoEnableWhenCharging: false,
        autoLockOnTimerStart: false
    )

    public init(lowBatteryThreshold: Int,
                onlyWhileCharging: Bool,
                pauseOnHighThermal: Bool,
                autoEnableWhenCharging: Bool = false,
                autoLockOnTimerStart: Bool = false) {
        self.lowBatteryThreshold = lowBatteryThreshold
        self.onlyWhileCharging = onlyWhileCharging
        self.pauseOnHighThermal = pauseOnHighThermal
        self.autoEnableWhenCharging = autoEnableWhenCharging
        self.autoLockOnTimerStart = autoLockOnTimerStart
    }
}

/// Why keep-awake was (or should be) auto-disabled.
public enum SafetyReason: Equatable {
    case highThermal
    case notCharging
    case lowBattery(Int)
    /// The Mac isn't on external power. Used by auto-enable mode, which requires
    /// external power regardless of the "Only while charging" preference.
    case notOnPower

    public var message: String {
        switch self {
        case .highThermal:        return "已自动暂停：Mac 正在过热。"
        case .notCharging:        return "已自动暂停：未连接充电器。"
        case .lowBattery(let p):  return "已自动暂停：使用电池，电量 \(p)%。"
        case .notOnPower:         return "已自动暂停：未连接电源。"
        }
    }

    /// Phrasing for when the user *tries to turn keep-awake on* but the policy
    /// won't allow it (vs. `message`, which describes a background auto-pause).
    public var blockedMessage: String {
        switch self {
        case .highThermal:        return "Mac 正在过热，保持唤醒已暂停，待冷却后可继续使用。"
        case .notCharging:        return "「仅插电时保持」已开启，请连接电源后再保持唤醒。"
        case .lowBattery(let p):  return "当前电量 \(p)%，低于低电量阈值，请先充电。"
        case .notOnPower:         return "请连接电源后再保持唤醒。"
        }
    }

    /// Short phrasing for the auto-mode warning bullet list (e.g. "Not connected
    /// to power"). Reflects the *current* unmet condition, not an auto-pause event.
    public var checkLabel: String {
        switch self {
        case .highThermal:        return "过热"
        case .notCharging:        return "未连接充电器"
        case .lowBattery(let p):  return "电量 \(p)% 已到低电量阈值"
        case .notOnPower:         return "未连接电源"
        }
    }
}

/// One sample of everything a safety decision reads from the world.
///
/// Exists so a decision and the write it authorises can be judged against the
/// same conditions. Sampling twice — once to decide, once to check on the way
/// out — puts a seam between them that the world can change across, and a write
/// refused at that seam is a write that never claimed a mutation, so it
/// supersedes nothing and leaves whatever it was correcting in force.
public struct SafetySnapshot: Equatable {
    public let battery: BatteryInfo
    public let thermalSerious: Bool

    public init(battery: BatteryInfo, thermalSerious: Bool) {
        self.battery = battery
        self.thermalSerious = thermalSerious
    }
}

/// Pure safety decision. No side effects, fully unit-testable.
public enum SafetyEvaluator {
    /// The reason keep-awake should be disabled given current conditions, or
    /// `nil` if it's safe to stay awake. Checked in priority order:
    /// thermal first (hardware protection), then charging policy, then battery.
    ///
    /// A `lowBatteryThreshold` of 0 means "Never" — the low-battery check is
    /// disabled entirely.
    public static func reasonToDisable(battery: BatteryInfo,
                                       thermalSerious: Bool,
                                       settings: SafetySettings) -> SafetyReason? {
        if settings.pauseOnHighThermal && thermalSerious {
            return .highThermal
        }
        if settings.onlyWhileCharging && !battery.onAC {
            return .notCharging
        }
        return lowBatteryReason(battery: battery, settings: settings)
    }

    /// The low-battery check, shared by `reasonToDisable` and `allUnmetReasons`
    /// so the two can't drift. Only fires off power, and a threshold of 0
    /// ("Never") disables it entirely.
    private static func lowBatteryReason(battery: BatteryInfo,
                                         settings: SafetySettings) -> SafetyReason? {
        guard settings.lowBatteryThreshold > 0,
              !battery.onAC,
              battery.percent <= settings.lowBatteryThreshold else { return nil }
        return .lowBattery(battery.percent)
    }

    /// Every currently-unmet check, for the auto-mode warning list — unlike
    /// `reasonToDisable`, which stops at the first. `requirePower` adds the
    /// external-power requirement that auto mode imposes on top of the user's
    /// enabled safety checks; when off power that power bullet subsumes the
    /// redundant "Only while charging" one so we never list both.
    public static func allUnmetReasons(battery: BatteryInfo,
                                       thermalSerious: Bool,
                                       settings: SafetySettings,
                                       requirePower: Bool) -> [SafetyReason] {
        var reasons: [SafetyReason] = []
        if settings.pauseOnHighThermal && thermalSerious {
            reasons.append(.highThermal)
        }
        if requirePower && !battery.onAC {
            reasons.append(.notOnPower)
        } else if settings.onlyWhileCharging && !battery.onAC {
            reasons.append(.notCharging)
        }
        if let lowBattery = lowBatteryReason(battery: battery, settings: settings) {
            reasons.append(lowBattery)
        }
        return reasons
    }
}

/// Pure decision for auto-enable mode ("Automatically enable when charging").
/// Keep-awake may activate only while on external power *and* every enabled
/// safety check passes. Requiring external power makes the low-battery check
/// moot (it only fires off power), matching "ignore the battery check on power".
public enum AutoEnablePolicy {
    public static func canActivate(battery: BatteryInfo,
                                   thermalSerious: Bool,
                                   settings: SafetySettings) -> Bool {
        guard battery.onAC else { return false }
        return SafetyEvaluator.reasonToDisable(battery: battery,
                                               thermalSerious: thermalSerious,
                                               settings: settings) == nil
    }

    /// The live keep-awake state auto mode wants, or `nil` when there's nothing
    /// to do — auto mode is off, or the state already matches. Returning `nil`
    /// for "already correct" keeps the caller from writing the system flag on
    /// every poll tick.
    ///
    /// `currentlyEnabled` must be the *effective* state — see `effectiveState`.
    /// Comparing against the shown state instead is how an intent expressed
    /// while a write is still travelling gets silently dropped.
    public static func target(armed: Bool,
                              currentlyEnabled: Bool,
                              battery: BatteryInfo,
                              thermalSerious: Bool,
                              settings: SafetySettings) -> Bool? {
        guard settings.autoEnableWhenCharging else { return nil }
        let shouldBeOn = armed && canActivate(battery: battery,
                                              thermalSerious: thermalSerious,
                                              settings: settings)
        return shouldBeOn == currentlyEnabled ? nil : shouldBeOn
    }

    /// Where keep-awake is *heading*: the target of a write still in flight, or
    /// the shown state when nothing is outstanding.
    ///
    /// Every decision has to be taken against this rather than against the shown
    /// state. A dispatched write hasn't moved `isEnabled` yet — that happens in
    /// its reply — so a user changing their mind mid-flight would otherwise be
    /// compared against a state the system has already left, conclude nothing
    /// needs doing, and let the earlier write land unopposed.
    public static func effectiveState(pendingTarget: Bool?, live: Bool) -> Bool {
        pendingTarget ?? live
    }

    /// Leaving auto mode while a write is still travelling: the state to settle
    /// on, which the caller must then actually write.
    ///
    /// Manual mode inherits where the system was heading, so the starting point
    /// is the outstanding target. But "on" is only honest while it's still
    /// allowed — conditions can have lapsed since that write went out — and
    /// settling on "off" is also what keeps the write unconditional. A write of
    /// `true` can be refused by the safety check before it claims a mutation,
    /// which would leave the superseded auto reply free to land after all; a
    /// write of `false` is never refused.
    public static func handoffToManual(pendingTarget: Bool,
                                       conditions: SafetySnapshot,
                                       settings: SafetySettings) -> Bool {
        guard pendingTarget else { return false }
        return writeIsPermitted(target: true, conditions: conditions, settings: settings)
    }

    /// Whether the safety check on the way out of `setEnabled` will let a write
    /// of `target` through, given the conditions it checks against.
    ///
    /// This mirrors that check exactly, so a caller can guarantee its write won't
    /// be refused by handing the same snapshot to both. Two properties follow,
    /// and the auto path depends on each:
    ///
    /// - A `false` target is never refused. That is what lets a corrective "off"
    ///   supersede a pending "on" under any conditions at all.
    /// - A `true` target decided from a snapshot is still permitted under that
    ///   same snapshot, by construction. Re-sampling instead would reopen the
    ///   seam this is here to close.
    public static func writeIsPermitted(target: Bool,
                                        conditions: SafetySnapshot,
                                        settings: SafetySettings) -> Bool {
        guard target else { return true }
        return SafetyEvaluator.reasonToDisable(battery: conditions.battery,
                                               thermalSerious: conditions.thermalSerious,
                                               settings: settings) == nil
    }
}
