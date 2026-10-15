import Foundation

/// What happens when the Mac's thermal state reaches serious. Migrated from
/// the former boolean: on → `.pause`, off → `.ignore`.
public enum ThermalPolicy: String, Codable, CaseIterable {
    /// Drop back to the Off tier (the historical behavior).
    case pause
    /// One system notification; the tier keeps running — for users who treat
    /// keep-awake as their remote-reachability lifeline.
    case notify
    /// Nothing at all.
    case ignore
}

/// User-tunable safety preferences for keep-awake.
public struct SafetySettings: Equatable {
    public var lowBatteryThreshold: Int
    public var onlyWhileCharging: Bool
    public var thermalPolicy: ThermalPolicy
    /// When true, the app turns the Lid tier on by itself at launch — so a Mac
    /// that rebooted with the lid closed (auto-update, remote restart) is
    /// reachable again instead of sitting on Off until someone opens the lid.
    /// Opt-in: the default keeps the historical "no tier survives a relaunch"
    /// guarantee. The helper watchdog still covers crashes.
    public var restoreLidTierOnLaunch: Bool
    /// Network keep-alive: an always-running `ping` against the default
    /// gateway, so idle-throttling APs and NIC power save never drop the
    /// link under an unattended Mac. Fully independent of the tiers —
    /// reachability matters in every state the machine can be in.
    public var networkKeepAliveEnabled: Bool
    /// Keep-alive interval in minutes; domain and default live in
    /// `NetworkKeepAlivePolicy`.
    public var networkKeepAliveIntervalMinutes: Int

    public static let `default` = SafetySettings(
        lowBatteryThreshold: 20,
        onlyWhileCharging: false,
        thermalPolicy: .pause,
        restoreLidTierOnLaunch: false
    )

    public init(lowBatteryThreshold: Int,
                onlyWhileCharging: Bool,
                thermalPolicy: ThermalPolicy,
                restoreLidTierOnLaunch: Bool = false,
                networkKeepAliveEnabled: Bool = false,
                networkKeepAliveIntervalMinutes: Int = NetworkKeepAlivePolicy.defaultMinutes) {
        self.lowBatteryThreshold = lowBatteryThreshold
        self.onlyWhileCharging = onlyWhileCharging
        self.thermalPolicy = thermalPolicy
        self.restoreLidTierOnLaunch = restoreLidTierOnLaunch
        self.networkKeepAliveEnabled = networkKeepAliveEnabled
        self.networkKeepAliveIntervalMinutes = networkKeepAliveIntervalMinutes
    }
}

/// Why keep-awake was (or should be) auto-disabled.
public enum SafetyReason: Equatable {
    case highThermal
    case notCharging
    case lowBattery(Int)

    public var message: String {
        switch self {
        case .highThermal:
            return NSLocalizedString("已自动暂停：Mac 正在过热。", comment: "safety pause")
        case .notCharging:
            return NSLocalizedString("已自动暂停：未连接充电器。", comment: "safety pause")
        case .lowBattery:
            return NSLocalizedString("已自动暂停：使用电池，电量 %lld%%。", comment: "safety pause; percent")
        }
    }

    /// Phrasing for when the user *tries to turn keep-awake on* but the policy
    /// won't allow it (vs. `message`, which describes a background auto-pause).
    public var blockedMessage: String {
        switch self {
        case .highThermal:
            return NSLocalizedString("Mac 正在过热，暂时无法保持唤醒，待冷却后再试。", comment: "blocked reason")
        case .notCharging:
            return NSLocalizedString("「仅插电时保持」已开启，请连接电源后再保持唤醒。", comment: "blocked reason")
        case .lowBattery:
            return NSLocalizedString("当前电量 %lld%%，低于低电量阈值，请先充电。", comment: "blocked reason; percent")
        }
    }

    /// The formatted message with the percent argument filled in.
    public func localizedMessage() -> String {
        switch self {
        case .highThermal, .notCharging:
            return String(format: message)
        case .lowBattery(let p):
            return String(format: message, p)
        }
    }

    /// Same for the blocked phrasing.
    public func localizedBlockedMessage() -> String {
        switch self {
        case .highThermal, .notCharging:
            return String(format: blockedMessage)
        case .lowBattery(let p):
            return String(format: blockedMessage, p)
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
        // Downgrading mid-run happens under `.pause` only: `.notify` keeps the
        // tier alive (the hot state is surfaced by a one-shot notification in
        // the app layer), and `.ignore` was the old `pauseOnHighThermal = false`.
        if settings.thermalPolicy == .pause && thermalSerious {
            return .highThermal
        }
        if settings.onlyWhileCharging && !battery.onAC {
            return .notCharging
        }
        return lowBatteryReason(battery: battery, settings: settings)
    }

    /// The reason an *activation* attempt should be refused. Heat blocks
    /// starting under `.pause` **and** `.notify` — notify keeps a running tier
    /// alive but doesn't bless starting a new hold on a hot Mac. `.ignore`
    /// disables the thermal gate entirely.
    public static func reasonToBlockActivation(battery: BatteryInfo,
                                               thermalSerious: Bool,
                                               settings: SafetySettings) -> SafetyReason? {
        if settings.thermalPolicy != .ignore && thermalSerious {
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
}
