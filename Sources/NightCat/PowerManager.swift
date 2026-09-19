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
        guard let out = Shell.capture("/usr/bin/pmset", ["-g"]) else { return nil }
        return PowerParsers.sleepDisabled(pmsetG: out)
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
        let script = "do shell script \"/usr/bin/pmset -a disablesleep \(value)\" with administrator privileges"

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
