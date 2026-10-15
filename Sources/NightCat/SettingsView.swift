import SwiftUI

/// The Settings window. Holds the secondary controls and the detailed
/// explanations that would clutter the menu bar popover (panel-mockup §2):
/// general preferences, the safety checks, auto mode, background-helper
/// setup, and About.
struct SettingsView: View {
    /// Fixed size of the window this view lives in — the view isn't resizable,
    /// so `SettingsWindowController` sizes the window from the same constant.
    static let preferredSize = CGSize(width: 420, height: 560)

    @EnvironmentObject var state: AppState

    /// Set once the user picks a language, until relaunch applies it.
    @State private var languageChanged = false
    @State private var licenseInputShown = false
    @State private var licenseDraft = ""
    @State private var licenseOutcome: LicenseManager.Outcome?

    var body: some View {
        Form {
            Section("通用") {
                Toggle("登录时启动", isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.setLaunchAtLogin($0) }
                ))
                Picker("语言", selection: Binding(
                    get: { state.appLanguage },
                    set: { code in
                        if code != state.appLanguage {
                            state.setAppLanguage(code)
                            languageChanged = true
                        }
                    }
                )) {
                    Text("跟随系统").tag("auto")
                    Text("简体中文").tag("zh-Hans")
                    Text("English").tag("en")
                }
                Picker("远程熄屏宽限", selection: Binding(
                    get: { state.lidDisplaySleepGraceMinutes },
                    set: { state.setLidDisplaySleepGraceMinutes($0) }
                )) {
                    Text(AutoOff.optionLabel(minutes: 5)).tag(5)
                    Text(AutoOff.optionLabel(minutes: 10)).tag(10)
                    Text(AutoOff.optionLabel(minutes: 15)).tag(15)
                }
                Toggle("启动时恢复合盖档", isOn: Binding(
                    get: { state.settings.restoreLidTierOnLaunch },
                    set: { v in var s = state.settings; s.restoreLidTierOnLaunch = v; state.updateSettings(s) }
                ))
                Button("查看设置指南") { state.showOnboarding() }
                if languageChanged {
                    HStack {
                        Text("重启 NightCat 以应用语言更改。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("立即重启") { state.relaunch() }
                            .controlSize(.small)
                    }
                }
            }

            Section("安全") {
                Toggle("仅插电时保持", isOn: Binding(
                    get: { state.settings.onlyWhileCharging },
                    set: { v in var s = state.settings; s.onlyWhileCharging = v; state.updateSettings(s) }
                ))
                Picker("过热时", selection: Binding(
                    get: { state.settings.thermalPolicy },
                    set: { v in var s = state.settings; s.thermalPolicy = v; state.updateSettings(s) }
                )) {
                    Text("自动暂停").tag(ThermalPolicy.pause)
                    Text("仅通知").tag(ThermalPolicy.notify)
                    Text("忽略").tag(ThermalPolicy.ignore)
                }
                .pickerStyle(.segmented)
                LowBatteryCutoffRow()
            }

            Section("日程") {
                Toggle("按周计划定时开启合盖档", isOn: Binding(
                    get: { state.scheduleEnabled },
                    set: { state.setScheduleEnabled($0) }
                ))
                if state.scheduleEnabled {
                    // The controls share one row; each hint is its own row.
                    // A custom VStack row gets sized to its content's ideal
                    // width, which wrapped the long hints well short of the
                    // card — while bare Text rows (like the helper section's)
                    // always get the full width. Hints are conditional and
                    // rare — a rule that can't fire, a suspension, a missing
                    // helper — never standing prose.
                    ScheduleRuleRow()
                    if state.schedule.crossesMidnight {
                        ScheduleHintRow("窗口跨过午夜，持续到次日凌晨。")
                    }
                    if state.schedule.weekdayMask == 0
                        || state.schedule.startMinute == state.schedule.endMinute {
                        ScheduleHintRow("未选星期或起止相同，日程不会触发。")
                    }
                    if !state.helperInstalled {
                        ScheduleHintRow("未安装 Helper，日程无法自动开启。")
                    }
                    if !state.batteryOnAC {
                        ScheduleHintRow("未接通电源时，系统可能忽略定时唤醒。")
                    }
                }
            }

            Section("网络") {
                NetworkKeepAliveRow()
            }

            Section("后台 Helper") {
                LabeledContent("状态") {
                    HStack(spacing: 6) {
                        Image(systemName: state.usingHelper ? "checkmark.shield.fill" : "exclamationmark.shield")
                            .foregroundStyle(state.usingHelper ? .green : .orange)
                        Text(state.usingHelper ? NSLocalizedString("已启用", comment: "helper status") : NSLocalizedString("未安装", comment: "helper status"))
                            .foregroundStyle(.secondary)
                    }
                }
                if !state.helperInstalled {
                    Text("安装后切换档位不再询问管理员密码，并启用安全看门狗。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button(state.helperNeedsApproval ? NSLocalizedString("前往登录项批准", comment: "button") : NSLocalizedString("安装后台 Helper", comment: "button")) {
                        state.installHelper()
                    }
                }
            }

            Section("关于") {
                HStack(spacing: 12) {
                    if let icon = NSApp.applicationIconImage {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 48, height: 48)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NightCat").font(.headline)
                        Text("版本 \(state.appVersion)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("检查更新") {
                        UpdaterManager.shared.checkForUpdates()
                    }
                    .disabled(!UpdaterManager.shared.canCheckForUpdates)
                }
                if let email = state.licensedEmail {
                    Text("已授权：\(email) · 感谢支持！")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(alignment: .center, spacing: 14) {
                        CatShape()
                            .fill(Color.primary.opacity(0.85))
                            .frame(width: 38, height: 34)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("这只猫不设试用期，功能全开，永不过期。")
                                .font(.callout)
                            Text("如果它陪你跑通过通宵，请它喝杯咖啡吧。")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            HStack {
                                Button("请喝杯咖啡") {
                                    LicenseManager.openPurchasePage()
                                }
                                .controlSize(.small)
                                Button("输入 License…") {
                                    licenseDraft = ""
                                    licenseOutcome = nil
                                    licenseInputShown = true
                                }
                                .controlSize(.small)
                            }
                            // The activation alert closes on click, so the
                            // verdict surfaces here — failure text inside the
                            // alert would never be seen.
                            if let failure = licenseFailureMessage {
                                Text(failure)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
            }
            .alert("输入 License", isPresented: $licenseInputShown) {
                TextField("粘贴购买后收到的 License Key", text: $licenseDraft)
                Button("激活") {
                    Task {
                        // activateLicense itself ignores a second call while
                        // one is in flight (double-tap before dismissal).
                        licenseOutcome = await state.activateLicense(
                            licenseDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
                .disabled(licenseDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("取消", role: .cancel) { }
            } message: {
                Text("粘贴购买后 Gumroad 自动发来的 License Key（首次激活需联网）。")
            }
        }
        .formStyle(.grouped)
        .frame(width: Self.preferredSize.width, height: Self.preferredSize.height)
    }

    /// Failure text for the inline row under the license buttons; `.licensed`
    /// never surfaces (the row switches to 已授权) and `nil` is "not yet tried".
    private var licenseFailureMessage: String? {
        switch licenseOutcome {
        case .invalid:
            NSLocalizedString("License 无效——请检查是否完整粘贴。", comment: "license activation failed")
        case .revoked:
            NSLocalizedString("该 License 已被退款或停用。", comment: "license revoked")
        case .networkFailed:
            NSLocalizedString("无法连接 Gumroad，请检查网络后重试。首次激活需要联网。", comment: "license network failed")
        case .licensed, .none:
            nil
        }
    }
}

/// Low-battery cutoff slider (0–100%, snapping in 5% steps). `0` means
/// 「不限」 — the low-battery check is disabled entirely.
private struct LowBatteryCutoffRow: View {
    @EnvironmentObject var state: AppState

    /// The value shown while dragging. Committing on every step would write
    /// UserDefaults — and, in auto mode, run a reconcile that can reach the
    /// privileged helper — once per 5% of travel, so the commit waits for the
    /// drag to end.
    @State private var dragging: Double?

    private var threshold: Int { state.settings.lowBatteryThreshold }

    /// The committed value, or the in-flight one while a drag is in progress.
    private var shown: Int { Int((dragging ?? Double(threshold)).rounded()) }

    private var value: Binding<Double> {
        Binding(get: { dragging ?? Double(threshold) },
                set: { dragging = $0 })
    }

    /// Commit the dragged value once the drag ends, and only if it actually moved.
    private func commit(editing: Bool) {
        guard !editing, let value = dragging else { return }
        dragging = nil
        var updated = state.settings
        updated.lowBatteryThreshold = Int(value.rounded())
        guard updated != state.settings else { return }
        state.updateSettings(updated)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text("低电量阈值")
                Spacer(minLength: 16)
                Text(shown == 0 ? NSLocalizedString("不限", comment: "threshold: never") : String(format: NSLocalizedString("%lld%%", comment: "percent"), shown))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Slider(value: value,
                   in: 0...100,
                   step: 5,
                   label: { Text("低电量阈值") },
                   minimumValueLabel: { Text("不限").font(.caption2).foregroundStyle(.secondary) },
                   maximumValueLabel: { Text("100%").font(.caption2).foregroundStyle(.secondary) },
                   onEditingChanged: commit)
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

/// Network keep-alive: an on/off switch plus an interval slider (1–30 min,
/// whole minutes). Same commit-on-drag-end contract as `LowBatteryCutoffRow`.
private struct NetworkKeepAliveRow: View {
    @EnvironmentObject var state: AppState

    @State private var dragging: Double?

    private var minutes: Int { state.settings.networkKeepAliveIntervalMinutes }

    /// The committed value, or the in-flight one while a drag is in progress.
    private var shown: Int { Int((dragging ?? Double(minutes)).rounded()) }

    private var value: Binding<Double> {
        Binding(get: { dragging ?? Double(minutes) },
                set: { dragging = $0 })
    }

    private func commit(editing: Bool) {
        guard !editing, let value = dragging else { return }
        dragging = nil
        var updated = state.settings
        updated.networkKeepAliveIntervalMinutes = Int(value.rounded())
        guard updated != state.settings else { return }
        state.updateSettings(updated)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("网络保活", isOn: Binding(
                get: { state.settings.networkKeepAliveEnabled },
                set: { v in var s = state.settings; s.networkKeepAliveEnabled = v; state.updateSettings(s) }
            ))

            if state.settings.networkKeepAliveEnabled {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        Text("保活间隔")
                        Spacer(minLength: 16)
                        Text(String(format: NSLocalizedString("%lld 分钟", comment: "minutes"), shown))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Slider(value: value,
                           in: Double(NetworkKeepAlivePolicy.minutesRange.lowerBound)...Double(NetworkKeepAlivePolicy.minutesRange.upperBound),
                           step: 1,
                           label: { Text("保活间隔") },
                           minimumValueLabel: { Text("1").font(.caption2).foregroundStyle(.secondary) },
                           maximumValueLabel: { Text("30 分钟").font(.caption2).foregroundStyle(.secondary) },
                           onEditingChanged: commit)
                        .labelsHidden()

                    Text("间隔过长可能失去保活效果。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("间隔只影响保活流量，掉线发现速度不受影响。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }
}

/// The schedule's controls, sharing one row: weekday chips and the start/end
/// time pickers. The explanatory hints live in their own rows (see the
/// Section) — this row holds only content whose natural width fits.
private struct ScheduleRuleRow: View {
    @EnvironmentObject var state: AppState

    private var startBinding: Binding<Date> {
        Binding(get: { WeeklySchedule.date(fromMinute: state.schedule.startMinute) },
                set: {
                    var rule = state.schedule
                    rule.startMinute = WeeklySchedule.minute(of: $0)
                    state.setSchedule(rule)
                })
    }

    private var endBinding: Binding<Date> {
        Binding(get: { WeeklySchedule.date(fromMinute: state.schedule.endMinute) },
                set: {
                    var rule = state.schedule
                    rule.endMinute = WeeklySchedule.minute(of: $0)
                    state.setSchedule(rule)
                })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WeekdayChips()
            HStack(spacing: 10) {
                DatePicker("开始时间", selection: startBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .accessibilityLabel(Text("开始时间"))
                Text("至")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                DatePicker("结束时间", selection: endBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .accessibilityLabel(Text("结束时间"))
            }
        }
        .padding(.vertical, 2)
    }
}

/// One hint line as a standalone row. The `minWidth` is load-bearing: the
/// grouped Form sizes its whole column to the widest row *ideal*, which was
/// the DatePicker row (~330pt) — leaving every card short of the window with
/// the long hints wrapping early. Anchoring one row's ideal to the window's
/// full content width widens the column for every row.
private struct ScheduleHintRow: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(minWidth: SettingsView.preferredSize.width - 40, alignment: .leading)
    }
}

/// Weekday multi-select as a row of capsule chips. macOS has no native
/// multi-weekday picker; the capsule row fits the 420pt window on one line
/// and echoes the panel's chip language. Order follows the locale's first
/// weekday; each chip is one bit of `weekdayMask`.
private struct WeekdayChips: View {
    @EnvironmentObject var state: AppState

    private let calendar = Calendar.current

    /// Weekday values (1 = Sunday … 7 = Saturday) in display order.
    private var orderedWeekdays: [Int] {
        let first = calendar.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(orderedWeekdays, id: \.self) { weekday in
                chip(weekday)
            }
        }
    }

    private func chip(_ weekday: Int) -> some View {
        let selected = state.schedule.weekdayMask & WeeklySchedule.mask(forWeekday: weekday) != 0
        return Button {
            var rule = state.schedule
            rule.weekdayMask ^= WeeklySchedule.mask(forWeekday: weekday)
            state.setSchedule(rule)
        } label: {
            Text(calendar.veryShortWeekdaySymbols[weekday - 1])
                .font(.callout)
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05))
                )
                .overlay(
                    Circle().strokeBorder(selected ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.12))
                )
                .foregroundStyle(selected ? Color.accentColor : Color.primary.opacity(0.7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(calendar.shortWeekdaySymbols[weekday - 1])
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
