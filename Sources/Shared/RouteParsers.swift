import Foundation

/// The default route's usable facts, as `route -n get default` reported them.
public struct DefaultRoute: Equatable {
    /// Dotted-quad IPv4 of the gateway. A value is only ever produced after
    /// strict validation — a hostname, an interface name, or an IPv6 literal
    /// never masquerades as a gateway.
    public let gatewayIPv4: String
    /// The egress interface ("en0"), when the output named one.
    public let interfaceName: String?

    public init(gatewayIPv4: String, interfaceName: String?) {
        self.gatewayIPv4 = gatewayIPv4
        self.interfaceName = interfaceName
    }
}

/// Pure parsing helpers for `route -n get default`. No side effects, so the
/// parsing can be unit-tested without touching the real routing table.
public enum RouteParsers {

    /// Parses `route -n get default` stdout into the default route.
    ///
    /// Returns nil — never a fabricated route — when the output doesn't
    /// actually state an IPv4 gateway: no default route (the command then
    /// exits non-zero and usually prints nothing), a link-layer route whose
    /// gateway is an interface name (`gateway: en0`), an IPv6 gateway, or
    /// output too mangled to trust. A nil means "nothing to keep alive
    /// against", not "offline".
    public static func defaultRoute(routeGetOutput: String) -> DefaultRoute? {
        var gateway: String?
        var interface: String?

        for raw in routeGetOutput.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("gateway:") {
                gateway = value(after: "gateway:", in: line)
            } else if line.hasPrefix("interface:") {
                interface = value(after: "interface:", in: line)
            }
        }

        guard let gateway, isIPv4(gateway) else { return nil }
        return DefaultRoute(gatewayIPv4: gateway, interfaceName: interface)
    }

    /// Strict dotted-quad IPv4 check via `inet_pton` — rejects hostnames,
    /// interface names, IPv6 literals, and leading-zero oddities alike.
    public static func isIPv4(_ s: String) -> Bool {
        var addr = in_addr()
        return s.withCString { inet_pton(AF_INET, $0, &addr) == 1 }
    }

    private static func value(after prefix: String, in line: String) -> String? {
        let remainder = line.dropFirst(prefix.count)
            .trimmingCharacters(in: .whitespaces)
        return remainder.isEmpty ? nil : remainder
    }
}
