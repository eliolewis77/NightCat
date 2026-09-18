import XCTest

/// Attribution for external takeovers (SPEC §9): parse `pmset -g assertions`
/// so a keep-awake held by Amphetamine (or anything else) can be named instead
/// of being presented as NightCat's own doing.
final class AssertionsParsingTests: XCTestCase {

    // MARK: Flat format — current macOS, fixture cut from live `pmset` output

    func testFlatOutputAttributedByInlineAssertionType() {
        let out = """
        2026-09-16 12:30:14 +0800
        Assertion status system-wide:
           BackgroundTask                 0
           UserIsActive                   1
           PreventSystemSleep             0
           PreventUserIdleSystemSleep     1
        Listed by owning process:
           pid 53895(Electron): [0x000955fc000193af] 27:16:40 NoIdleSleepAssertion named: "Electron"
           pid 617(WindowServer): [0x000acb3f0009844e] 00:00:00 UserIsActive named: "com.apple.iohideventsystem.queue.tickle.nxevent service:IOHIDSystem pid:90687 process:UURemoteServer"
        Timeout will fire in 300 secs Action=TimeoutActionRelease
           pid 535(powerd): [0x000a94b80001a170] 03:54:06 PreventUserIdleSystemSleep named: "Powerd - Prevent sleep while display is on"
           pid 79350(Amphetamine): [0x000a94ec0001a18a] 03:53:14 PreventUserIdleSystemSleep named: "Amphetamine (Single-Use - System)"
           pid 79350(Amphetamine): [0x000a953c0005a19a] 03:51:54 PreventUserIdleDisplaySleep named: "Amphetamine (Single-Use - Display)"
           pid 605(coreaudiod): [0x000ab8c100018063] 01:20:21 PreventUserIdleSystemSleep named: "com.apple.audio.AudioTap-48890594-DB72-4999-9448-296F1BC69F69F.context.preventuseridlesleep"
        \tCreated for PID: 48890594.
        \tResources: audio-in 77435E0C-1A82-4ACC-BB7DF7C78192
           pid 90656(UURemote): [0x00079c68000182ef] 72:27:41 PreventUserIdleSystemSleep named: "UURemote Disable Idle System Sleep"
           pid 550(mds): [0x00085273000b939e] 46:17:56 BackgroundTask named: "com.apple.metadata.mds.power"
        Kernel Assertions: 0x104=USB,MAGICWAKE
           id=553  level=255 0x100=MAGICWAKE creat=2026/9/5 23:25 description=en0 owner=IOSkywalkNetworkBSDClient
        """
        XCTAssertEqual(PowerParsers.sleepAssertionHolders(pmsetAssertions: out), [
            AssertionHolder(pid: 535, processName: "powerd"),
            AssertionHolder(pid: 79350, processName: "Amphetamine"),
            AssertionHolder(pid: 605, processName: "coreaudiod"),
            AssertionHolder(pid: 90656, processName: "UURemote"),
        ])
    }

    /// The WindowServer line's quoted text embeds "pid:90687" and a display
    /// assertion — free text must never be mistaken for a holder.
    func testQuotedAssertionNamesAndForeignPidTextAreNotHolders() {
        let out = """
        Listed by owning process:
           pid 617(WindowServer): [0x000acb3f0009844e] 00:00:00 UserIsActive named: "service:IOHIDSystem pid:90687 process:UURemoteServer PreventUserIdleSystemSleep"
        """
        XCTAssertEqual(PowerParsers.sleepAssertionHolders(pmsetAssertions: out), [])
    }

    // MARK: Sectioned format — older `pmset` layouts

    /// A pid line belongs to the nearest section header above it: entries
    /// under a non-sleep section (UserIsActive) must not leak into the sleep
    /// sections listed earlier, and the same pid under two sections yields
    /// two entries.
    func testSectionedOutputAttributedToNearestHeaderAbove() {
        let out = """
        Listed by owning process:
        PreventSystemSleep:
        pid 1205(Amphetamine): [0x00001234] 1:02:11  named: "Amphetamine session"
        pid 431(caffeinate): [0x0000abcd] 0:00:03  named: "user session"
        PreventUserIdleSystemSleep:
        pid 431(caffeinate): [0x0000abce] 0:00:05  named: "user session"
        pid 999(coreaudiod): [0x0000abcf] named: "audio"
        UserIsActive:
        pid 617(WindowServer): [0x0000abd0] 00:00:00 named: "tickle"
        """
        XCTAssertEqual(PowerParsers.sleepAssertionHolders(pmsetAssertions: out), [
            AssertionHolder(pid: 1205, processName: "Amphetamine"),
            AssertionHolder(pid: 431, processName: "caffeinate"),
            AssertionHolder(pid: 431, processName: "caffeinate"),
            AssertionHolder(pid: 999, processName: "coreaudiod"),
        ])
    }

