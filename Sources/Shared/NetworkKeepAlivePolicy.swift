import Foundation

/// The dial the user turns: which keep-alive interval is valid, and how a
/// ping process that keeps dying should be retried. Pure math — the timers
/// and the process live elsewhere.
public enum NetworkKeepAlivePolicy {

    /// Slider bounds shown in Settings; anything outside is a stored relic
    /// (an old default, a hand-edited plist), not a request.
    public static let minutesRange = 1...30
    public static let defaultMinutes = 3

    /// Collapses a raw stored value into the valid domain. Zero and negatives
    /// (UserDefaults' answer when the key was never written) fall back to the
    /// default rather than the lower bound — "unset" and "deliberately 1 min"
    /// are different intents.
    public static func clampedMinutes(_ raw: Int) -> Int {
        guard raw >= 1 else { return defaultMinutes }
        return min(raw, minutesRange.upperBound)
    }

    /// `ping -i` takes seconds.
    public static func pingIntervalSeconds(minutes: Int) -> Int {
        clampedMinutes(minutes) * 60
    }
}

/// Backoff for a keep-alive ping that exits when it shouldn't. A ping that
/// merely can't reach its gateway keeps running (printing timeouts), so an
/// actual exit means the process was killed or intercepted — worth retrying,
/// but politely: doubling from 1 s, capped at 60 s. A run that survived at
/// least `stableUptime` resets the streak; one that died young climbs it.
public struct PingRestartPolicy {

    public struct Config: Equatable {
        public let baseDelay: TimeInterval
        public let maxDelay: TimeInterval
        public let stableUptime: TimeInterval

        public init(baseDelay: TimeInterval = 1, maxDelay: TimeInterval = 60, stableUptime: TimeInterval = 60) {
            self.baseDelay = baseDelay
            self.maxDelay = maxDelay
            self.stableUptime = stableUptime
        }

        public static let `default` = Config()
    }

    /// Next restart delay after `n` consecutive young deaths. `n` below 1 is
    /// treated as the first failure.
    public static func delay(afterConsecutiveFailures n: Int, config: Config = .default) -> TimeInterval {
        let failures = max(n, 1)
        return min(config.maxDelay, config.baseDelay * pow(2, Double(failures - 1)))
    }

    public static func isStable(uptime: TimeInterval, config: Config = .default) -> Bool {
        uptime >= config.stableUptime
    }

    /// The failure count a death at `uptime` contributes: a stable run starts
    /// the streak over, a young one extends it.
    public static func failureCount(current: Int, uptime: TimeInterval, config: Config = .default) -> Int {
        isStable(uptime: uptime, config: config) ? 1 : current + 1
    }
}
