import Foundation

/// A weekly repeating window: on the chosen weekdays, from `startMinute` to
/// `endMinute`. Pure data + pure date math — no AppKit, no state — so the
/// window semantics can be tested directly, the way `AutoOff` is.
///
/// The window belongs to its *start day*: a cross-midnight window (e.g.
/// 22:00–06:00 with Monday selected) runs from Monday 22:00 to Tuesday 06:00,
/// regardless of whether Tuesday is also selected. `startMinute == endMinute`
/// is a zero-length window that never fires.
public struct WeeklySchedule: Equatable, Codable {
    /// Weekday bit mask. Bit N-1 corresponds to `Calendar.Component.weekday`
    /// value N (1 = Sunday … 7 = Saturday), so Monday–Friday is `0b0111110`.
    public var weekdayMask: Int
    /// Window start, minutes since midnight (0..<1440).
    public var startMinute: Int
    /// Window end, minutes since midnight (0..<1440).
    public var endMinute: Int

    public static let `default` = WeeklySchedule(weekdayMask: 0b0111110,
                                                 startMinute: 9 * 60,
                                                 endMinute: 17 * 60)
    public static let allWeekdaysMask = 0b1111111

    public init(weekdayMask: Int, startMinute: Int, endMinute: Int) {
        self.weekdayMask = weekdayMask
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    /// Fields forced back into their legal domains. UserDefaults integers
    /// from absent or corrupt keys read as 0 — without this, a half-written
    /// rule would silently mean "Sunday only, 00:00–00:00".
    public var sanitized: WeeklySchedule {
        WeeklySchedule(weekdayMask: weekdayMask & Self.allWeekdaysMask,
                       startMinute: min(max(startMinute, 0), 1439),
                       endMinute: min(max(endMinute, 0), 1439))
    }

    public var crossesMidnight: Bool { startMinute > endMinute }
    /// Never fires: no days chosen, or a zero-length window.
    public var isEmpty: Bool { startMinute == endMinute || weekdayMask == 0 }

    /// Bit for a `Calendar` weekday value (1 = Sunday … 7 = Saturday).
    static func mask(forWeekday weekday: Int) -> Int {
        1 << (weekday - 1)
    }

    /// Whether `date` falls inside the window — a half-open interval
    /// `[start, end)`, so 17:00 sharp is already *outside* a 9:00–17:00
    /// window. The boundary has to land on exactly one side: "does this end
    /// now" and "does this begin now" must never both be true at 17:00.
    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard !isEmpty else { return false }
        let minute = Self.minute(of: date, calendar: calendar)
        if crossesMidnight {
            // Inside either the start day's evening half or the next day's
            // morning half. The morning half belongs to the previous day's
            // selection — the window belongs to its start day.
            let weekday = calendar.component(.weekday, from: date)
            let previous = calendar.date(byAdding: .day, value: -1, to: date)
                .map { calendar.component(.weekday, from: $0) } ?? 0
            return (weekdayMask & Self.mask(forWeekday: weekday) != 0 && minute >= startMinute)
                || (weekdayMask & Self.mask(forWeekday: previous) != 0 && minute < endMinute)
        }
        let weekday = calendar.component(.weekday, from: date)
        return weekdayMask & Self.mask(forWeekday: weekday) != 0
            && minute >= startMinute && minute < endMinute
    }

    /// The moment the window containing `date` began; nil when `date` is
    /// outside every window. For a cross-midnight morning tail this is the
    /// *previous* day's start — the instance identity the director uses to
    /// recognise "this window has already been handled".
    public func windowStart(containing date: Date, calendar: Calendar = .current) -> Date? {
        guard contains(date, calendar: calendar) else { return nil }
        let startDay = crossesMidnight && Self.minute(of: date, calendar: calendar) < endMinute
            ? calendar.date(byAdding: .day, value: -1, to: date) ?? date
            : date
        return calendar.date(bySettingHour: startMinute / 60,
                             minute: startMinute % 60,
                             second: 0,
                             of: startDay)
    }

    /// The next window start strictly after `date`, or nil when no weekday is
    /// selected. Looks at most ~8 days out, so DST shifts can't send the scan
    /// past a real occurrence.
    public func nextStart(after date: Date, calendar: Calendar = .current) -> Date? {
        guard !isEmpty else { return nil }
        let startOfToday = calendar.startOfDay(for: date)
        for offset in 0...8 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday),
                  let candidate = calendar.date(bySettingHour: startMinute / 60,
                                                minute: startMinute % 60,
                                                second: 0,
                                                of: day)
            else { continue }
            let weekday = calendar.component(.weekday, from: day)
            guard weekdayMask & Self.mask(forWeekday: weekday) != 0 else { continue }
            if candidate > date { return candidate }
        }
        return nil
    }

    /// `minutes` since midnight as a `Date` on today's date — the carrier the
    /// `DatePicker(.hourAndMinute)` bindings round-trip through.
    public static func date(fromMinute minutes: Int, calendar: Calendar = .current) -> Date {
        let clamped = min(max(minutes, 0), 1439)
        let start = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .minute, value: clamped, to: start) ?? start
    }

    /// Minutes since midnight of `date`'s hour and minute components.
    public static func minute(of date: Date, calendar: Calendar = .current) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }
}

