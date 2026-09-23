import Foundation

/// How the active interface reaches the network. Own copy, so Shared stays
/// free of the Network framework (this file also compiles into the helper
/// and the test bundle).
public enum NetInterfaceKind: String, Equatable, Codable {
    case wifi
    case wired
    case other
}

/// One sample of the network world. Every field is handed in by the caller —
/// this type does no I/O of its own, which is what makes the event detector
/// below table-testable.
public struct NetworkSnapshot: Equatable {
    /// `NWPath.status == .satisfied`.
    public let online: Bool
    public let interfaceKind: NetInterfaceKind?
    public let interfaceName: String?
    public let ipv4: String?
    public let gatewayIPv4: String?
    /// Best effort — nil whenever macOS won't hand it over without location
    /// consent. Absence never blocks anything.
    public let ssid: String?

    public init(online: Bool,
                interfaceKind: NetInterfaceKind?,
                interfaceName: String?,
                ipv4: String?,
                gatewayIPv4: String?,
                ssid: String?) {
        self.online = online
        self.interfaceKind = interfaceKind
        self.interfaceName = interfaceName
        self.ipv4 = ipv4
        self.gatewayIPv4 = gatewayIPv4
        self.ssid = ssid
    }

    /// The nothing-known sample: startup before the first path report, or a
    /// monitor that never delivered.
    public static let offline = NetworkSnapshot(
        online: false, interfaceKind: nil, interfaceName: nil,
        ipv4: nil, gatewayIPv4: nil, ssid: nil)
}

/// Something worth a log line (and, for an IP move, a notification).
public enum NetworkEvent: Equatable {
    /// Was offline (or unknown) — now satisfiable.
    case online(NetworkSnapshot)
    /// Was satisfiable — now not.
    case offline(previousInterface: String?)
    case ipv4Changed(old: String?, new: String?)
    case gatewayChanged(old: String?, new: String?)
    case interfaceChanged(old: String?, new: String?)
}

/// Diffs consecutive snapshots into events. Offline periods report nothing
/// but the offline/online edges themselves: addresses churning while the
/// link is down is noise, not news.
public enum NetworkEventDetector {

    /// `from == nil` is the first sample ever taken: an online result is the
    /// arrival event, an offline one is simply where the machine started.
    public static func events(from old: NetworkSnapshot?, to new: NetworkSnapshot) -> [NetworkEvent] {
        guard let old else {
            return new.online ? [.online(new)] : []
        }

        var events: [NetworkEvent] = []
        if old.online, !new.online {
            events.append(.offline(previousInterface: old.interfaceName))
        }
        if !old.online, new.online {
            events.append(.online(new))
        }
        guard old.online, new.online else { return events }

        if old.ipv4 != new.ipv4 {
            events.append(.ipv4Changed(old: old.ipv4, new: new.ipv4))
        }
        if old.gatewayIPv4 != new.gatewayIPv4 {
            events.append(.gatewayChanged(old: old.gatewayIPv4, new: new.gatewayIPv4))
        }
        if old.interfaceName != new.interfaceName {
            events.append(.interfaceChanged(old: old.interfaceName, new: new.interfaceName))
        }
        return events
    }
}

/// Renders events as single tab-separated log lines.
public enum NetworkLog {

    /// Local wall-clock time — this log is read by a human returning to a
    /// machine after the fact, in their own timezone.
    public static func timestamp(_ date: Date) -> String {
        formatter.string(from: date)
    }

    /// One line per event, e.g.
    /// `2026-09-23 14:32:05<TAB>online<TAB>interface=en0<TAB>ip=…<TAB>gateway=…<TAB>ssid=…`
    /// Absent facts print as `-` so columns stay greppable.
    public static func line(for event: NetworkEvent, at date: Date, snapshot: NetworkSnapshot) -> String {
        var parts = [timestamp(date), Self.token(of: event)]

        switch event {
        case .offline(let previous):
            parts.append("previous=\(previous ?? "-")")
        case .ipv4Changed(let old, let new):
            parts.append(contentsOf: ["from=\(old ?? "-")", "to=\(new ?? "-")"])
        case .gatewayChanged(let old, let new):
            parts.append(contentsOf: ["from=\(old ?? "-")", "to=\(new ?? "-")"])
        case .interfaceChanged(let old, let new):
            parts.append(contentsOf: ["from=\(old ?? "-")", "to=\(new ?? "-")"])
        case .online:
            break
        }

        if !(event.isOfflineEdge) {
            parts.append("interface=\(snapshot.interfaceName ?? "-")")
            parts.append("ip=\(snapshot.ipv4 ?? "-")")
            parts.append("gateway=\(snapshot.gatewayIPv4 ?? "-")")
            parts.append("ssid=\(snapshot.ssid ?? "-")")
        }
        return parts.joined(separator: "\t")
    }

    /// Rotate when the log outgrows `maxBytes` — checked before each append.
    public static func shouldRotate(fileSizeBytes: Int, maxBytes: Int = 256 * 1024) -> Bool {
        fileSizeBytes > maxBytes
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    private static func token(of event: NetworkEvent) -> String {
        switch event {
        case .online: return "online"
        case .offline: return "offline"
        case .ipv4Changed: return "ipv4_changed"
        case .gatewayChanged: return "gateway_changed"
        case .interfaceChanged: return "interface_changed"
        }
    }
}

extension NetworkEvent {
    /// The offline edge carries no snapshot worth recording — nothing about
    /// the network is knowable at that moment beyond what we came from.
    var isOfflineEdge: Bool {
        if case .offline = self { return true }
        return false
    }
}
