import Foundation

/// Exit-restoration policy for the system `SleepDisabled` flag (SPEC §9): on a
/// normal exit, put the flag back to the value it had **before we took it
/// over**, rather than unconditionally writing 0.
///
/// Division of labour with the privileged helper:
///
/// - **Normal exit** (the user quits the app): the app restores using
///   `restoreValue(of:)` with the baseline it captured.
/// - **Crash / force quit**: no app code runs, and the helper's 90-second
///   watchdog unconditionally writes 0. That fixed 0 is a deliberate safety
///   net — a Mac stuck awake forever is worse than one whose externally-set
///   baseline is lost — and it is intentionally untouched by this policy.
///
/// Ownership boundary: a baseline is captured only at the moment NightCat is
/// about to write 1 while the flag still reads 0 — i.e. only when the 0→1
/// transition is genuinely ours. If the flag already reads 1 (Amphetamine or
/// another tool is holding it), `capture(current:)` returns nil: we never
/// owned the state, so the restore on exit is not ours to issue either.
public enum ExitRestore {

    /// The pre-takeover snapshot. Its existence is the whole claim "we took
    /// the flag over and owe a restore on exit".
    public struct Baseline: Equatable {
        /// The flag value observed immediately before our first write of 1.
        public let previous: Bool

        public init(previous: Bool) {
            self.previous = previous
        }
    }

    /// Call immediately before the app writes `disablesleep 1`, passing the
    /// freshly observed flag value.
    ///
    /// - `current == false`: the takeover is genuinely ours — returns the
    ///   baseline to restore on a normal exit.
    /// - `current == true`: somebody else already holds the flag — returns
    ///   nil, meaning "not ours". The caller keys off the same nil to skip
    ///   the exit restore entirely: writing 0 would stomp the other tool's
    ///   session.
    public static func capture(current: Bool) -> Baseline? {
        guard !current else { return nil }
        return Baseline(previous: current)
    }

    /// The value a **normal** exit should restore.
    ///
    /// A captured baseline restores its own `previous` value. A nil baseline
    /// falls back to `false` (SPEC §9: "restore 0 if the baseline was never
    /// captured") — a conservative value for callers that never captured but
    /// still must write something, and a harmless no-op when we never wrote 1.
    /// Callers that know `capture` refused ownership (external takeover)
    /// should not issue a restore at all; nil is their signal.
    public static func restoreValue(of baseline: Baseline?) -> Bool {
        baseline?.previous ?? false
    }
}
