import XCTest

final class NetworkKeepAliveTests: XCTestCase {

    // MARK: RouteParsers.defaultRoute

    /// A real `route -n get default` transcript, indentation included.
    private let realRouteOutput = """
           route to: default
        destination: default
               mask: default
            gateway: 192.168.31.1
          interface: en0
              flags: <UP,GATEWAY,DONE,STATIC,PRCLONING,GLOBAL>
        """

    func testRouteParsesRealOutput() {
        let route = RouteParsers.defaultRoute(routeGetOutput: realRouteOutput)
        XCTAssertEqual(route?.gatewayIPv4, "192.168.31.1")
        XCTAssertEqual(route?.interfaceName, "en0")
    }

    /// A link-layer route names an interface as its gateway — that's not a
    /// gateway to ping.
    func testLinkLayerGatewayIsRejected() {
        let out = "destination: default\n   gateway: en0\n interface: en0"
        XCTAssertNil(RouteParsers.defaultRoute(routeGetOutput: out))
    }

    func testIPv6GatewayIsRejected() {
        let out = "destination: default\n   gateway: fe80::1\n interface: en0"
        XCTAssertNil(RouteParsers.defaultRoute(routeGetOutput: out))
    }

    func testHostnameGatewayIsRejected() {
        let out = "destination: default\n   gateway: router.local\n interface: en0"
        XCTAssertNil(RouteParsers.defaultRoute(routeGetOutput: out))
    }

    func testMissingGatewayLineIsRejected() {
        XCTAssertNil(RouteParsers.defaultRoute(routeGetOutput: ""))
        XCTAssertNil(RouteParsers.defaultRoute(routeGetOutput: "destination: default\n interface: en0"))
    }

    /// No `interface:` line is a best-effort miss, not a rejection — the
    /// gateway is still real.
    func testMissingInterfaceLineStillYieldsGateway() {
        let out = "   gateway: 10.0.0.1"
        let route = RouteParsers.defaultRoute(routeGetOutput: out)
        XCTAssertEqual(route?.gatewayIPv4, "10.0.0.1")
        XCTAssertNil(route?.interfaceName)
    }

    func testIsIPv4() {
        XCTAssertTrue(RouteParsers.isIPv4("192.168.31.1"))
        XCTAssertTrue(RouteParsers.isIPv4("0.0.0.0"))
        XCTAssertFalse(RouteParsers.isIPv4("en0"))
        XCTAssertFalse(RouteParsers.isIPv4("fe80::1"))
        XCTAssertFalse(RouteParsers.isIPv4(""))
        XCTAssertFalse(RouteParsers.isIPv4("192.168.31"))
    }

    // MARK: NetworkKeepAlivePolicy

    func testClampedMinutes() {
        XCTAssertEqual(NetworkKeepAlivePolicy.clampedMinutes(0), 3)     // unset → default
        XCTAssertEqual(NetworkKeepAlivePolicy.clampedMinutes(-5), 3)
        XCTAssertEqual(NetworkKeepAlivePolicy.clampedMinutes(1), 1)
        XCTAssertEqual(NetworkKeepAlivePolicy.clampedMinutes(3), 3)
        XCTAssertEqual(NetworkKeepAlivePolicy.clampedMinutes(30), 30)
        XCTAssertEqual(NetworkKeepAlivePolicy.clampedMinutes(31), 30)
        XCTAssertEqual(NetworkKeepAlivePolicy.clampedMinutes(999), 30)
    }

    func testPingIntervalSeconds() {
        XCTAssertEqual(NetworkKeepAlivePolicy.pingIntervalSeconds(minutes: 3), 180)
        XCTAssertEqual(NetworkKeepAlivePolicy.pingIntervalSeconds(minutes: 30), 1800)
        XCTAssertEqual(NetworkKeepAlivePolicy.pingIntervalSeconds(minutes: 0), 180)  // unset → default
    }

    // MARK: PingRestartPolicy

