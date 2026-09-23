import Foundation
import Network
import CoreWLAN
import CoreLocation

/// Event-driven network observation: NWPathMonitor reports a change, we take
/// one sample of the world (IP, gateway, SSID) on a serial queue, and diff it
/// against the previous one. Monitoring is always on — it is what turns a
/// morning-after "remote was unreachable" into a timeline someone can read.
/// Sampling runs on `queue` (CoreWLAN is picky about that); the diff and the
/// callback run on the main thread.
final class NetworkMonitor {
    /// Called on the main thread. Empty `events` never arrives — the caller
    /// gets nothing when nothing changed.
    var onEvent: (([NetworkEvent], NetworkSnapshot) -> Void)?

    /// The latest full snapshot, for rows that want to read it synchronously.
    private(set) var current: NetworkSnapshot?

    private let queue = DispatchQueue(label: "com.eliokit.nightcat.network")
    private var monitor: NWPathMonitor?

    func start() {
        guard monitor == nil else { return }
        let m = NWPathMonitor()
        monitor = m
        m.pathUpdateHandler = { [weak self] path in
            self?.report(path: path)
        }
        m.start(queue: queue)
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
    }

    /// Fallback resample for address changes that don't move the path
    /// (DHCP renewals handing out a new lease on the same route). Rides the
    /// app's existing 30 s tick; produces events only on a real diff.
    func refreshNow() {
        queue.async { [weak self] in
            guard let self else { return }
            self.report(path: self.monitor?.currentPath)
        }
    }

    // MARK: - Sampling (runs on `queue`)

    private func report(path: NWPath?) {
        let snapshot = Self.sample(path: path)
        DispatchQueue.main.async { [weak self] in
            self?.absorb(snapshot)
        }
    }

    private func absorb(_ new: NetworkSnapshot) {
        let events = NetworkEventDetector.events(from: current, to: new)
        current = new
        guard !events.isEmpty else { return }
        onEvent?(events, new)
    }

    private static func sample(path: NWPath?) -> NetworkSnapshot {
        let online = path?.status == .satisfied
        guard online else { return .offline }

        let kind: NetInterfaceKind
        if path!.usesInterfaceType(.wifi) {
            kind = .wifi
        } else if path!.usesInterfaceType(.wiredEthernet) {
            kind = .wired
        } else {
            kind = .other
        }

        // Only the active default route matters: it's the path remote traffic
        // actually rides, and the only one worth keeping warm.
        let route = Shell.capture("/sbin/route", ["-n", "get", "default"])
            .flatMap { RouteParsers.defaultRoute(routeGetOutput: $0) }
        let ssid = kind == .wifi ? sampleSSID(interfaceName: route?.interfaceName) : nil

        return NetworkSnapshot(
            online: true,
            interfaceKind: kind,
            interfaceName: route?.interfaceName,
            ipv4: LocalIPRow.primaryIPv4(),
            gatewayIPv4: route?.gatewayIPv4,
            ssid: ssid)
    }

    /// macOS won't hand out the SSID without location consent from macOS 14
    /// on. We read it only when consent already exists; a request is never
    /// made — an SSID label isn't worth a system permission dialog, and the
    /// row falls back to the interface name.
    private static func sampleSSID(interfaceName: String?) -> String? {
        guard let interfaceName else { return nil }
        if #available(macOS 14, *) {
            // macOS has no WhenInUse tier — SSID needs Always consent, and we
            // never ask for it; absent consent the row falls back to en0.
            guard CLLocationManager.authorizationStatus() == .authorizedAlways else { return nil }
        }
        guard let interface = CWWiFiClient.shared().interface(withName: interfaceName) else { return nil }
        return (try? interface.ssid()) ?? nil
    }
}
