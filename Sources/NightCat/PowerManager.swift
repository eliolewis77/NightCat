import Foundation

/// Controls the macOS `SleepDisabled` flag (IOPMrootDomain).
///
/// This is the **fallback** path, used only when the privileged helper isn't
/// installed: it shells out to `pmset -a disablesleep` via `osascript` with
/// administrator privileges, so toggling prompts for the admin password.
///
/// The primary path is `HelperManager`, which sets the flag over XPC through a
/// root helper installed via `SMAppService` — password-less, plus a heartbeat
/// watchdog that auto-clears the flag if the app dies.
struct PowerManager {

    /// Read the current `SleepDisabled` flag from `pmset -g`.
    ///
    /// Returns nil whenever the flag wasn't actually observed — `pmset` failed to
    /// launch, exited non-zero, or printed something that doesn't state the flag.
    /// A failed read must never collapse into "off".
    ///
    /// Reading needs no privileges, so this is the app's read path whether or not
    /// the helper is installed; the helper is only needed to *change* the flag.
    func isSleepDisabled() -> Bool? {
        readPowerState().observed
    }

    /// Whether the lid is closed, from the IOPMrootDomain clamshell key.
    /// nil when the machine has no lid (desktops) or the read failed.
    func isLidClosed() -> Bool? {
        guard let out = Shell.capture("/usr/sbin/ioreg", ["-r", "-k", "AppleClamshellState"]) else { return nil }
        return PowerParsers.isLidClosed(ioregOutput: out)
    }

    /// One `pmset -g` reading: the flag plus the raw output — the output also
    /// carries the repeating-power-events section the wake-belief
    /// reconciliation checks, so one spawn serves both readers.
    func readPowerState() -> (observed: Bool?, schedOutput: String) {
        let out = Shell.capture("/usr/bin/pmset", ["-g"]) ?? ""
        return (PowerParsers.sleepDisabled(pmsetG: out), out)
    }

    /// Set or clear the flag. Calls `completion` exactly once with the
    /// underlying error on failure (including the user cancelling the admin
    /// prompt), `nil` on success — **on an arbitrary background thread**; hop to
    /// the queue you need yourself.
    ///
    /// Runs asynchronously on purpose: the admin prompt can sit on screen for as
    /// long as the user takes, and blocking the main actor here freezes the whole
    /// menu-bar app — its status item, its popover, and the 30-second heartbeat
    /// that keeps the helper's watchdog from restoring sleep under a live tier.
    /// (No main-queue hop here either: the exit path waits on the completion with
    /// a semaphore while its caller is already parked on the main thread, and a
    /// main-queue dispatch could never run under that wait.)
    func setSleepDisabled(_ enabled: Bool, completion: @escaping (Error?) -> Void) {
        let value = enabled ? "1" : "0"
        runAdminScript(
            "do shell script \"/usr/bin/pmset -a disablesleep \(value)\" with administrator privileges",
            completion: completion)
    }

    /// Set or clear the system-wide repeating wake event through the admin
    /// prompt — the fallback for when the helper can't do it (not installed,
    /// or too old for the `setRepeatingWake` XPC method). Same contract as
    /// `setSleepDisabled`: asynchronous, exactly one completion on an
    /// arbitrary background thread.
    func setRepeatingWake(weekdayMask: Int, minutes: Int, enabled: Bool,
                          completion: @escaping (Error?) -> Void) {
        guard let script = RepeatingWake.shellScript(weekdayMask: weekdayMask,
                                                     minutes: minutes,
                                                     enabled: enabled) else {
            completion(NSError(
                domain: "NightCat.PowerManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: RepeatingWake.invalidArgumentsMessage]
            ))
            return
        }
        runAdminScript(script, completion: completion)
    }

    /// The shared osascript plumbing: run one `do shell script … with
    /// administrator privileges` line, report stderr (or the user cancelling
    /// the prompt) through `completion` exactly once.
    private func runAdminScript(_ script: String, completion: @escaping (Error?) -> Void) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        let errPipe = Pipe()
        proc.standardError = errPipe
        proc.standardOutput = Pipe()

        // The error pipe is only read once the process has exited, so the read
        // can't deadlock; it happens before completion is dispatched.
        proc.terminationHandler = { process in
            if process.terminationStatus != 0 {
                let data = errPipe.fileHandleForReading.readDataToEndOfFile()
                let msg = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                completion(NSError(
                    domain: "NightCat.PowerManager",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: msg.isEmpty
                        ? NSLocalizedString("已取消管理员授权。", comment: "pmset error")
                        : msg]
                ))
            } else {
                completion(nil)
            }
        }

        do {
            try proc.run()
        } catch {
            completion(error)
        }
    }
}
