import AppKit
import SwiftUI
import Foundation

@MainActor
final class AppState: ObservableObject {
    /// The active keep-awake tier. `.screen`/`.preventIdle` run an App-layer
    /// caffeinate process; `.lidClosed` owns the privileged `disablesleep`
    /// flag. Everything below that reconciles a Bool (StateReconciler,
    /// verification, auto mode) is scoped to that flag — i.e. to this tier.
    @Published var mode: KeepAwakeMode = .off

    /// The lid tier's flag, as the app believes it.
    var isEnabled: Bool { mode == .lidClosed }

    /// Whether any tier is currently keeping the Mac awake.
    var isActive: Bool { mode != .off }

    /// Session-level mode lock (SPEC §6): while on, a mode *change* by the
    /// user — including to `off`, which is a tier change like any other — is
    /// held for confirmation instead of applied. Exists so a stray click can't
    /// interrupt a batch run mid-flight.
    ///
    /// Deliberately **not persisted**: a lock that survived a relaunch could
    /// pin a forgotten tier on, so a restart always unlocks. No `store.save`
    /// call may ever touch this.
    @Published var isModeLocked = false

    /// The mode switch the lock is currently holding, awaiting the
    /// confirmation dialog. Non-nil only while that dialog is up.
    @Published var pendingLockedSwitch: KeepAwakeMode?

    /// The battery warning banner (SPEC §8): non-nil while the user is
    /// deciding what to do about the lid tier on battery power. Set when the
    /// user asks for the lid tier on battery, or when the charger comes out
    /// from under a running lid tier — never by a silent downgrade.
    @Published var batteryWarning: BatteryWarningContext?

    /// "Don't remind again this session". Session-only by design: a persisted
    /// suppression could quietly make every future battery-lid decision for
    /// the user, which is exactly the silent downgrade SPEC §8 forbids.
    /// No `store.save` call may ever touch this.
    @Published var suppressBatteryWarningThisSession = false

    @Published var helperInstalled = false
    @Published var helperNeedsApproval = false
    @Published var batteryDescription = ""
    /// Current battery charge (0–100) and whether on AC power. Drives the
    /// popover status strip (icon + "Battery 74%").
    @Published var batteryPercent = 0
    @Published var batteryOnAC = false
    @Published var lastError: String?

    /// Explains a toggle that moved by itself. Its own channel, so an external
    /// change and a safety pause can both be on screen at once.
    @Published var externalNotice: String?

    /// Transient status of a write we haven't been able to confirm. Also its own
    /// channel, so clearing it can't disturb `lastError`.
    @Published var verificationNotice: String?

    /// True when using the privileged helper; false when on the M1 admin-prompt fallback.
    @Published var usingHelper = false

    /// User-tunable safety preferences (persisted).
    @Published var settings: SafetySettings = .default

    /// Auto-mode master-toggle intent (persisted): whether the user wants
    /// keep-awake armed. In auto mode the *live* state (`isEnabled`) is derived
    /// from `armed` gated by power + safety — see `reconcile()`. Unused in manual
    /// mode, where the toggle drives `isEnabled` directly; it's (re-)seeded on the
    /// way into auto mode rather than tracked continuously.
    @Published var armed = false

    /// The currently-unmet checks to surface in the popover's auto-mode warning,
    /// or empty when there's nothing to warn about. Non-empty only when auto mode
    /// is on, the feature is armed, but keep-awake isn't live right now.
    var autoWarningReasons: [SafetyReason] {
        guard settings.autoEnableWhenCharging, armed, !isEnabled else { return [] }
        return SafetyEvaluator.allUnmetReasons(battery: currentBattery,
                                               thermalSerious: thermalSerious(),
                                               settings: settings,
                                               requirePower: true)
    }

    /// What the mode picker displays. Auto mode operates the lid tier only,
    /// so the picker collapses to lid-armed/off there; screen and idle are
    /// manual-mode tiers.
    var controlMode: KeepAwakeMode {
        guard settings.autoEnableWhenCharging else { return mode }
        return armed ? .lidClosed : .off
    }

    /// Launch-at-login state (the app itself).
    @Published var launchAtLogin = false

    /// Auto-off timer: minutes after which keep-awake turns itself off
    /// (`0` = never). Persisted.
    @Published var autoOffMinutes = 0
    /// When the active auto-off timer will fire; nil when not counting down.
    @Published var autoOffDeadline: Date?
    /// Human countdown (e.g. `1:05:09`) shown while a timer is active.
    @Published var autoOffRemaining = ""

    /// System thermal pressure, refreshed with the battery sample. Shown in
    /// the panel's battery row so the overheat-pause has a visible cause.
    @Published var thermalState: ProcessInfo.ThermalState = .nominal

    /// When the current lid-tier hold began (`nil` unless the lid tier is
    /// active). Resets when the tier leaves — switching away and back starts
    /// a fresh hold.
    @Published var keepAwakeStartedAt: Date?
    /// Human-readable hold duration (e.g. `已保持 3 小时 12 分钟`), refreshed
    /// by the 30-second tick.
    @Published var keepAwakeDuration = ""

    /// Whether the user has finished first-run onboarding (persisted).
    @Published var onboardingComplete = false

    /// Buyer email once a Gumroad license key has been verified, else `nil`.
    /// Cached locally after the first online activation; background
    /// re-verification only *removes* it on an explicit revoked verdict —
    /// an unreachable Gumroad (offline launch) keeps the license intact.
    @Published var licensedEmail: String?
    @Published private(set) var verifyingLicense = false

    /// In-app language override ("auto" | "zh-Hans" | "en"). Persisted via the
    /// app's `AppleLanguages` default, so it takes effect on next launch —
    /// bundle lookup tables load once at startup. The *selection* itself lives
    /// in a separate `AppLanguageOverride` key: reading `AppleLanguages` back
    /// would hit the system's global domain (always present) and masquerade as
    /// a user choice.
    @Published var appLanguage: String

    /// Online activation of a pasted Gumroad license key.
    func activateLicense(_ key: String) async -> LicenseManager.Outcome {
        verifyingLicense = true
        defer { verifyingLicense = false }
        let outcome = await LicenseManager.verifyOnline(key)
        switch outcome {
        case .licensed(let email):
            UserDefaults.standard.set(key, forKey: "LicenseKey")
            UserDefaults.standard.set(email, forKey: "LicensedEmail")
            licensedEmail = email
        case .revoked:
            UserDefaults.standard.removeObject(forKey: "LicenseKey")
            UserDefaults.standard.removeObject(forKey: "LicensedEmail")
            licensedEmail = nil
        case .invalid, .networkFailed:
            break
        }
        return outcome
    }

