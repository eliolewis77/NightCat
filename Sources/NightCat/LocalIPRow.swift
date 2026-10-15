import SwiftUI

/// One quiet row in the panel's status group: this Mac's primary LAN IPv4,
/// click to copy. For the remote-workflow user this is the number they look up
/// most often — DHCP makes it move, and System Settings is a detour.
///
/// Layout-agnostic by design (panel-redesign §A): no insets of its own, so the
/// group that owns the row decides where the column starts.
struct LocalIPRow: View {
    @EnvironmentObject var state: AppState
    @State private var fallbackIP: String?
    @State private var copied = false
    /// Owns the reset of `copied`. A bare `asyncAfter` would stack one timer
    /// per click — the first would clear the flag out from under the second —
    /// and keep firing after the panel closed. Cancelling on re-copy and on
    /// disappear fixes both.
    @State private var copyResetTask: Task<Void, Never>?

    /// The monitor's sample is the source of truth — it refreshes on every
    /// network event and lands within a second of launch. The one-shot read
    /// only covers the instant before that first sample arrives.
    private var ip: String? { state.networkStatus?.ipv4 ?? fallbackIP }

    var body: some View {
        Group {
            if let ip {
                HStack(spacing: 9) {
                    Image(systemName: copied ? "checkmark" : "wifi")
                        .font(PanelFont.micro.weight(copied ? .semibold : .regular))
                        .foregroundStyle(copied ? Color.green : Color.secondary)
                        .accessibilityHidden(true)
                    Text(copied
                         ? NSLocalizedString("已复制", comment: "IP copied feedback")
                         : String(format: NSLocalizedString("本机 IP %@", comment: "local IP row"), ip))
                        .font(PanelFont.footnote)
                        .foregroundStyle(.secondary)
                    if state.keepAliveRunning {
                        Text("保活中")
                            .font(PanelFont.micro)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                    Button {
                        copyIP(ip)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundStyle(copied ? Color.green : Color.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 3)
                            .contentShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    // 只有复制按钮是交互元素:hover 高亮、tooltip、无障碍
                    // 标签都挂在它身上;行的其余部分是纯展示,不给点击面。
                    .hoverHighlight(in: RoundedRectangle(cornerRadius: 4), opacity: 0.06)
                    .help(NSLocalizedString("点击复制本机 IP 地址", comment: "IP copy help"))
                    .accessibilityLabel(Text("复制本机 IP 地址"))
                }
            }
        }
        .onAppear { fallbackIP = Self.primaryIPv4() }
        .onDisappear { copyResetTask?.cancel() }
    }

    private func copyIP(_ ip: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ip, forType: .string)
        copied = true
        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            copied = false
        }
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