/// What a director tick asks `AppState` to do.
public enum ScheduleDirective: Equatable {
    /// Nothing to do this beat.
    case none
    /// The window just began and no tier is active — turn the lid tier on.
    case enableLid
    /// The window just ended and the running hold is the schedule's own —
    /// turn keep-awake off.
    case disableLid
}

/// The schedule's runtime half: edge detection + ownership, as a pure struct
/// so the whole manual-priority contract is unit-testable.
///
/// Two rules make up the contract:
///
/// **Edge-triggered.** A window "starts" only when a tick *observes* the
/// transition from outside to inside the window — app launch, enabling the
/// schedule mid-window, or a resume after auto mode all count as that first
/// observation. Each window instance is handled at most once;
/// `lastHandledWindowStart` (persisted by the app) makes that hold across a
/// relaunch, so a manual off can't be resurrected by restarting the app.
///
/// **Manual priority.** The schedule only ever owns a hold it started itself.
/// Any write that lands through another origin (`.user`, `.safety`,
/// `.autoOff`, `.auto`) clears that ownership, so the schedule never fights
/// the user: it doesn't re-light a manually cancelled window, and it doesn't
/// tear down a hold the user started. At window end it undoes only its own.
public struct ScheduleDirector: Equatable, Codable {
    /// Whether the previous tick observed the window as open.
    public private(set) var wasInWindow = false
    /// Whether the current keep-awake hold was started by this schedule and
    /// is therefore ours to end.
    public private(set) var ownsActivation = false
    /// The start of the most recently handled window instance. Persisted by
    /// the app and restored into a fresh director on launch — the marker that
    /// says "this window was already handled; don't replay its edge".
    public private(set) var lastHandledWindowStart: Date?

    public init() {}

    /// A fresh director carrying over the persisted marker from a previous
    /// session — how the app aligns a relaunch with window instances the last
    /// session already handled.
    public init(lastHandledWindowStart: Date?) {
        self.lastHandledWindowStart = lastHandledWindowStart
    }

    /// One scheduling beat (the app calls this from its 30-second tick).
    ///
    /// Suspended inputs (`autoModeOn`, or a nil schedule) freeze everything:
    /// no edges are observed, ownership doesn't move. Resumption therefore
    /// reads as one late observation under the same rules — inside a window
    /// with nothing running, it counts as the window start.
    public mutating func tick(now: Date,
                              schedule: WeeklySchedule?,
                              tierActive: Bool,
                              autoModeOn: Bool,
                              calendar: Calendar = .current) -> ScheduleDirective {
        guard !autoModeOn, let schedule else { return .none }
        let inWindow = schedule.contains(now, calendar: calendar)
        defer { wasInWindow = inWindow }

        if inWindow, !wasInWindow {
            let start = schedule.windowStart(containing: now, calendar: calendar)
            if start == lastHandledWindowStart { return .none }
            lastHandledWindowStart = start
            // Someone else's hold: don't claim it, and don't undo it later.
            guard !tierActive else { return .none }
            ownsActivation = true
            return .enableLid
        }

        if !inWindow, wasInWindow {
            guard ownsActivation else { return .none }
            ownsActivation = false
            return tierActive ? .disableLid : .none
        }

        // Mid-window: the hold we started has gone dark (the user or a safety
        // pause turned it off). This window stays silent from here on.
        if ownsActivation, !tierActive {
            ownsActivation = false
        }
        return .none
    }

    /// The single ownership rule: a landed write through `.schedule` sets
    /// ownership to what actually landed; any other origin cancels it. Safety
    /// pauses, the auto-off timer, and auto mode all act on the same tier, and
    /// none of their outcomes are the schedule's to undo.
    public mutating func noteWrite(origin: SetOrigin, landedActive: Bool) {
        ownsActivation = origin == .schedule && landedActive
    }

    /// A state the app adopted rather than wrote (external change, or a
    /// restore path giving up). An observed-off clears ownership; an
    /// observed-on was somebody else's doing, so it changes nothing.
    public mutating func noteAdopted(active: Bool) {
        if !active { ownsActivation = false }
    }

    /// The schedule was switched off. Turning the schedule off is not the
    /// request "turn keep-awake off" — it only gives up any hold claim.
    public mutating func relinquish() {
        ownsActivation = false
    }
}