    /// When a line names its assertion type inline, the line wins over the
    /// section it sits in.
    func testInlineTypeWinsOverTheSurroundingSection() {
        let out = """
        UserIsActive:
        pid 1205(Amphetamine): [0x00001234] 1:02:11 PreventSystemSleep named: "session"
        pid 617(WindowServer): [0x0000abd0] 00:00:00 named: "tickle"
        """
        XCTAssertEqual(PowerParsers.sleepAssertionHolders(pmsetAssertions: out), [
            AssertionHolder(pid: 1205, processName: "Amphetamine"),
        ])
    }

    /// The type token can sit before the duration as well as after it.
    func testHandlesTypeTokenBeforeTheDuration() {
        let out = """
        Listed by owning process:
        pid 431(caffeinate): [0x0000abcd] PreventUserIdleSystemSleep 0:00:03  named: "user"
        pid 1205(Amphetamine): [0x00001234] PreventSystemSleep 1:02:11  named: "session"
        """
        XCTAssertEqual(PowerParsers.sleepAssertionHolders(pmsetAssertions: out), [
            AssertionHolder(pid: 431, processName: "caffeinate"),
            AssertionHolder(pid: 1205, processName: "Amphetamine"),
        ])
    }

    /// Display-only assertions keep a Mac's screen on, not the system — they
    /// must not be reported as system sleep prevention.
    func testDisplaySleepAssertionIsNotSystemSleepPrevention() {
        let out = """
        Listed by owning process:
           pid 79350(Amphetamine): [0x000a953c0005a19a] 03:51:54 PreventUserIdleDisplaySleep named: "Amphetamine (Single-Use - Display)"
        """
        XCTAssertEqual(PowerParsers.sleepAssertionHolders(pmsetAssertions: out), [])
    }

    // MARK: Pids belong to the caller

    /// NightCat itself runs `caffeinate -d -w <our pid>`; the parser must hand
    /// it over unfiltered — filtering own processes by pid is the app layer's
    /// job.
    func testReturnsPidsSoCallersCanFilterTheirOwnProcesses() {
        let out = """
        Listed by owning process:
           pid 1234(caffeinate): [0x1] 00:10:00 PreventUserIdleSystemSleep named: "NightCat"
        """
        XCTAssertEqual(PowerParsers.sleepAssertionHolders(pmsetAssertions: out),
                       [AssertionHolder(pid: 1234, processName: "caffeinate")])
    }

    func testSameNamedProcessesStayDistinctByPid() {
        let out = """
        PreventUserIdleSystemSleep:
        pid 100(caffeinate): [0x1] named: "a"
        pid 200(caffeinate): [0x2] named: "b"
        """
        XCTAssertEqual(PowerParsers.sleepAssertionHolders(pmsetAssertions: out), [
            AssertionHolder(pid: 100, processName: "caffeinate"),
            AssertionHolder(pid: 200, processName: "caffeinate"),
        ])
    }

    // MARK: Malformed output — never a crash, never a misattribution

    func testEmptyAndGarbageOutputYieldNoHolders() {
        XCTAssertEqual(PowerParsers.sleepAssertionHolders(pmsetAssertions: ""), [])
        XCTAssertEqual(PowerParsers.sleepAssertionHolders(pmsetAssertions: " Assertion status system-wide:\n\t\n   "), [])
    }

    func testStructurallyBrokenPidLinesAreSkipped() {
        let out = """
        PreventSystemSleep:
        pid (caffeinate): [0x1] named: "no pid digits"
        pid abc(def): [0x1] named: "pid is not a number"
        pid 99999999999(overflow): [0x1] named: "pid beyond Int32"
        pid 431(): [0x1] named: "no process name"
        pid 431(caffeinate) trailing: [0x1] named: "no colon right after the paren"
        something pid 431(caffeinate): [0x1] PreventSystemSleep named: "not line-initial"
        """
        XCTAssertEqual(PowerParsers.sleepAssertionHolders(pmsetAssertions: out), [])
    }

    // MARK: Attribution wording (StateReconciler.externalTakeoverMessage)

    func testSingleHolderIsNamed() {
        XCTAssertEqual(StateReconciler.externalTakeoverMessage(holders: ["Amphetamine"]),
                       "当前由 Amphetamine控制。")
    }

    func testMultipleHoldersJoinWithAnd() {
        XCTAssertEqual(StateReconciler.externalTakeoverMessage(holders: ["Amphetamine", "caffeinate"]),
                       "当前由 Amphetamine 和 caffeinate控制。")
    }

    /// One process commonly holds several assertions (Amphetamine holds a
    /// system one per session); the wording must not repeat it.
    func testDuplicateHolderNamesCollapseKeepingFirstSeenOrder() {
        XCTAssertEqual(StateReconciler.externalTakeoverMessage(holders: ["coreaudiod", "Amphetamine", "coreaudiod"]),
                       "当前由 coreaudiod 和 Amphetamine控制。")
    }

    /// Holders we couldn't name fall back to the existing generic wording —
    /// an empty roster must not be presented as a claim about nobody.
    func testNoHoldersFallBackToTheGenericExternalNotice() {
        XCTAssertEqual(StateReconciler.externalTakeoverMessage(holders: []),
                       ExternalChange.enabledOutside.message)
    }
}
