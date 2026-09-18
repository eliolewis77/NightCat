import XCTest

/// Tests for the helper's identity and the code signing requirement it demands
/// of anything connecting to it.
final class HelperIdentityTests: XCTestCase {

    func testAppBundleIDIsInverseOfLabel() {
        for bundleID in ["com.nghialuong.lidless", "com.nghialuong.lidless.dev"] {
            let label = NightCatHelper.label(appBundleID: bundleID)
            XCTAssertEqual(NightCatHelper.appBundleID(fromLabel: label), bundleID)
        }
    }

    /// The fallback label has to round-trip too — it's what the requirement is
    /// built from when the environment variable is missing, and a wrong answer
    /// there would have the helper demand an app that doesn't exist, locking out
    /// the real one.
    func testAppBundleIDHandlesFallbackLabel() {
        XCTAssertEqual(NightCatHelper.appBundleID(fromLabel: NightCatHelper.fallbackLabel),
                       "com.eliokit.nightcat")
    }

    func testAppBundleIDLeavesUnexpectedLabelAlone() {
        XCTAssertEqual(NightCatHelper.appBundleID(fromLabel: "com.example.thing"),
                       "com.example.thing")
        XCTAssertEqual(NightCatHelper.appBundleID(fromLabel: ""), "")
    }

    /// Each clause closes a hole the other two leave open: identity alone admits
    /// an impostor using the name, the anchor alone admits every Apple-signed
    /// app, the team alone admits anything else we ship.
    func testRequirementPinsIdentityAnchorAndTeam() {
        let requirement = NightCatHelper.codeSigningRequirement(appBundleID: "com.nghialuong.lidless")
        XCTAssertTrue(requirement.contains("identifier \"com.nghialuong.lidless\""))
        XCTAssertTrue(requirement.contains("anchor apple generic"))
        XCTAssertTrue(requirement.contains("certificate leaf[subject.OU] = \"\(NightCatHelper.teamID)\""))
    }

    /// The `.dev` and release builds must not satisfy each other's requirement —
    /// keeping their daemons isolated is the whole point of the separate ids.
    func testRequirementDiffersBetweenDebugAndReleaseIdentifiers() {
        XCTAssertNotEqual(
            NightCatHelper.codeSigningRequirement(appBundleID: "com.nghialuong.lidless"),
            NightCatHelper.codeSigningRequirement(appBundleID: "com.nghialuong.lidless.dev")
        )
    }

    /// A malformed requirement throws an Objective-C exception where it's set,
    /// which in the helper means dying on every incoming connection. Keep it to
    /// one line with nothing stray in it.
    func testRequirementIsASingleNonEmptyLine() {
        let requirement = NightCatHelper.codeSigningRequirement(appBundleID: "com.nghialuong.lidless")
        XCTAssertFalse(requirement.contains("\n"))
        XCTAssertFalse(requirement.isEmpty)
    }

    /// The requirement the daemon builds must match the app that will call it.
    /// These are derived on opposite sides of the XPC boundary from different
    /// inputs — the helper from its launchd label, the app from its bundle id —
    /// so a drift between them locks the app out of its own helper.
    func testRequirementFromLabelMatchesRequirementFromBundleID() {
        for bundleID in ["com.nghialuong.lidless", "com.nghialuong.lidless.dev"] {
            let label = NightCatHelper.label(appBundleID: bundleID)
            XCTAssertEqual(
                NightCatHelper.codeSigningRequirement(appBundleID: NightCatHelper.appBundleID(fromLabel: label)),
                NightCatHelper.codeSigningRequirement(appBundleID: bundleID)
            )
        }
    }
}
