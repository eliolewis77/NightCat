import Foundation

/// Runs the keep-alive ping: one long-lived `/sbin/ping -i <seconds> <gateway>`
/// whose only job is generating traffic so the AP and the NIC never call this
/// Mac idle. One process at a time, matching the requested target — the shape
/// mirrors `CaffeinateManager`.
///
/// Lifecycle is deliberate: the process dies with the app in both exit paths.
/// Clean quit stops it explicitly; a crash takes it down within one interval,
/// because our end of the stdout pipe closes and ping's next reply write gets
/// SIGPIPE. (The handler below must keep draining — a full pipe buffer would
/// block ping mid-write and silently stop the keep-alive.)
final class NetworkKeepAliveManager {
    /// Set when ping can't be started at all (missing binary and the like).
    /// Retrying would be pointless; the next `apply` tries again.
    var onError: ((String) -> Void)?
    /// Main-thread callback on every alive/stopped transition — the panel's
    /// keep-alive badge reads this, not a poll.
    var onRunningChanged: ((Bool) -> Void)?

    /// Whether a keep-alive ping is alive right now (panel display).
    private(set) var isRunning = false

    private struct Target: Equatable {
        let gateway: String
        let intervalSeconds: Int
    }

    private var process: Process?
    private var pipe: Pipe?
    private var runningTarget: Target?
    /// What the user currently wants, when enabled — survives ping deaths so
    /// the backoff loop knows what to bring back.
    private var desired: Target?
    /// Invalidates in-flight restarts: anything scheduled by a superseded
    /// generation must never resurrect itself.
    private var generation = 0
    private var consecutiveFailures = 0
    private var startedAt: Date?

    /// The single entry point, idempotent. `gateway == nil` means enabled but
    /// no default route yet — hold off; the next gateway event applies it.
    func apply(enabled: Bool, intervalMinutes: Int, gateway: String?) {
        guard enabled, let gateway else {
            stop()
            return
        }
        let target = Target(
            gateway: gateway,
            intervalSeconds: NetworkKeepAlivePolicy.pingIntervalSeconds(minutes: intervalMinutes))
        desired = target
        if process?.isRunning == true, runningTarget == target { return }
        start(target)
    }

    func stop() {
        desired = nil
        consecutiveFailures = 0
        teardown()
    }

    // MARK: - Process lifecycle

    private func start(_ target: Target) {
        teardown()
        let gen = generation

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/sbin/ping")
        proc.arguments = ["-i", String(target.intervalSeconds), target.gateway]
        let p = Pipe()
        p.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
        }
        proc.standardOutput = p
        proc.standardError = p
        proc.terminationHandler = { [weak self] _ in
            // Handler runs off-main; re-enter the actor on the main thread.
            DispatchQueue.main.async { self?.handleTermination(generation: gen) }
        }
        do {
            try proc.run()
        } catch {
            onError?(error.localizedDescription)
            return
        }
        process = proc
        pipe = p
        runningTarget = target
        startedAt = Date()
        setRunning(true)
    }

    private func handleTermination(generation gen: Int) {
        // A stop or a replacement caused this exit — not our business.
        guard gen == generation else { return }
        let uptime = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        consecutiveFailures = PingRestartPolicy.failureCount(
            current: consecutiveFailures, uptime: uptime)
        clearProcess()
        guard let target = desired else { return }

        let delay = PingRestartPolicy.delay(afterConsecutiveFailures: consecutiveFailures)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.generation == gen, let target = self.desired else { return }
            self.start(target)
        }
    }

    private func teardown() {
        generation += 1
        if let proc = process {
            // Nil the handler before terminating so its exit doesn't race the
            // drain callback.
            pipe?.fileHandleForReading.readabilityHandler = nil
            if proc.isRunning { proc.terminate() }
        }
        clearProcess()
    }

    private func clearProcess() {
        process = nil
        pipe = nil
        runningTarget = nil
        startedAt = nil
        setRunning(false)
    }

    private func setRunning(_ value: Bool) {
        guard isRunning != value else { return }
        isRunning = value
        onRunningChanged?(value)
    }
}