    func testBackoffDelayDoublesThenCaps() {
        XCTAssertEqual(PingRestartPolicy.delay(afterConsecutiveFailures: 1), 1)
        XCTAssertEqual(PingRestartPolicy.delay(afterConsecutiveFailures: 2), 2)
        XCTAssertEqual(PingRestartPolicy.delay(afterConsecutiveFailures: 3), 4)
        XCTAssertEqual(PingRestartPolicy.delay(afterConsecutiveFailures: 7), 60)   // cap from here on
        XCTAssertEqual(PingRestartPolicy.delay(afterConsecutiveFailures: 50), 60)
        XCTAssertEqual(PingRestartPolicy.delay(afterConsecutiveFailures: 0), 1)    // degenerate → first failure
    }

    func testStabilityThreshold() {
        XCTAssertFalse(PingRestartPolicy.isStable(uptime: 59.9))
        XCTAssertTrue(PingRestartPolicy.isStable(uptime: 60))
        XCTAssertTrue(PingRestartPolicy.isStable(uptime: 3600))
    }

    func testFailureCountResetsAfterStableRun() {
        XCTAssertEqual(PingRestartPolicy.failureCount(current: 5, uptime: 120), 1)
        XCTAssertEqual(PingRestartPolicy.failureCount(current: 5, uptime: 10), 6)
    }

    // MARK: NetworkEventDetector

    private func snapshot(online: Bool, ipv4: String? = nil, gateway: String? = nil,
                          interface: String? = nil, ssid: String? = nil) -> NetworkSnapshot {
        NetworkSnapshot(online: online, interfaceKind: online ? .wifi : nil,
                        interfaceName: interface, ipv4: ipv4,
                        gatewayIPv4: gateway, ssid: ssid)
    }

    func testFirstSampleOnlineIsArrival() {
        let new = snapshot(online: true, ipv4: "1.2.3.4", gateway: "1.2.3.1")
        XCTAssertEqual(NetworkEventDetector.events(from: nil, to: new), [.online(new)])
    }

    /// Starting offline states nothing — there's no change to report.
    func testFirstSampleOfflineIsEmpty() {
        XCTAssertTrue(NetworkEventDetector.events(from: nil, to: snapshot(online: false)).isEmpty)
    }

    func testOnlineToOffline() {
        let old = snapshot(online: true, interface: "en0")
        let events = NetworkEventDetector.events(from: old, to: snapshot(online: false))
        XCTAssertEqual(events, [.offline(previousInterface: "en0")])
    }

    func testOfflineToOnlineCarriesSnapshot() {
        let new = snapshot(online: true, ipv4: "5.6.7.8", gateway: "5.6.7.1", interface: "en0")
        let events = NetworkEventDetector.events(from: snapshot(online: false), to: new)
        XCTAssertEqual(events, [.online(new)])
    }

    func testAddressChangeWhileOnline() {
        let old = snapshot(online: true, ipv4: "1.2.3.4", gateway: "1.2.3.1", interface: "en0")
        let new = snapshot(online: true, ipv4: "1.2.3.99", gateway: "1.2.3.1", interface: "en0")
        XCTAssertEqual(NetworkEventDetector.events(from: old, to: new),
                       [.ipv4Changed(old: "1.2.3.4", new: "1.2.3.99")])
    }

    func testGatewayAndInterfaceChanges() {
        let old = snapshot(online: true, ipv4: "1.2.3.4", gateway: "1.2.3.1", interface: "en0")
        let new = snapshot(online: true, ipv4: "9.9.9.9", gateway: "9.9.9.1", interface: "en5")
        XCTAssertEqual(NetworkEventDetector.events(from: old, to: new),
                       [.ipv4Changed(old: "1.2.3.4", new: "9.9.9.9"),
                        .gatewayChanged(old: "1.2.3.1", new: "9.9.9.1"),
                        .interfaceChanged(old: "en0", new: "en5")])
    }

    /// Same route, different name — 2.4G/5G roaming on one router.
    func testSSIDChangeWhileOnline() {
        let old = snapshot(online: true, ipv4: "1.2.3.4", gateway: "1.2.3.1", ssid: "Home-2G")
        let new = snapshot(online: true, ipv4: "1.2.3.4", gateway: "1.2.3.1", ssid: "Home-5G")
        XCTAssertEqual(NetworkEventDetector.events(from: old, to: new),
                       [.ssidChanged(old: "Home-2G", new: "Home-5G")])
    }