    private func reverifyLicense() async {
        guard let key = UserDefaults.standard.string(forKey: "LicenseKey") else { return }
        let outcome = await LicenseManager.verifyOnline(key)
        guard case .revoked = outcome else { return }
        licensedEmail = nil
        UserDefaults.standard.removeObject(forKey: "LicensedEmail")
    }

    func setAppLanguage(_ code: String) {
        appLanguage = code
        let defaults = UserDefaults.standard
        defaults.set(code, forKey: "AppLanguageOverride")
        if code == "auto" {
            defaults.removeObject(forKey: "AppleLanguages")
        } else {
            defaults.set([code], forKey: "AppleLanguages")
        }
    }

    private let helper = HelperManager()
    /// App-layer assertions for the screen / prevent-idle tiers.
    private let caffeinate = CaffeinateManager()
    /// Reads the flag on every path — `pmset -g` needs no privileges — and also
    /// writes it when the helper isn't installed.
    private let power = PowerManager()
    private let battery = BatteryMonitor()
    private let store = SettingsStore()
    private let loginItem = LoginItemManager()
    private lazy var onboarding = OnboardingController(state: self)

    private lazy var settingsWindow = SettingsWindowController(
        contentSize: SettingsView.preferredSize
    ) { [weak self] in
        guard let self else { return AnyView(EmptyView()) }
        return AnyView(
            SettingsView()
                .environmentObject(self)
        )
    }

    /// Marketing version shown in the menu.
    var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
    private var batteryTimer: Timer?
    private var heartbeatTimer: Timer?
    private var autoOffTimer: Timer?

    /// Last-known "helper is usable" value, so we can detect it flipping on at
    /// runtime (right after the user approves it) and prompt a restart.
    private var helperWasUsable = false
    /// True once the system flag has been read successfully this session. Set
    /// only by a read — a write's success reply is a claim, not a reading, and
    /// treating it as one would let an unconfirmed write masquerade as drift.
    private var hasConfirmedState = false
    /// The write currently awaiting confirmation, if any.
    private var pendingVerification: PendingVerification?
    /// Rejects async replies that have been superseded.
    private var sync = StateSync()
    /// True while the onboarding window is open and not yet completed.
    private var onboardingActive = false
    private var didBecomeActiveObserver: NSObjectProtocol?
    /// The value the `SleepDisabled` flag had before our most recent takeover
    /// (SPEC §9). Non-nil means we turned a 0 into a 1 and owe a restore on a
    /// normal exit; nil means the flag was (or was read as) already held, so
    /// restoring is not ours to do.
    private var exitBaseline: ExitRestore.Baseline?
    /// The previous sample's power source, for detecting the charger coming
    /// out — the event that triggers the battery warning under a running lid
    /// tier. Level-triggered checks can't: re-asking every 30-second tick
    /// would nag the user about a decision they just made.
    private var lastBatteryOnAC: Bool?

