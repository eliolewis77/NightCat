import Foundation

/// The keep-awake tier, in increasing order of intrusion.
///
/// - `screen`: the display never sleeps — presentations, dashboards. The
///   system itself may still sleep.
/// - `preventIdle`: the system won't idle-sleep; the screen may turn off —
///   long downloads and builds.
/// - `lidClosed`: the Mac stays awake with the lid closed — unattended runs.
///   Writes the system-wide `disablesleep` flag through the privileged helper.
///
/// The first two run entirely in the app as a `caffeinate` subprocess, which
/// dies with the app — the tier can't outlive it. `lidClosed` is the one tier
/// that writes system state and outlives the app, which is why the rest of
/// NightCat exists to make sure it gets turned off again.
public enum KeepAwakeMode: Int, CaseIterable, Identifiable {
    case off = 0
    case screen = 1
    case preventIdle = 2
    case lidClosed = 3

    public var id: Int { rawValue }

    /// Arguments for the App-layer `caffeinate` process, or `nil` when this
    /// tier doesn't run one. `off` needs nothing; `lidClosed` writes the
    /// system flag instead — `disablesleep 1` already covers idle sleep, so
    /// stacking `caffeinate` on top would be redundant.
    public var caffeinateArguments: [String]? {
        switch self {
        case .off, .lidClosed: return nil
        case .screen:          return ["-d"]
        case .preventIdle:     return ["-i", "-m", "-s"]
        }
    }

    /// Whether the tier owns the privileged helper's `disablesleep` flag.
    public var usesHelper: Bool { self == .lidClosed }

    /// Segment label (the picker's short names). Localized: zh-Hans is the
    /// source language, English translations live in Localizable.xcstrings.
    public var label: String {
        switch self {
        case .off:         return NSLocalizedString("关闭", comment: "tier short name")
        case .screen:      return NSLocalizedString("常亮", comment: "tier short name")
        case .preventIdle: return NSLocalizedString("防空闲", comment: "tier short name")
        case .lidClosed:   return NSLocalizedString("合盖", comment: "tier short name")
        }
    }

    /// Full name for the status row (and any sentence naming the tier).
    public var displayName: String {
        switch self {
        case .off:         return NSLocalizedString("关闭", comment: "tier full name")
        case .screen:      return NSLocalizedString("屏幕常亮", comment: "tier full name")
        case .preventIdle: return NSLocalizedString("防空闲", comment: "tier full name")
        case .lidClosed:   return NSLocalizedString("合盖不睡", comment: "tier full name")
        }
    }

    /// The one-line meaning shown under the tier name (panel-mockup §2).
    public var explanation: String {
        switch self {
        case .off:         return NSLocalizedString("跟随 Mac 的正常睡眠设置", comment: "tier explanation")
        case .screen:      return NSLocalizedString("屏幕保持点亮 · 系统仍可睡眠", comment: "tier explanation")
        case .preventIdle: return NSLocalizedString("系统不因空闲睡眠 · 屏幕可熄灭", comment: "tier explanation")
        case .lidClosed:   return NSLocalizedString("合上盖子继续运行 · 需要特权 Helper", comment: "tier explanation")
        }
    }
}