    func testSSIDChangedLineCarriesFromAndTo() {
        let snap = snapshot(online: true, ipv4: "1.2.3.4", gateway: "1.2.3.1", ssid: "Home-5G")
        let line = logLine(.ssidChanged(old: "Home-2G", new: "Home-5G"), snapshot: snap)
        XCTAssertTrue(line.contains("ssid_changed"))
        XCTAssertTrue(line.contains("from=Home-2G"))
        XCTAssertTrue(line.contains("to=Home-5G"))
    }

    func testNoChangeIsEmpty() {
        let snap = snapshot(online: true, ipv4: "1.2.3.4", gateway: "1.2.3.1", interface: "en0")
        XCTAssertTrue(NetworkEventDetector.events(from: snap, to: snap).isEmpty)
    }

    /// Addresses churning while the link is down is noise, not news — only
    /// the offline/online edges themselves may be reported.
    func testOfflinePeriodReportsNoAddressNoise() {
        let old = snapshot(online: true, ipv4: "1.2.3.4")
        let mid = snapshot(online: false, ipv4: nil)
        let new = snapshot(online: true, ipv4: "5.6.7.8", gateway: "5.6.7.1")
        XCTAssertEqual(NetworkEventDetector.events(from: old, to: mid), [.offline(previousInterface: nil)])
        XCTAssertEqual(NetworkEventDetector.events(from: mid, to: new).first, .online(new))
    }

    // MARK: NetworkLog

    private func logLine(_ event: NetworkEvent, snapshot: NetworkSnapshot) -> String {
        NetworkLog.line(for: event, at: Date(timeIntervalSince1970: 0), snapshot: snapshot)
    }

    func testOnlineLineLayout() {
        let snap = snapshot(online: true, ipv4: "192.168.31.100",
                            gateway: "192.168.31.1", interface: "en0", ssid: "Home")
        let line = logLine(.online(snap), snapshot: snap)
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(parts.count, 6)
        XCTAssertEqual(parts[1], "online")
        XCTAssertEqual(parts[2], "interface=en0")
        XCTAssertEqual(parts[3], "ip=192.168.31.100")
        XCTAssertEqual(parts[4], "gateway=192.168.31.1")
        XCTAssertEqual(parts[5], "ssid=Home")
    }

    func testOfflineLineCarriesPreviousOnly() {
        let line = logLine(.offline(previousInterface: "en0"), snapshot: .offline)
        XCTAssertTrue(line.contains("\toffline\t"))
        XCTAssertTrue(line.contains("previous=en0"))
        XCTAssertFalse(line.contains("ip="))
    }

    func testChangedLineCarriesFromAndTo() {
        let snap = snapshot(online: true, ipv4: "5.6.7.8", gateway: "5.6.7.1")
        let line = logLine(.ipv4Changed(old: "1.2.3.4", new: "5.6.7.8"), snapshot: snap)
        XCTAssertTrue(line.contains("ipv4_changed"))
        XCTAssertTrue(line.contains("from=1.2.3.4"))
        XCTAssertTrue(line.contains("to=5.6.7.8"))
    }

    func testNilFactsPrintAsDash() {
        let snap = snapshot(online: true, gateway: "1.2.3.1")
        let line = logLine(.online(snap), snapshot: snap)
        XCTAssertTrue(line.contains("ip=-"))
        XCTAssertTrue(line.contains("ssid=-"))
    }

    func testTimestampIsLocalWallClock() {
        let date = Date(timeIntervalSince1970: 0)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let expected = String(format: "%04d-%02d-%02d %02d:%02d:%02d",
                              c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
        XCTAssertTrue(NetworkLog.timestamp(date).hasPrefix(expected))
    }

    // MARK: NetworkLog.shouldRotate

    func testRotateThreshold() {
        XCTAssertFalse(NetworkLog.shouldRotate(fileSizeBytes: 256 * 1024))
        XCTAssertTrue(NetworkLog.shouldRotate(fileSizeBytes: 256 * 1024 + 1))
    }
}
