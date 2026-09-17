import Foundation

/// Runs the App-layer `caffeinate` process for the tiers that don't need root
/// (`screen` / `preventIdle`). One process at a time, matching the requested
/// tier.
///
/// The process is spawned with `-w <this app's pid>`: caffeinate exits when
/// the app's process dies, so an assertion can never outlive NightCat. That's
/// the App-layer counterpart of the helper's 90-second watchdog, and the
/// property that lets these tiers run without one.
final class CaffeinateManager {
    /// Called when caffeinate can't be started at all — not expected on a
    /// stock macOS install, but a silently missing assertion is worse than a
    /// visible error.
    var onError: ((String) -> Void)?

    private var process: Process?
    private var runningFlags: [String] = []

    /// The pid of the live caffeinate, for attribution filtering: our own
    /// assertion holder must never be reported as an external takeover.
    var runningPID: Int32? { process?.processIdentifier }

    /// Make the running caffeinate match `mode`: a no-op when it already
    /// does, otherwise stop the old process and start the new one.
    func apply(_ mode: KeepAwakeMode) {
        guard let flags = mode.caffeinateArguments else {
            stop()
            return
        }
        if process?.isRunning == true, runningFlags == flags { return }
        stop()
        start(flags)
    }

    func stop() {
        guard let process else { return }
        if process.isRunning {
            process.terminate()
        }
        self.process = nil
        runningFlags = []
    }

    private func start(_ flags: [String]) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        proc.arguments = flags + ["-w", String(ProcessInfo.processInfo.processIdentifier)]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        // An empty handler makes Foundation reap the child; without one,
        // every tier switch would leave a zombie until the app exits.
        proc.terminationHandler = { _ in }
        do {
            try proc.run()
            process = proc
            runningFlags = flags
        } catch {
            onError?(error.localizedDescription)
        }
    }
}
