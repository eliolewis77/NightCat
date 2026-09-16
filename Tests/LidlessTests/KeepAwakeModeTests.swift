import XCTest

final class KeepAwakeModeTests: XCTestCase {

    // MARK: caffeinate mapping

    func testScreenTierRunsDisplayAssertion() {
        XCTAssertEqual(KeepAwakeMode.screen.caffeinateArguments, ["-d"])
    }

    func testPreventIdleTierRunsSystemAssertions() {
        XCTAssertEqual(KeepAwakeMode.preventIdle.caffeinateArguments, ["-i", "-m", "-s"])
    }

    func testOffRunsNoCaffeinate() {
        XCTAssertNil(KeepAwakeMode.off.caffeinateArguments)
    }

    /// `disablesleep 1` already forbids idle sleep, so the lid tier must not
    /// stack a second mechanism on top.
    func testLidClosedRunsNoCaffeinate() {
        XCTAssertNil(KeepAwakeMode.lidClosed.caffeinateArguments)
    }

    // MARK: helper ownership

    func testOnlyLidClosedUsesThePrivilegedHelper() {
        XCTAssertEqual(KeepAwakeMode.allCases.filter(\.usesHelper), [.lidClosed])
    }

    // MARK: tier ladder

    /// Raw values are the ladder order (UI relies on ascending intrusion).
    func testRawValuesAscendByIntrusion() {
        XCTAssertLessThan(KeepAwakeMode.screen.rawValue, KeepAwakeMode.preventIdle.rawValue)
        XCTAssertLessThan(KeepAwakeMode.preventIdle.rawValue, KeepAwakeMode.lidClosed.rawValue)
        XCTAssertEqual(KeepAwakeMode.allCases, [.off, .screen, .preventIdle, .lidClosed])
    }

    func testEveryTierHasALabel() {
        for mode in KeepAwakeMode.allCases {
            XCTAssertFalse(mode.label.isEmpty)
        }
    }
}
