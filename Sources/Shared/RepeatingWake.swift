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
    public static let minimumHelperVersion = "0.2.0"

    /// Calendar weekday bitmask → pmset's weekday letters, in pmset's
    /// canonical order (`M T W R F S U`; R = Thursday, U = Sunday). Bit N-1 is
    /// weekday N (1 = Sunday … 7 = Saturday), same domain as
    /// `WeeklySchedule.weekdayMask`. nil when the mask is empty or carries
    /// bits outside the weekday domain.
    public static func weekdayLetters(weekdayMask: Int) -> String? {
        guard weekdayMask > 0,
              weekdayMask & ~WeeklySchedule.allWeekdaysMask == 0
        else { return nil }
        // Weekday value → letter; 2=Mon … 7=Sat, 1=Sun.
        let letterForWeekday = [2: "M", 3: "T", 4: "W", 5: "R", 6: "F", 7: "S"]
        var letters = ""
        for weekday in 2...7 where weekdayMask & WeeklySchedule.mask(forWeekday: weekday) != 0 {
            letters += letterForWeekday[weekday]!
        }
        if weekdayMask & WeeklySchedule.mask(forWeekday: 1) != 0 {
            letters += "U"
        }
        return letters
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

    /// What one sync pass should do to the system wake event.
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
}
