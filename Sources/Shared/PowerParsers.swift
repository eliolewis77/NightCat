import Foundation

/// Pure parsing helpers for `pmset` output. Kept free of side effects so they
/// can be unit-tested without touching real power management.
public enum PowerParsers {

    /// Parse `pmset -g` output for the `SleepDisabled` flag. The relevant line
    /// looks like: ` SleepDisabled        1`
    ///
    /// Returns nil when the output doesn't actually state the flag — the key is
    /// absent, or its value is something other than `0`/`1`. Truncated or
    /// unexpected output must not read as "off": that's a claim the Mac is free
    /// to sleep, made from data that says nothing of the sort.
    public static func sleepDisabled(pmsetG output: String) -> Bool? {
        for raw in output.split(separator: "\n") {
            let line = String(raw).lowercased()
            guard line.contains("sleepdisabled") else { continue }
            let remainder = line
                .replacingOccurrences(of: "sleepdisabled", with: "")
                .trimmingCharacters(in: .whitespaces)
            switch remainder {
            case "1": return true
            case "0": return false
            default:  return nil
            }
        }
        return nil
    }

    /// Lenient form, kept for callers that have no way to act on "unknown" —
    /// the helper's XPC reply is a plain `Bool`. Prefer `sleepDisabled(pmsetG:)`.
    public static func isSleepDisabled(pmsetG output: String) -> Bool {
        sleepDisabled(pmsetG: output) ?? false
    }

    // MARK: Sleep-preventing assertion holders (`pmset -g assertions`)

    /// Assertion types that stop the system from sleeping on its own. Only an
    /// exact token match counts — `PreventUserIdleDisplaySleep` (display only)
    /// and `LimitedPreventUserIdleSystemSleep` are deliberately not ours to
    /// claim.
    static let sleepPreventionAssertionTypes: Set<String> = [
        "PreventSystemSleep",
        "PreventUserIdleSystemSleep",
    ]

    /// Parses `pmset -g assertions` output into the processes holding a
    /// sleep-preventing assertion, in listing order — one entry per assertion
    /// line, duplicates included (a process may hold several; callers dedupe
    /// when attributing).
    ///
    /// Two output layouts are handled:
    ///
    /// - Flat (current macOS): lines under `Listed by owning process:` name
    ///   their assertion type inline —
    ///   `pid 79350(Amphetamine): [0x…] 03:53:14 PreventUserIdleSystemSleep named: "…"`.
    /// - Sectioned (older layouts): a bare `PreventSystemSleep:` header line,
    ///   with `pid N(name): …` lines below it belonging to the nearest header
    ///   above them. When a line names a type inline, the line wins over the
    ///   section it sits in.
    ///
    /// The parser always returns the pid: NightCat itself keeps a
    /// `caffeinate -d -w <our pid>` alive, so deciding which holders are "us"
    /// is the app layer's job, keyed on pid. Anything unparseable is skipped
    /// rather than guessed at — failures surface as an empty list, never a
    /// crash and never a misattributed holder.
    public static func sleepAssertionHolders(pmsetAssertions output: String) -> [AssertionHolder] {
        var holders: [AssertionHolder] = []
        var sectionType: String?

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("pid") {
                guard let holder = holderPrefix(line) else { continue }
                let inSleepSection = sectionType.map { sleepPreventionAssertionTypes.contains($0) } ?? false
                guard namesSleepAssertionInline(line) || inSleepSection else { continue }
                holders.append(holder)
            } else if line.hasSuffix(":") {
                // A bare `Type:` line opens a section; non-assertion headers
                // ("Listed by owning process:") are stored too — they simply
                // never match a sleep type.
                sectionType = String(line.dropLast()).trimmingCharacters(in: .whitespaces)
            }
            // Everything else — summary counts, kernel assertion `id=` lines,
            // continuation lines ("Created for PID: …", "Resources: …",
            // "Timeout will fire…") — states nothing we can attribute.
        }
        return holders
    }

    /// Extracts `pid N(name):` from the head of an assertion line. Returns nil
    /// for anything without that exact shape: the pid must be numeric and fit
    /// in `Int32`, the process name must be non-empty (an empty name can't be
    /// attributed to anyone), and the closing paren must be followed directly
    /// by the colon that introduces the assertion payload.
    private static func holderPrefix(_ line: String) -> AssertionHolder? {
        let afterPid = line.dropFirst(3)                          // "pid"
        guard let firstNonSpace = afterPid.firstIndex(where: { !$0.isWhitespace }) else { return nil }
        let body = afterPid[firstNonSpace...]
        let digits = body.prefix(while: { $0.isNumber })
        guard !digits.isEmpty, let pid = Int32(String(digits)) else { return nil }
        let afterDigits = body.dropFirst(digits.count)
        guard afterDigits.first == "(" else { return nil }
        let parenBody = afterDigits.dropFirst()
        guard let close = parenBody.firstIndex(of: ")") else { return nil }
        let name = parenBody[..<close]
        let afterClose = parenBody.index(after: close)
        guard !name.isEmpty, afterClose < parenBody.endIndex, parenBody[afterClose] == ":" else { return nil }
        return AssertionHolder(pid: pid, processName: String(name))
    }

    /// True when the line's own payload names a sleep-preventing assertion
    /// type. Only the part before `named:` is scanned — the quoted string
    /// after it is free text.
    private static func namesSleepAssertionInline(_ line: String) -> Bool {
        let payload: Substring
        if let namedAt = line.range(of: "named:") {
            payload = line[..<namedAt.lowerBound]
        } else {
            payload = line[...]
        }
        return payload.split(whereSeparator: \.isWhitespace).contains {
            sleepPreventionAssertionTypes.contains(String($0))
        }
    }
}

/// A process currently holding a sleep-preventing power assertion, as listed
/// by `pmset -g assertions`.
public struct AssertionHolder: Equatable {
    public let pid: Int32
    public let processName: String

    public init(pid: Int32, processName: String) {
        self.pid = pid
        self.processName = processName
    }
}

public struct BatteryInfo: Equatable {
    public let percent: Int
    public let onAC: Bool

    public init(percent: Int, onAC: Bool) {
        self.percent = percent
        self.onAC = onAC
    }

    public var source: String { onAC ? "AC" : "Battery" }
}

public enum BatteryParsers {
    /// Parse `pmset -g batt` output into a BatteryInfo.
    public static func parse(pmsetBatt output: String) -> BatteryInfo {
        var percent = 0
        if let range = output.range(of: #"\d+%"#, options: .regularExpression) {
            percent = Int(output[range].dropLast()) ?? 0
        }
        let onAC = output.contains("AC Power")
        return BatteryInfo(percent: percent, onAC: onAC)
    }
}
