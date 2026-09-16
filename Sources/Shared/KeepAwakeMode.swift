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

    /// Segment label (English; localized with the rest of the UI later).
    public var label: String {
        switch self {
        case .off:         return "Off"
        case .screen:      return "Screen"
        case .preventIdle: return "Idle"
        case .lidClosed:   return "Lid"
        }
    }
}