    init() {
        settings = store.load()
        armed = store.loadArmed()
        autoOffMinutes = store.loadAutoOffMinutes()
        onboardingComplete = store.loadOnboardingComplete()
        appLanguage = UserDefaults.standard.string(forKey: "AppLanguageOverride") ?? "auto"
        licensedEmail = UserDefaults.standard.string(forKey: "LicensedEmail")
        // Quiet background re-verification of the cached license; tolerance
        // for network failure is the point — an offline launch keeps working.
        if UserDefaults.standard.string(forKey: "LicenseKey") != nil {
            Task { await reverifyLicense() }
        }
        launchAtLogin = loginItem.isEnabled
        ExitRestoreBridge.appState = self
        caffeinate.onError = { [weak self] message in self?.lastError = message }
        AppNotifier.requestAuthorizationIfNeeded()
        refreshHelperStatus()
        refreshHelperRegistrationIfUpdated()
        helperWasUsable = usingHelper
        refreshState()
        refreshBattery()
        // Auto mode owns the live state at launch: (re-)activate if armed and
        // conditions allow, or turn it off if a prior session left it on with
        // conditions since lapsed. `refreshState()` above reads the flag
        // synchronously, so `isEnabled` is already the real state to compare
        // against and there's nothing to force.
        //
        // Plainly `reconcile()`, not `reconcileNow()`: adopting the state that
        // read just established may already have dispatched a write, and clearing
        // that claim here would dispatch a second one for the same decision.
        reconcile()
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // Re-check the helper whenever the app comes forward — e.g. when the user
        // returns from approving it in System Settings — so we notice it being
        // enabled without requiring a manual restart.
        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.recheckHelper()
                // Also re-read the flag: it may have been changed from a Terminal
                // the user was just in. `recheckHelper` only refreshes on the rare
                // helper unusable→usable transition.
                self?.refreshState()
            }
        }
        // First launch shows onboarding once (persisted so closing it early won't
        // re-nag). A relaunch triggered mid-onboarding resumes the flow instead.
        if store.loadResumeOnboarding() {
            store.saveResumeOnboarding(false)
            DispatchQueue.main.async { [weak self] in self?.showOnboarding() }
        } else if !onboardingComplete {
            onboardingComplete = true
            store.saveOnboardingComplete(true)
            DispatchQueue.main.async { [weak self] in self?.showOnboarding() }
        }
        // Chain self-check: the launch restore only works if the login item
        // brings the app back after a reboot. Warn once when the user armed
        // the restore but disconnected its first link.
        if settings.restoreLidTierOnLaunch && !launchAtLogin {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                AppNotifier.post(NSLocalizedString(
                    "启动恢复合盖档已开启，但「登录时启动」已关闭——重启后 NightCat 不会自启，合盖机器将无法远程唤醒。",
                    comment: "login item chain warning"))
            }
        }
        // Opt-in launch restore: a restarted Mac with the lid closed would
        // otherwise sit unreachable on the Off tier (disablesleep is cleared by
        // the reboot itself) until someone physically opens the lid. Deferred
        // to the next runloop tick so the UI (and any pending onboarding work)
        // settles before the helper round trip starts.
        if settings.restoreLidTierOnLaunch, mode == .off {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.mode == .off else { return }
                self.setMode(.lidClosed, origin: .user)
            }
        }
    }

    deinit {
        if let didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(didBecomeActiveObserver)
        }
    }

    // MARK: Onboarding

    /// Present the first-run setup window (also reachable from Settings).
    func showOnboarding() {
        onboardingActive = true
        onboarding.show()
    }

    /// Mark onboarding done, persist it, and close the window.
    func completeOnboarding() {
        onboardingActive = false
        onboardingComplete = true
        store.saveOnboardingComplete(true)
        store.saveResumeOnboarding(false)
        onboarding.close()
    }

    // MARK: Settings

    /// Present the Settings window from the menu-bar popover.
    func showSettings() {
        settingsWindow.show()
    }

    func updateSettings(_ new: SafetySettings) {
        let wasAuto = settings.autoEnableWhenCharging
        settings = new
        store.save(new)
        if new.autoEnableWhenCharging {
            if !wasAuto {
                // Opting into auto mode *is* the request to have keep-awake on, so
                // arm it rather than inheriting the current live state — otherwise
                // switching on "Automatically enable when charging" while
                // keep-awake happens to be off (the very case this feature exists
                // for) would visibly do nothing. Also drop any manual auto-off
                // countdown, which would just fight auto mode's own activation.
                armed = true
                store.saveArmed(armed)
                cancelAutoOff()
            }
            reconcileNow()
        } else if let pending = autoWrite.inFlightTarget {
            // Leaving auto mode with a write still travelling. Its target is where
            // the system is heading, so that's what manual mode inherits — but the
            // transition has to own that outcome with a write of its own, or the
            // auto reply lands afterwards and moves the state in a mode the user
            // has already left.
            //
            // Quiet origin deliberately: the user toggled a mode, not the switch,
            // so a modal about keep-awake would be about a write they never asked
            // for. It also can't be `.user` for a second reason — that origin
            // clears `externalNotice`, which this isn't entitled to do.
            //
            // The reply to this write runs `updateAutoOff`, and auto mode is off
            // in `settings` by now, so the countdown arms exactly as manual mode
            // expects.
            refreshBattery()
            let conditions = SafetySnapshot(battery: currentBattery,
                                            thermalSerious: thermalSerious())
            let settled = AutoEnablePolicy.handoffToManual(pendingTarget: pending,
                                                           conditions: conditions,
                                                           settings: settings)
            autoWrite.clear()
            // Same snapshot to decide and to write: whichever way `settled` went,
            // the check on the way out is guaranteed to permit it, so this write
            // always claims a mutation and always supersedes the auto reply.
            setEnabled(settled, note: nil, origin: .auto, conditions: conditions)
        } else {
            // Leaving auto mode hands activation back to the user, so the auto-off
            // countdown becomes applicable again — re-arm it if one is configured
            // and keep-awake is currently on.
            if wasAuto, isEnabled { armAutoOff() }
            evaluateSafety()
        }
    }

    /// The mode picker's set action. In auto mode a lid/off selection maps to
    /// the armed intent; screen and idle aren't auto-mode tiers, so the picker
    /// snaps back (its `get` re-derives from `armed`) and a note explains why.
    ///
    /// Guarded by the session lock: when locked, any selection other than the
    /// currently displayed mode — off included — is parked on
    /// `pendingLockedSwitch` for the confirmation dialog instead of applied.
    /// Background transitions (the timer, safety, adopted external changes)
    /// don't come through here and are never blocked: the lock protects
    /// against *user* mis-clicks, not against the app's own machinery.
    func setControlMode(_ newMode: KeepAwakeMode) {
        if isModeLocked, newMode != controlMode {
            pendingLockedSwitch = newMode
            return
        }
        guard settings.autoEnableWhenCharging else {
            setMode(newMode, origin: .user)
            return
        }
        switch newMode {
        case .lidClosed: setArmed(true)
        case .off:       setArmed(false)
        case .screen, .preventIdle:
            lastError = NSLocalizedString("自动模式开启时不使用常亮与防空闲档——它只驱动合盖档。", comment: "auto mode notice")
        }
    }

    /// Toggle the session lock from the panel's lock button. Unlocking also
    /// drops any switch still awaiting confirmation — with the lock gone there
    /// is nothing left to confirm it against.
    func setModeLocked(_ locked: Bool) {
        isModeLocked = locked
        if !locked { pendingLockedSwitch = nil }
    }

    /// The confirmation dialog's "Switch & Unlock": release the lock and
    /// perform the switch that was held.
    func confirmLockedSwitch() {
        guard let target = pendingLockedSwitch else { return }
        pendingLockedSwitch = nil
        isModeLocked = false
        setControlMode(target)
    }

    /// The confirmation dialog's "Cancel": drop the held switch. The mode —
    /// and the lock — stay exactly as they were.
    func cancelLockedSwitch() {
        pendingLockedSwitch = nil
    }

    /// Set the auto-mode armed intent, persist it, and reconcile the live state.
    private func setArmed(_ on: Bool) {
        armed = on
        store.saveArmed(on)
        reconcileNow()
    }

    /// Auto mode: derive the live keep-awake state from `armed` gated by external
    /// power + safety, flipping only the live state (never the `armed` intent).
    /// When conditions aren't met the feature stays armed and the popover's
    /// warning explains why it isn't currently active.
    ///
    /// The poll's entry point. No-ops when auto mode is off, when the effective
    /// state already matches, or while an earlier write is still outstanding or
    /// has already concluded this turn — see `autoWrite`. `origin: .auto` because
    /// this fires unprompted on the timer and must stay silent.
    func reconcile() { reconcile(userDriven: false) }

    /// Reconcile now on behalf of something the user just did — arming, changing
    /// settings — where waiting for the next tick would read as the control doing
    /// nothing.
    ///
    /// Unlike the poll, this may write over a request still in flight, because
    /// the user has since said something newer. It does *not* simply drop the
    /// claim: dropping it loses the pending target, and the decision is then
    /// taken against a state the system has already left. Disarming while an
    /// "on" write is travelling would compare `false` against a still-`false`
    /// `isEnabled`, conclude there was nothing to do, and leave the earlier write
    /// to land unopposed — turning keep-awake on moments after the user turned it
    /// off. Deciding against the effective state instead yields a corrective
    /// write, which supersedes the old reply and, because the helper serialises,
    /// lands last.
    private func reconcileNow() { reconcile(userDriven: true) }

    /// Derive the live keep-awake state from `armed` gated by external power +
    /// safety, flipping only the live state (never the `armed` intent). When
    /// conditions aren't met the feature stays armed and the popover's warning
    /// explains why it isn't currently active.
    ///
    /// Refreshes the battery cache first so the decision and the warning list the
    /// popover renders from it are read off the same sample.
    private func reconcile(userDriven: Bool) {
        guard settings.autoEnableWhenCharging else { return }
        guard userDriven || autoWrite.mayWrite else { return }
        refreshBattery()
        // One sample, used to decide *and* handed to the write, so the check on
        // the way out can't disagree with the decision that authorised it. A
        // disagreement there would be a refusal, and a refusal claims no mutation
        // — leaving a superseded write in force.
        let conditions = SafetySnapshot(battery: currentBattery,
                                        thermalSerious: thermalSerious())
        let effective = AutoEnablePolicy.effectiveState(pendingTarget: autoWrite.inFlightTarget,
                                                        live: isEnabled)
        // No target means the outstanding write is already heading where we want
        // it to. Leave the claim standing rather than clearing it — clearing
        // would let the next tick dispatch a duplicate alongside a live request.
        guard let target = AutoEnablePolicy.target(armed: armed,
                                                   currentlyEnabled: effective,
                                                   battery: conditions.battery,
                                                   thermalSerious: conditions.thermalSerious,
                                                   settings: settings) else { return }
        autoWrite.issued(target: target)
        setEnabled(target, note: nil, origin: .auto, conditions: conditions)
    }

    /// The claim on auto mode's outstanding write. Held across the helper's async
    /// round trip, so a reply that reads back wrong can't immediately provoke
    /// another write. See `AutoWriteCoordinator`.
    private var autoWrite = AutoWriteCoordinator()

    /// The last-sampled battery state, refreshed by `refreshBattery()`. Shared by
    /// `reconcile()` and `autoWarningReasons` so the two can't disagree.
    private var currentBattery: BatteryInfo {
        BatteryInfo(percent: batteryPercent, onAC: batteryOnAC)
    }

    /// "Keep awake for N minutes" — the whole gesture, in one call.
    ///
    /// Turns keep-awake on when it isn't already, because that is plainly what
    /// asking for fifteen minutes of it means. Making someone flip the switch
    /// first and *then* set a duration is making them do the bookkeeping.
    ///
    /// Note the ordering when it has to enable: the duration is persisted first,
    /// then the write goes out, and the countdown is armed from the write's
    /// confirmation (via `updateAutoOff(for:)`). So if the safety policy refuses
    /// — flat battery, running hot — no timer is left counting down for a state
    /// the Mac never entered.
    func keepAwakeFor(minutes: Int) {
        // Timed runs apply to whatever tier is active; from `off`, the gesture
        // enables the lid tier (the upstream "keep awake" meaning).
        let request = AutoOff.request(minutes: minutes,
                                      anyTierActive: isActive,
                                      autoModeOn: settings.autoEnableWhenCharging)
        guard request != .ignoredInAutoMode else { return }
        autoOffMinutes = minutes
        store.saveAutoOffMinutes(minutes)
        switch request {
        case .ignoredInAutoMode:
            break
        case .cancelTimer:
            cancelAutoOff()
        case .armTimer:
            armAutoOff()
        case .enableThenArmTimer:
            setMode(.lidClosed, origin: .user)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        if let err = loginItem.setEnabled(enabled) {
            lastError = err
            launchAtLogin = loginItem.isEnabled
        } else {
            // status can lag right after register/unregister; trust the action.
            launchAtLogin = enabled
        }
    }

    private func thermalSerious() -> Bool {
        let state = ProcessInfo.processInfo.thermalState
        return state == .serious || state == .critical
    }

    /// Auto-disable keep-awake if current conditions violate the safety policy.
    /// Applies to every tier: a hot Mac or a dying battery is a reason to stop
    /// holding the machine awake however the holding is done.
    func evaluateSafety() {
        guard isActive else { return }
        let info = battery.read()
        if let reason = SafetyEvaluator.reasonToDisable(battery: info,
                                                        thermalSerious: thermalSerious(),
                                                        settings: settings) {
            // Pass the message through so it survives the async helper callback
            // (which would otherwise clear lastError on success).
            setMode(.off, note: reason.localizedMessage(), origin: .safety)
            AppNotifier.post(reason.localizedMessage())
        }
    }

    // MARK: Battery warning (SPEC §8: no silent downgrade on battery)

    /// Whether the lid tier on battery should ask first. Only true for the
    /// case the safety policy *permits*: at/below the low-battery cutoff, hot,
    /// or under "Only while charging", `setEnabled` refuses outright (and
    /// SPEC §8 says there is no "Continue" to offer there) — so this gate
    /// never fires on a case that would be refused two lines later anyway.
    private func shouldWarnOnBattery() -> Bool {
        guard !suppressBatteryWarningThisSession, !currentBattery.onAC else { return false }
        return SafetyEvaluator.reasonToDisable(battery: currentBattery,
                                               thermalSerious: thermalSerious(),
                                               settings: settings) == nil
    }

    /// One of the banner's buttons. See `BatteryWarningChoice` for what each
    /// choice means per context; the banner closes first so a re-trigger
    /// during the switch (e.g. the safety check re-firing) starts clean.
    func resolveBatteryWarning(_ choice: BatteryWarningChoice) {
        let context = batteryWarning
        batteryWarning = nil
        switch choice {
        case .keepLid:
            // Enabling: proceed for real, past this gate only. Power lost:
            // the tier never stopped — confirming is the whole action.
            if context == .enabling {
                setMode(.lidClosed, origin: .user, bypassBatteryWarning: true)
            }
        case .useIdle:
            setMode(.preventIdle, origin: .user)
        case .cancel:
            // Enabling: nothing was turned on; off is where it stays. Power
            // lost: "cancel" is the user declining the battery run, so the
            // tier comes off rather than sitting on until the cutoff.
            if context == .powerLost {
                setMode(.off, note: NSLocalizedString("已关闭——正在使用电池。", comment: "battery cancel"), origin: .safety)
            }
        }
    }

    /// The charger came out from under a running lid tier. Hard policy
    /// violations (cutoff, thermal, "Only while charging") are handled by
    /// `evaluateSafety` on the same tick — those are decisions the user
    /// already made in Settings. Everything else asks (SPEC §8), keeping the
    /// tier running while the banner is up: stopping or downgrading without
    /// asking is precisely what the spec forbids.
    private func handlePowerDisconnected() {
        guard mode == .lidClosed, batteryWarning == nil,
              shouldWarnOnBattery() else { return }
        batteryWarning = .powerLost
    }

    // MARK: Helper lifecycle

    func refreshHelperStatus() {
        helperInstalled = helper.isEnabled
        helperNeedsApproval = helper.requiresApproval
        usingHelper = helperInstalled
    }

    /// The app's current build number (`CFBundleVersion`).
    private var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }

    private func storeCurrentHelperBuild() {
        store.saveLastHelperBuild(currentBuild)
    }

    /// After an app update the helper binary is re-signed and its launchd job can
    /// keep a stale launch record, so the daemon fails to start (EX_CONFIG) and
    /// XPC calls hang — the toggle then silently does nothing. On the first launch
    /// of a new build, probe the registered daemon; only if it's unreachable do we
    /// rebuild its registration (which may require re-approval). Healthy updates
    /// are left untouched, so they don't needlessly prompt for approval.
    private func refreshHelperRegistrationIfUpdated() {
        guard !currentBuild.isEmpty else { return }
        guard store.loadLastHelperBuild() != currentBuild else { return }
        storeCurrentHelperBuild()
        guard helper.isEnabled else { return }
        helper.checkReachable { [weak self] reachable in
            guard let self, !reachable else { return }
            self.repairHelper()
        }
    }

    /// Re-read helper status; if it just became usable (the user approved it while
    /// the app was running), pick up its keep-awake state and prompt a restart so
    /// the app fully switches onto the privileged helper.
    func recheckHelper() {
        let wasUsable = helperWasUsable
        refreshHelperStatus()
        helperWasUsable = usingHelper
        guard !wasUsable, usingHelper else { return }
        refreshState()
        promptRestartAfterHelperEnabled()
    }

    /// Tell the user the helper is now active and offer to relaunch. The privileged
    /// XPC connection is most reliable from a fresh launch, so a restart is the
    /// simplest way to finish setup.
    private func promptRestartAfterHelperEnabled() {
        // If this happened mid-onboarding, resume the flow after the relaunch.
        if onboardingActive { store.saveResumeOnboarding(true) }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("后台 Helper 已启用", comment: "alert title")
        alert.informativeText = NSLocalizedString("重启 NightCat 以完成与后台 Helper 的连接。", comment: "alert body")
        alert.addButton(withTitle: NSLocalizedString("立即重启", comment: "button"))
        alert.addButton(withTitle: NSLocalizedString("稍后", comment: "button"))
        if alert.runModal() == .alertFirstButtonReturn {
            relaunch()
        }
    }

    /// Spawn a fresh instance of the app, then terminate this one.
    func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.terminate(nil)
        }
    }

    func installHelper() {
        // If the daemon is already registered and just awaiting approval, don't
        // re-register (that throws once pending and would swallow the open) —
        // just take the user to Login Items.
        if helper.requiresApproval {
            openLoginItems()
            return
        }
        do {
            try helper.register()
            let wasUsable = helperWasUsable
            refreshHelperStatus()
            helperWasUsable = usingHelper
            if helper.requiresApproval {
                lastError = NSLocalizedString("请在 系统设置 ▸ 登录项 中批准 NightCat。", comment: "helper approval")
                helper.openLoginItemsSettings()
            } else {
                lastError = nil
                // Rare: registered and immediately usable (already approved). Treat
                // it as the same enable transition the approval path would hit.
                if !wasUsable, usingHelper {
                    refreshState()
                    promptRestartAfterHelperEnabled()
                }
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Open System Settings ▸ Login Items so the user can approve the helper.
    /// Kept separate from `installHelper()` so re-registration can never swallow
    /// the open.
    func openLoginItems() {
        lastError = NSLocalizedString("请在 系统设置 ▸ 登录项 中批准 NightCat。", comment: "helper approval")
        helper.openLoginItemsSettings()
        refreshHelperStatus()
    }

    // MARK: State

    /// Read the real `SleepDisabled` flag and bring the UI into step with it.
    ///
    /// Always read directly rather than asking the helper: the XPC reply is a
    /// plain `Bool`, so a `pmset` failure inside the daemon would arrive as a
    /// confident "off". Reading needs no privileges, so there's nothing to gain
    /// by routing it through root — and an unknown stays an unknown.
    func refreshState() {
        let token = sync.beginRead()
        applyObserved(power.isSleepDisabled(), token)
    }

    private func applyObserved(_ observed: Bool?, _ token: StateSync.ReadToken) {
        guard sync.shouldApply(token) else { return }   // superseded by a newer read or a write

        // A write we haven't confirmed owns the interpretation until it resolves:
        // a disagreement here is our own write failing to hold, not somebody
        // else's doing, and mustn't be reported as an external change.
        if let pending = pendingVerification {
            switch StateReconciler.resolve(pending, observed: observed) {
            case .stillUnverified:
                break
            case .confirmed:
                autoWrite.resolved()
                pendingVerification = nil
                verificationNotice = nil
                hasConfirmedState = true
            case .writeMismatch(let actual):
                // Same ordering rule as `applyVerification`: settle the claim
                // before adopting, so the reconcile that adopting triggers can't
                // chase the mismatch with another write in this turn.
                autoWrite.resolved()
                pendingVerification = nil
                verificationNotice = StateReconciler.writeMismatchMessage(actual: actual)
                hasConfirmedState = true
                adoptSystemState(actual)
            }
            return
        }

        switch StateReconciler.reconcile(shown: isEnabled,
                                         hasBaseline: hasConfirmedState,
                                         observed: observed) {
        case .unknown:
            break                                       // keep the last-known state
        case .inSync:
            hasConfirmedState = true                    // no side effects, by construction
        case .adopt(let enabled):
            hasConfirmedState = true
            adoptSystemState(enabled)
        case .drift(let change):
            hasConfirmedState = true
            // The lid tier owns the flag, so a clear underneath an active lid
            // tier is a stolen choice, not a takeover to adopt: session
            // teardown in some remote-desktop tools (UU远程) resets
            // `disablesleep` when the viewer disconnects. Write it back —
            // rate-limited, so a determined writer surfaces as a visible
            // conflict instead of an endless 30-second rewrite loop. A user
            // who wants the tier off clicks the panel (origin .user), which
            // never reaches this path.
            if !change.nowEnabled, mode == .lidClosed {
                restoreClearedFlag()
            } else {
                externalNotice = change.nowEnabled
                    ? StateReconciler.externalTakeoverMessage(holders: externalSleepAssertionHolders())
                    : change.message
                adoptSystemState(change.nowEnabled)
            }
        }
    }

    /// Rate limiting for `restoreClearedFlag`: more than 3 clears inside
    /// 10 minutes means something is actively fighting us, and hammering the
    /// helper every poll would just churn XPC and pmset. Past the threshold the
    /// tier folds to off with an explicit notice — the user must resolve the
    /// conflict (or re-pick the tier) themselves.
    private var externalClearTimes: [Date] = []

    private func restoreClearedFlag() {
        let now = Date()
        externalClearTimes = externalClearTimes.filter { now.timeIntervalSince($0) < 600 }
        externalClearTimes.append(now)
        guard externalClearTimes.count <= 3, helperInstalled else {
            externalNotice = NSLocalizedString("保持唤醒被其他程序反复关闭，已停止自动恢复。请检查远程软件等工具的电源设置。", comment: "restore gave up")
            mode = .off
            caffeinate.apply(mode)
            manageHeartbeat()
            updateAutoOff(for: false)
            AppNotifier.post(NSLocalizedString("保持唤醒被其他程序反复关闭，已停止自动恢复。", comment: "restore gave up"))
            return
        }
        let token = sync.beginMutation()
        helper.setKeepAwake(true) { [weak self] ok, err in
            guard let self, self.sync.shouldApply(token) else { return }
            if ok {
                self.externalNotice = NSLocalizedString("检测到保持唤醒被其他程序关闭，已自动恢复。", comment: "restored")
                self.pendingVerification = PendingVerification(target: true)
                self.verifySetApplied(target: true)
                AppNotifier.post(NSLocalizedString("检测到保持唤醒被其他程序关闭，已自动恢复。", comment: "restored"))
            } else {
                self.externalNotice = String(format: NSLocalizedString("保持唤醒被其他程序关闭，自动恢复失败：%@", comment: "restore failed"), err ?? NSLocalizedString("未知错误", comment: "unknown error"))
                self.mode = .off
                self.caffeinate.apply(self.mode)
                self.manageHeartbeat()
                self.updateAutoOff(for: false)
                AppNotifier.post(NSLocalizedString("保持唤醒被其他程序关闭，自动恢复失败。", comment: "restore failed"))
            }
        }
    }

    /// Sleep-assertion holders other than ourselves, for attributing an
    /// externally-enabled flag (SPEC §9). Our own `caffeinate` shows up in
    /// `pmset -g assertions` holding `PreventUserIdleSystemSleep`, so the
    /// live pid is filtered out before attribution.
    private func externalSleepAssertionHolders() -> [String] {
        guard let out = Shell.capture("/usr/bin/pmset", ["-g", "assertions"]) else { return [] }
        var ownPids: Set<Int32> = []
        if let pid = caffeinate.runningPID { ownPids.insert(pid) }
        return PowerParsers.sleepAssertionHolders(pmsetAssertions: out)
            .filter { !ownPids.contains($0.pid) }
            .map { $0.processName }
    }

    /// Bring `mode` in line with reality *without* touching the flag, running
    /// the side effects `setEnabled` would have run for this state.
    ///
    /// Only ever reached for a real transition — `reconcile` returns `.inSync`
    /// when the values already agree — so the 30-second poll can't re-arm the
    /// auto-off timer or restart the heartbeat on every pass.
    private func adoptSystemState(_ enabled: Bool) {
        // An observed flag *is* the lid tier (ours, adopted; or someone else's,
        // which M4's external-takeover work will attribute). An observed-off
        // while a caffeinate tier is showing must keep that tier — it never
        // owned the flag, so there's nothing to turn off.
        if enabled {
            mode = .lidClosed
            if keepAwakeStartedAt == nil { keepAwakeStartedAt = Date() }
            // This 1 wasn't written by us, so the exit restore isn't ours to
            // issue either (SPEC §9): void any stale baseline rather than
            // clear someone else's session on quit. The crash-path watchdog
            // still covers the case where nobody restores at all.
            exitBaseline = nil
        } else if mode == .lidClosed {
            mode = .off
            keepAwakeStartedAt = nil
        }
        caffeinate.apply(mode)
        sync.beginMutation()            // supersede every read and write still in flight
        manageHeartbeat()
        updateAutoOff(for: mode != .off)
        // Auto mode owns the live state, so route through `reconcile()` rather
        // than the manual safety pass: adopting an outside change must be settled
        // by the same rule that set the state in the first place, or the toggle
        // visibly jumps and then falls back a tick later.
        if settings.autoEnableWhenCharging {
            reconcile()
        } else if enabled {
            evaluateSafety()
        }
    }

    /// Switch the keep-awake tier. `.screen`/`.preventIdle` run or stop the
    /// App-layer caffeinate process; entering or leaving `.lidClosed` routes a
    /// write through the flag machinery, so auto mode's claim, read-back
    /// verification, and the heartbeat all stay consistent. A tier change that
    /// doesn't touch the flag lands immediately.
    ///
    /// SPEC §8: a *user* request for the lid tier on battery (with enough
    /// charge — the hard refusals stay inside `setEnabled`) parks on the
    /// battery warning banner instead of switching. `bypassBatteryWarning` is
    /// set only by the banner's own "Continue", which is the user confirming.
    func setMode(_ newMode: KeepAwakeMode,
                 note: String? = nil,
                 origin: SetOrigin = .user,
                 conditions: SafetySnapshot? = nil,
                 bypassBatteryWarning: Bool = false) {
        guard newMode != mode else { return }
        if newMode == .lidClosed, origin == .user,
           !bypassBatteryWarning, shouldWarnOnBattery() {
            batteryWarning = .enabling
            return
        }
        caffeinate.apply(newMode)
        let target = newMode == .lidClosed
        if target != isEnabled {
            // The flag has to move; the write's success lands the new mode.
            setEnabled(target, note: note, origin: origin,
                       conditions: conditions, landingMode: newMode)
        } else {
            mode = newMode
            lastError = note
        }
    }

    /// Write the `disablesleep` flag (the lid tier's channel). `note` is shown
    /// to the user on a successful change (used when an auto-pause or the
    /// auto-off timer disables it); nil clears any prior message. When `origin`
    /// is `.user` (the user acted on a control), a failure or policy refusal
    /// also pops a blocking alert so it can't go unnoticed; background callers
    /// pass their own origin to stay quiet.
    ///
    /// `landingMode` is the tier the UI lands on when the write concludes —
    /// callers switching tiers pass the tier they're switching *to*, since e.g.
    /// leaving the lid tier writes `false` but must land on that tier, not on
    /// `off`. Defaults to the flag's own Bool semantics (auto mode, the timer,
    /// safety — all of which operate the lid tier).
    ///
    /// `conditions` is the sample a caller already made its decision from. The
    /// safety check below still runs — this is not a bypass — but it runs against
    /// those conditions rather than a fresh reading, so a decision and the write
    /// it authorises can't be judged against different worlds. Callers that have
    /// no decision to be consistent with (the user flipping a control) omit it
    /// and get the fresh reading, which is what they want.
    func setEnabled(_ target: Bool,
                    note: String? = nil,
                    origin: SetOrigin = .user,
                    conditions: SafetySnapshot? = nil,
                    landingMode: KeepAwakeMode? = nil) {
        let land = landingMode ?? (target ? .lidClosed : .off)
        if StateReconciler.clearsExternalNotice(origin) { externalNotice = nil }
        // Any other origin takes the flag away from auto mode: its claim is void
        // and its reply, if one is still in flight, will be rejected as superseded
        // below. Leaving the claim standing would stall auto mode for a tick or
        // two on a reply that is never coming.
        if origin != .auto { autoWrite.clear() }

        // Refuse to enable if it would immediately violate the safety policy.
        // Returns before claiming a mutation, so nothing in flight is disturbed —
        // which is exactly why a caller correcting an outstanding write must pass
        // the conditions it decided from: a refusal here supersedes nothing.
        if target {
            let checked = conditions ?? SafetySnapshot(battery: battery.read(),
                                                       thermalSerious: thermalSerious())
            if let blocker = SafetyEvaluator.reasonToDisable(battery: checked.battery,
                                                             thermalSerious: checked.thermalSerious,
                                                             settings: settings) {
                lastError = blocker.localizedMessage()
                if origin == .user {
                    presentFailureAlert(target: target, message: blocker.localizedBlockedMessage())
                }
                // Nothing was dispatched, so release the claim rather than holding
                // it for a write that never happened.
                if origin == .auto { autoWrite.clear() }
                return
            }
            // About to write 1: snapshot the flag for the exit restore (SPEC
            // §9). `capture` returns nil when it already reads 1 — someone
            // else's session — which also voids any earlier baseline of ours.
            // A failed read captures as false: same value the crash-path
            // watchdog would restore anyway, so it errs no harder than the
            // safety net already does.
            let observed = power.isSleepDisabled()
            exitBaseline = ExitRestore.capture(current: observed ?? false)
        }
        let resultMessage = note

        // A new write supersedes any older one, along with its pending verification.
        pendingVerification = nil
        verificationNotice = nil
        let token = sync.beginMutation()

        if helperInstalled {
            helper.setKeepAwake(target) { [weak self] ok, err in
                guard let self, self.sync.shouldApply(token) else { return }   // superseded write
                if ok {
                    self.mode = land
                    self.lastError = resultMessage
                    self.keepAwakeStartedAt = land == .lidClosed ? Date() : nil
                    self.manageHeartbeat()
                    self.updateAutoOff(for: land != .off)
                    // Deliberately not `hasConfirmedState`: the helper's success
                    // reply is a claim about the flag, not a reading of it.
                    self.pendingVerification = PendingVerification(target: target)
                    self.verifySetApplied(target: target)
                } else {
                    // The helper can fail without a message (e.g. a dropped XPC
                    // reply, or the daemon failing to launch after an update);
                    // surface it instead of letting the toggle silently no-op.
                    let message = err ?? NSLocalizedString("后台 Helper 未响应。", comment: "helper timeout")
                    self.lastError = message
                    if origin == .user { self.presentHelperFailureAlert(message: message) }
                    self.recoverStateAfterFailedWrite()
                }
            }
        } else {
            do {
                try power.setSleepDisabled(target)
                mode = land
                lastError = resultMessage
                keepAwakeStartedAt = land == .lidClosed ? Date() : nil
                updateAutoOff(for: land != .off)
                pendingVerification = PendingVerification(target: target)
                verifySetApplied(target: target)
            } catch {
                lastError = error.localizedDescription
                if origin == .user { presentFailureAlert(target: target, message: error.localizedDescription) }
                recoverStateAfterFailedWrite()
            }
        }
    }

    /// After a write that reported failure we know nothing reliable about the
    /// flag — the write may still have landed. Go re-read it through the normal
    /// reconcile path rather than assigning `isEnabled` directly, so the token,
    /// baseline, and side effects all stay consistent.
    ///
    /// The baseline is dropped first so that read re-establishes it silently: if
    /// the flag did move, that was our own failed write, and blaming an external
    /// actor for it would be plainly wrong.
    private func recoverStateAfterFailedWrite() {
        // Resolve before re-reading: that read can adopt a state and ask auto mode
        // to reconcile, which must not turn into an immediate second attempt at
        // the write that just failed.
        autoWrite.resolved()
        hasConfirmedState = false
        refreshState()
    }

    /// The write reported success — read the flag back to see whether it landed.
    private func verifySetApplied(target: Bool) {
        let token = sync.beginRead()
        let observed = power.isSleepDisabled()
        guard sync.shouldApply(token) else { return }
        applyVerification(StateReconciler.verifyAfterSet(target: target, observed: observed),
                          target: target)
    }

    /// Verification never writes to `lastError`: it keeps its own channel so
    /// clearing a caveat can't wipe a safety note or a helper error.
    private func applyVerification(_ outcome: StateReconciler.VerifyOutcome, target: Bool) {
        // Whatever the outcome, auto mode's write is over. Resolving up front
        // matters most for `.mismatch`, where adopting the contradicting state
        // reconciles again: without this, that reconcile would dispatch a fresh
        // write, whose read-back could mismatch in turn, with no bound but the
        // stack. Deferring costs a tick and cannot loop.
        autoWrite.resolved()
        switch outcome {
        case .verified:
            pendingVerification = nil
            verificationNotice = nil
            hasConfirmedState = true
        case .unverified:
            // Keep `pendingVerification` — the next poll resolves it, and until
            // then the UI says plainly that the state isn't confirmed.
            verificationNotice = StateReconciler.unverifiedMessage(target: target)
        case .mismatch(let actual):
            pendingVerification = nil
            verificationNotice = StateReconciler.writeMismatchMessage(actual: actual)
            hasConfirmedState = true
            adoptSystemState(actual)
        }
    }

    /// Pop a blocking alert when a user-initiated toggle can't be applied, so the
    /// reason is impossible to miss. The inline `lastError` note still persists in
    /// the popover after the alert is dismissed.
    private func presentFailureAlert(target: Bool, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = target ? NSLocalizedString("无法保持 Mac 唤醒", comment: "alert title") : NSLocalizedString("无法关闭保持唤醒", comment: "alert title")
        alert.informativeText = message
        alert.addButton(withTitle: NSLocalizedString("好", comment: "button"))
        alert.runModal()
    }

    /// The helper is registered but didn't respond — almost always a stale
    /// registration after an app update (launchd refuses to launch the new
    /// binary). Offer a one-click reinstall, which re-registers and refreshes
    /// that record.
    private func presentHelperFailureAlert(message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("无法连接后台 Helper", comment: "alert title")
        alert.informativeText = String(format: NSLocalizedString("%@\n\n这通常发生在更新之后，重新安装后台 Helper 即可修复。", comment: "alert body; error detail"), message)
        alert.addButton(withTitle: NSLocalizedString("重新安装 Helper", comment: "button"))
        alert.addButton(withTitle: NSLocalizedString("取消", comment: "button"))
        if alert.runModal() == .alertFirstButtonReturn {
            repairHelper()
        }
    }

    /// Re-register the privileged helper to refresh launchd's record, then report
    /// the outcome. Used both automatically (after a detected app update) and from
    /// the failure alert's "Reinstall Helper" action.
    func repairHelper() {
        helper.reregister { [weak self] error in
            guard let self else { return }
            self.refreshHelperStatus()
            self.storeCurrentHelperBuild()
            if let error {
                self.lastError = error.localizedDescription
            } else if self.helper.requiresApproval {
                self.lastError = NSLocalizedString("请在 系统设置 ▸ 登录项 中批准 NightCat，然后重试切换。", comment: "helper approval")
                self.helper.openLoginItemsSettings()
            } else {
                self.lastError = NSLocalizedString("后台 Helper 已重新安装——请重试切换。", comment: "helper reinstalled")
            }
        }
    }

    // MARK: Heartbeat (keeps the helper watchdog satisfied)

    private func manageHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        guard isEnabled, helperInstalled else { return }
        helper.heartbeat()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.helper.heartbeat() }
        }
    }

    // MARK: Auto-off timer

    /// Arm when keep-awake turns on, cancel when it turns off. A countdown
    /// already running isn't reset: switching between tiers keeps counting the
    /// same keep-awake session.
    private func updateAutoOff(for active: Bool) {
        if active {
            if autoOffTimer == nil { armAutoOff() }
        } else {
            cancelAutoOff()
        }
    }

    private func armAutoOff() {
        cancelAutoOff()
        // Auto mode manages activation on its own; a countdown would disarm the
        // feature out from under it, so auto-off is inert while auto mode is on.
        guard isActive, autoOffMinutes > 0, !settings.autoEnableWhenCharging else { return }
        // The batch-run helper (SPEC §6): only reached once the timer is
        // genuinely armed (past the guard above), so a refused or auto-mode
        // arming never locks anything.
        if settings.autoLockOnTimerStart { isModeLocked = true }
        let deadline = AutoOff.deadline(from: Date(), minutes: autoOffMinutes)
        autoOffDeadline = deadline
        refreshAutoOffRemaining()
        // One repeating timer drives both the countdown label and the firing,
        // and only runs while a timer is actually armed.
        autoOffTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.autoOffTick() }
        }
    }

    private func cancelAutoOff() {
        autoOffTimer?.invalidate()
        autoOffTimer = nil
        autoOffDeadline = nil
        autoOffRemaining = ""
    }

    private func autoOffTick() {
        guard let deadline = autoOffDeadline else { return }
        if AutoOff.isExpired(deadline: deadline, now: Date()) {
            let minutes = autoOffMinutes
            cancelAutoOff()
            // SPEC §7: expiry releases every tier at once — straight to `off`
            // from wherever the countdown ran, never stepping down.
            let landed = AutoOff.modeOnExpiry(from: mode)
            // The run the lock was protecting is over; leave it on and the
            // picker would sit disabled at Off, demanding a confirmation whose
            // "may interrupt running tasks" caveat is no longer true.
            setModeLocked(false)
            setMode(landed,
                    note: String(format: NSLocalizedString("定时已到：已按 %@ 自动关闭。", comment: "timer expiry; duration"), AutoOff.optionLabel(minutes: minutes)),
                    origin: .autoOff)
            AppNotifier.post(NSLocalizedString("定时已到，保持唤醒已关闭。", comment: "timer expiry"))
        } else {
            refreshAutoOffRemaining()
        }
    }

    private func refreshAutoOffRemaining() {
        guard let deadline = autoOffDeadline else { autoOffRemaining = ""; return }
        autoOffRemaining = AutoOff.formatCountdown(AutoOff.remaining(deadline: deadline, now: Date()))
    }

    // MARK: Battery + safety guard

    func tick() {
        // Backstop for the didBecomeActive observer: catch a helper approval even
        // if the app never lost/regained active state.
        recheckHelper()
        // Advance auto mode's write claim. A concluded write reopens here — this
        // is where its retry comes from. One still outstanding does not: this tick
        // may be landing moments after the dispatch, and reopening would put a
        // second write alongside a live first. It reopens a tick later instead,
        // which also bounds how long a lost reply can hold the feature.
        autoWrite.advanceTick()
        // Reconcile with the real flag every tick, not only while enabled:
        // polling only when we think it's on would structurally miss the case
        // where it was turned on behind our back.
        refreshState()
        if settings.autoEnableWhenCharging {
            reconcile()             // refreshes the battery sample itself
        } else {
            refreshBattery()
            evaluateSafety()
        }
        updateThermalNotification()
        refreshKeepAwakeDuration()
    }

    /// Minute-granularity hold duration for the panel. Only the lid tier
    /// counts: screen/idle tiers don't write system state, so "how long has
    /// this been held" doesn't apply to them the same way.
    private func refreshKeepAwakeDuration() {
        guard let start = keepAwakeStartedAt else {
            keepAwakeDuration = ""
            return
        }
        let minutes = max(1, Int(Date().timeIntervalSince(start) / 60))
        keepAwakeDuration = minutes < 60
            ? String(format: NSLocalizedString("已保持 %lld 分钟", comment: "hold duration"),
                     minutes)
            : String(format: NSLocalizedString("已保持 %lld 小时 %lld 分钟", comment: "hold duration"),
                     minutes / 60, minutes % 60)
    }

    /// One-shot hot Mac notification under the notify-only policy: fires on the
    /// transition into serious and re-arms once the Mac cools down, so a
    /// sustained hot spell produces exactly one banner, not one every 30s.
    private var thermalNotifyShown = false
    private func updateThermalNotification() {
        let hot = thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
        if hot {
            if settings.thermalPolicy == .notify, !thermalNotifyShown {
                thermalNotifyShown = true
                AppNotifier.post(NSLocalizedString("Mac 正在过热，请留意散热。", comment: "notify-only thermal"))
            }
        } else {
            thermalNotifyShown = false
        }
    }

    func refreshBattery() {
        let info = battery.read()
        let wasOnAC = lastBatteryOnAC
        batteryPercent = info.percent
        batteryOnAC = info.onAC
        batteryDescription = "\(info.source) · \(info.percent)%"
        lastBatteryOnAC = info.onAC
        thermalState = ProcessInfo.processInfo.thermalState
        if let wasOnAC, wasOnAC, !info.onAC {
            handlePowerDisconnected()
        }
    }

    // MARK: Exit restoration (SPEC §9)

    /// Called from `applicationShouldTerminate` on a normal quit. Puts the
    /// flag back to the pre-takeover baseline — only when the lid tier is
    /// live *and* we own the takeover (a baseline exists). An externally-held
    /// flag (baseline nil) is left alone, and an off flag needs no write.
    ///
    /// Crash paths never reach this: the helper's 90-second watchdog writes 0
    /// there, and that unconditional net is deliberately untouched.
    func restoreOnExit() -> NSApplication.TerminateReply {
        // Dies with us anyway via `-w <pid>`; stopping it first keeps the exit
        // tidy and keeps it out of any last assertion listing.
        caffeinate.stop()
        guard isEnabled, exitBaseline != nil else { return .terminateNow }
        let value = ExitRestore.restoreValue(of: exitBaseline)
        if helperInstalled {
            helper.setKeepAwake(value) { _, _ in
                NSApp.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
        // Fallback path: the admin prompt may appear (same as every other
        // write without the helper); cancelling it just leaves the flag as-is,
        // and the worst case equals the crash path's delayed 0.
        do { try power.setSleepDisabled(value) } catch { }
        return .terminateNow
    }
}
