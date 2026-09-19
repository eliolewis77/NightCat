import SwiftUI

/// One quiet row in the panel's status group: this Mac's primary LAN IPv4,
/// click to copy. For the remote-workflow user this is the number they look up
/// most often — DHCP makes it move, and System Settings is a detour.
///
/// Layout-agnostic by design (panel-redesign §A): no insets of its own, so the
/// group that owns the row decides where the column starts.
struct LocalIPRow: View {
    @State private var ip: String?
    @State private var copied = false

    var body: some View {
        Group {
            if let ip {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ip, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copied = false
                    }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: copied ? "checkmark" : "wifi")
                            .font(.system(size: 11, weight: copied ? .semibold : .regular))
                            .foregroundStyle(copied ? Color.green : Color.secondary)
                        Text(copied
                             ? NSLocalizedString("已复制", comment: "IP copied feedback")
                             : String(format: NSLocalizedString("本机 IP %@", comment: "local IP row"), ip))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .help(NSLocalizedString("点击复制本机 IP 地址", comment: "IP copy help"))
            }
        }
        .onAppear { ip = Self.primaryIPv4() }
    }

    /// First IPv4 of the built-in interfaces, preferring `en0` (Wi-Fi on
    /// laptops, the interface a remote session almost always rides).
    static func primaryIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var fallback: String?
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }
            let interface = current.pointee
            guard let sa = interface.ifa_addr,
                  sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name)
            guard name == "en0" || name.hasPrefix("en") else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: host)
            if name == "en0" { return ip }
            fallback = fallback ?? ip
        }
        return fallback
    }
}
