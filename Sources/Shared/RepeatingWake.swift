import Foundation

/// The system-wide repeating wake event (`pmset repeat wake …`) that makes a
/// sleeping Mac wake up when a schedule window begins. Pure command
/// construction + pure decisions — no process calls — shared verbatim by the
/// helper (root XPC path), the app (osascript fallback), and the tests, so
/// both write paths produce byte-identical arguments.
///
/// `pmset repeat` allows exactly one set of repeating power events system-wide;
/// writing replaces whatever was there. Cancellation is all-or-nothing
/// (`pmset repeat cancel`).
public enum RepeatingWake {
    /// The helper version that first shipped `setRepeatingWake`. Helpers below
    /// it must never receive the new selector — `@objc` dispatch on a missing
    /// method crashes the daemon — so callers compare against this and fall
    /// back to the admin-prompt path instead.
    ///
    /// Distinct fact from `NightCatHelper.protocolVersion` (what the running
    /// daemon reports): this is the oldest version *this app binary* accepts.
    /// The two coincide today and must move together when a capability is
    /// added, but the minimum must never be derived from the protocol version —
    /// a future app that tolerates old helpers would otherwise reject them.
    public static let minimumHelperVersion = "0.2.0"

    /// Rejection text both write paths use for out-of-domain parameters, so
    /// the XPC refusal and the app-side refusal render identically through
    /// `定时唤醒设置失败：%@".
    public static let invalidArgumentsMessage = "invalid repeating wake arguments"

    /// Calendar weekday bitmask → pmset's weekday letters, in pmset's
    /// canonical order (`M T W R F S U`; R = Thursday, U = Sunday). Bit N-1 is
    /// weekday N (1 = Sunday … 7 = Saturday), same domain as
    /// `WeeklySchedule.weekdayMask`. nil when the mask is empty or carries
    /// bits outside the weekday domain.
    public static func weekdayLetters(weekdayMask: Int) -> String? {
        guard weekdayMask > 0,
              weekdayMask & ~WeeklySchedule.allWeekdaysMask == 0
        else { return nil }
        // One ordered table in pmset's canonical order — Sunday last — so the
        // ordering invariant is visible at a glance and there is nothing to
        // look up (and nothing to force-unwrap).
        let table: [(bit: Int, letter: String)] = [
            (1 << 1, "M"), (1 << 2, "T"), (1 << 3, "W"),
            (1 << 4, "R"), (1 << 5, "F"), (1 << 6, "S"),
            (1 << 0, "U"),
        ]
        return table.reduce(into: "") { result, entry in
            if weekdayMask & entry.bit != 0 { result += entry.letter }
        }
    }

    /// The pmset argv for this request. `enabled == false` always yields
    /// `["repeat", "cancel"]` — cancelling ignores the rule entirely, so
    /// callers can route a stale rule straight to the same path. A register
    /// with an empty mask or out-of-range minutes is not a command at all:
    /// nil means "refuse", which the helper treats as a rejected call.
    public static func pmsetArguments(weekdayMask: Int, minutes: Int, enabled: Bool) -> [String]? {
        guard enabled else { return ["repeat", "cancel"] }
        guard let letters = weekdayLetters(weekdayMask: weekdayMask),
              (0..<1440).contains(minutes)
        else { return nil }
        return ["repeat", "wake", letters,
                String(format: "%02d:%02d:00", minutes / 60, minutes % 60)]
    }

    /// The same request as an `osascript` shell script for the admin-prompt
    /// fallback path. Safe to interpolate unquoted: every component comes
    /// from a closed alphabet (fixed verbs, weekday letters, zero-padded
    /// digits), never from user strings.
    public static func shellScript(weekdayMask: Int, minutes: Int, enabled: Bool) -> String? {
        guard let args = pmsetArguments(weekdayMask: weekdayMask, minutes: minutes, enabled: enabled)
        else { return nil }
        return "do shell script \"/usr/bin/pmset \(args.joined(separator: " "))\" with administrator privileges"
    }

    /// Whether a helper reporting `version` understands `setRepeatingWake`.
    /// Dot components compare numerically with missing components read as 0
    /// (`"0.2"` == `"0.2.0"`); anything unparsable — empty, garbage — fails
    /// closed, because the cost of guessing wrong is a dead daemon.
    public static func isHelperSupported(version: String) -> Bool {
        guard let actual = components(of: version),
              let required = components(of: minimumHelperVersion)
        else { return false }
        for index in 0..<max(actual.count, required.count) {
            let a = index < actual.count ? actual[index] : 0
            let r = index < required.count ? required[index] : 0
            if a != r { return a > r }
        }
        return true
    }

    private static func components(of version: String) -> [Int]? {
        var parts: [Int] = []
        for token in version.split(separator: ".") {
            guard let n = Int(token) else { return nil }
            parts.append(n)
        }
        return parts.isEmpty ? nil : parts
    }

    /// What one sync pass should do to the system wake event. Persisted (via
    /// SettingsStore) as the app's belief of what the system currently holds —
    /// the cross-session anchor that keeps a schedule toggled off from leaving
    /// a stale event armed.
    public enum Decision: Equatable {
        /// Arm (or re-arm — pmset replaces) the wake event for this rule.
        case register(weekdayMask: Int, minutes: Int)
        /// Clear any repeating event: schedule off, suspended by auto mode,
        /// or a rule that can never fire.
        case cancel
    }

    /// The single decision point every sync site routes through. Auto mode
    /// suspends the schedule, so it also suspends the wake — waking the Mac
    /// for a tier that auto mode would then decide about is not this
    /// feature's call. An empty rule (no weekdays, or start == end) never
    /// fires, so its wake event must not linger.
    public static func decision(enabled: Bool,
                                autoModeOn: Bool,
                                schedule: WeeklySchedule?) -> Decision {
        guard enabled, !autoModeOn, let schedule, !schedule.isEmpty else { return .cancel }
        return .register(weekdayMask: schedule.weekdayMask, minutes: schedule.startMinute)
    }

    /// Whether `pmset -g sched` output shows our repeating wake event armed.
    ///
    /// Lenient on purpose: a repeating section that names a wake (or power-on)
    /// at all counts as armed — pmset's exact line format has shifted across
    /// macOS releases, and the question this answers is binary ("is something
    /// of ours still scheduled"), not a parse of its fields.
    public static func isArmed(inSchedOutput output: String) -> Bool {
        guard let repeatingRange = output.range(of: "Repeating power events",
                                                options: .caseInsensitive) else {
            return false
        }
        let repeatingTail = output[repeatingRange.lowerBound...]
        return repeatingTail.contains("wake at") || repeatingTail.contains("poweron at")
    }
}

/// Codable so the app can persist its believed wake state across launches
/// (SettingsStore stores it as a JSON blob).
extension RepeatingWake.Decision: Codable {}
