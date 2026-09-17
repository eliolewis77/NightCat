import Foundation

/// Tiny helper to run a command and capture stdout.
///
/// Returns nil if the process couldn't be launched *or* exited non-zero. A
/// failed command usually writes nothing to stdout, and an empty string parses
/// as a perfectly plausible "flag is off" — so a caller that can't tell the two
/// apart will quietly invent state it never read.
enum Shell {
    static func capture(_ path: String, _ args: [String]) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
        } catch {
            return nil
        }
        // Drain before waiting: a full pipe would deadlock a chatty command.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
