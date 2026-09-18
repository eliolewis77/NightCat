import SwiftUI

/// Shared horizontal inset so every row, divider, and the footer line up on the
/// same leading/trailing columns.
let hInset: CGFloat = 14

/// The menu bar popover (panel-mockup §2): status row, tier segments, inline
/// warnings, timer chips, battery + helper rows, footer. Secondary settings
/// live in the Settings window.
struct MenuContent: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TierSegmentRow()

            // Neutral notices first (external takeover / verification / the
            // ordinary error or safety note), strongest slot above the picker
            // so they're read before any decision (mockup §3 variant 2).
            if !state.autoWarningReasons.isEmpty {
                NoticeBanner(text: String(format: NSLocalizedString("自动模式已开启，但当前条件不满足：%@", comment: "auto-mode warning"), state.autoWarningReasons.map { $0.localizedCheckLabel() }.joined(separator: NSLocalizedString("、", comment: "list separator"))),
                             systemImage: "exclamationmark.circle.fill",
                             tint: Color(nsColor: .systemYellow))
            }

            if let notice = state.externalNotice {
                NoticeBanner(text: notice, systemImage: "exclamationmark.triangle.fill",
                             tint: Color(nsColor: .systemYellow))
            }

            if let notice = state.verificationNotice {
                NoticeBanner(text: notice, systemImage: "questionmark.circle.fill",
                             tint: Color(nsColor: .systemYellow))
            }

            if let err = state.lastError {
                NoticeBanner(text: err, systemImage: "info.circle",
                             tint: Color.secondary)
            }

            if state.batteryWarning != nil {
                BatteryWarningBanner()
            }

            TimerSection()

            Divider()
                .padding(.horizontal, hInset)
                .padding(.top, 16)

            BatteryRow()
            HelperRow()
            LocalIPRow()

            if state.panelPurchaseNudgeVisible {
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    Text("喜欢 NightCat？")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    Button("请喝杯咖啡") { state.purchaseNudgeTapped() }
                        .buttonStyle(.link)
                        .font(.system(size: 11.5))
                    Button {
                        state.dismissPurchaseNudge()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("本周不再显示")
                    .accessibilityLabel("关闭购买提示")
                }
                .padding(.horizontal, hInset)
                .padding(.top, 4)
            }

            HStack {
                SettingsButton()
                Spacer()
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("退出", systemImage: "power")
                        .foregroundStyle(.primary.opacity(0.85))
                }
                .keyboardShortcut("q")
            }
            .buttonStyle(.plain)
            .font(.system(size: 12.5))
            .padding(.horizontal, hInset)
            .padding(.vertical, 12)
        }
        .frame(width: 324)
        // The popover is the moment the user actually looks at the toggle, so
        // it's the moment it most needs to be true.
        .onAppear { state.refreshState() }
        // Second confirmation for a switch the mode lock intercepted. The
        // dialog's presence *is* the pending intent: dismissing it any other
        // way (Esc, clicking away) cancels.
        .confirmationDialog(
            lockedSwitchMessage,
            isPresented: Binding(
                get: { state.pendingLockedSwitch != nil },
                set: { if !$0 { state.cancelLockedSwitch() } }
            ),
            titleVisibility: .visible
        ) {
            Button("切换并解除锁定") { state.confirmLockedSwitch() }
            Button("取消", role: .cancel) { state.cancelLockedSwitch() }
        }
    }

    /// SPEC §6's wording, with the target tier's full name in place.
    private var lockedSwitchMessage: String {
        let name = state.pendingLockedSwitch?.displayName ?? ""
        return String(format: NSLocalizedString("档位已锁定。切换到「%@」可能中断正在运行的任务。", comment: "locked switch confirm; tier name"), name)
    }
}

/// The mode lock: lit pins the current tier. Tapping it while locked releases
/// the pin — and drops any switch still awaiting confirmation.
private struct ModeLockButton: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Button {
            state.setModeLocked(!state.isModeLocked)
        } label: {
            Image(systemName: state.isModeLocked ? "lock.fill" : "lock.open")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 27, height: 27)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(state.isModeLocked ? Color.accentColor : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.primary.opacity(0.12))
                        )
                )
                .foregroundColor(state.isModeLocked ? .white : Color(white: 0.55))
        }
        .buttonStyle(.plain)
        .help(state.isModeLocked ? NSLocalizedString("已锁定，点击解锁", comment: "lock help") : NSLocalizedString("锁定当前档位", comment: "lock help"))
        .accessibilityLabel(state.isModeLocked ? NSLocalizedString("档位已锁定", comment: "a11y") : NSLocalizedString("档位未锁定", comment: "a11y"))
    }
}

// MARK: - Tier segments

/// The four-tier segmented picker (mockup §2). Short names; the status row
/// above carries the full name, so segments stay narrow enough for four.
private struct TierSegmentRow: View {
    @EnvironmentObject var state: AppState

    private var autoMode: Bool { state.settings.autoEnableWhenCharging }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 10) {
                Picker("档位", selection: Binding(
                    get: { state.controlMode },
                    set: { state.setControlMode($0) }
                )) {
                    ForEach(KeepAwakeMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                // A locked mode can't be clicked away — the whole point of the
                // lock is that a stray click mustn't change the tier. Selections
                // while locked can only arrive before the disabled view lands.
                .disabled(state.isModeLocked)

                Spacer(minLength: 8)

                ModeLockButton()
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // The caption carries the active tier's one-line explanation —
                // or, when auto mode owns the picker, why the others are dimmed.
                Text(autoMode
                    ? "自动模式仅驱动合盖档。"
                    : state.controlMode.explanation)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                if let countdown = countdownText {
                    Text(countdown)
                        .font(.system(size: 12.5).monospacedDigit())
                        .foregroundStyle(.primary.opacity(0.88))
                } else if !state.keepAwakeDuration.isEmpty {
                    Text(state.keepAwakeDuration)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, hInset)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var countdownText: String? {
        MenubarStyle.countdownText(autoOffRemaining: state.autoOffRemaining)
    }
}

// MARK: - Notices

/// A quiet inline bar for transient explanations (mockup §3): neutral tint,
/// no actions.
private struct NoticeBanner: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label {
            Text(text)
                .font(.system(size: 12.5))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
        }
        .foregroundStyle(.primary.opacity(0.85))
        .padding(.horizontal, hInset)
        .padding(.top, 8)
    }
}

// MARK: - Battery warning banner (SPEC §8)

/// The inline battery warning: the lid tier is requested — or already
/// running — on battery, and the user decides. Continues are never offered
/// for hard refusals (low battery, thermal): those never produce a banner.
private struct BatteryWarningBanner: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var colorScheme

    private var amber: Color { warmAmber(colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("正在使用电池：合盖不睡每小时耗电约 8–12%，散热受限。")
                    .font(.system(size: 12.5))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(amber)
            }
            .foregroundStyle(.primary)

            HStack(spacing: 7) {
                Button("继续") { state.resolveBatteryWarning(.keepLid) }
                    .buttonStyle(.borderedProminent)
                    .tint(amber)
                Button("改用防空闲") { state.resolveBatteryWarning(.useIdle) }
                Button("取消") { state.resolveBatteryWarning(.cancel) }
                Spacer(minLength: 0)
            }
            .controlSize(.small)

            Toggle("本次会话不再提醒",
                   isOn: $state.suppressBatteryWarningThisSession)
                .font(.system(size: 11.5))
                .controlSize(.small)
                .tint(amber)
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(amber.opacity(colorScheme == .dark ? 0.16 : 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(amber.opacity(colorScheme == .dark ? 0.55 : 0.45))
                )
        )
        .padding(.horizontal, hInset)
        .padding(.top, 10)
    }
}

// MARK: - Timer (SPEC §7)

/// Timer chips (mockup §2A): 不限时 / presets / 自定义. Selecting a duration
/// both sets it and (via `keepAwakeFor`) turns keep-awake on when off — one
/// gesture. D8's note under the chips: expiry closes every tier at once.
private struct TimerSection: View {
    @EnvironmentObject var state: AppState
    @State private var isEditingCustom = false
    @State private var customDraft = ""

    private var autoMode: Bool { state.settings.autoEnableWhenCharging }

    private var isPreset: Bool {
        state.autoOffMinutes == 0 || AutoOff.presetMinutes.contains(state.autoOffMinutes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("定时关闭", systemImage: "timer")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.primary.opacity(0.7))

            if isEditingCustom {
                HStack(spacing: 8) {
                    TextField("分钟（1–240）", text: $customDraft)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .onSubmit(applyCustom)
                    Button("好", action: applyCustom)
                        .controlSize(.small)
                    Button("取消") { isEditingCustom = false }
                        .controlSize(.small)
                }
            } else {
                FlowChips(selected: chipSelection) { minutes, label in
                    state.keepAwakeFor(minutes: minutes)
                } custom: {
                    isEditingCustom = true
                    customDraft = isPreset ? "" : String(state.autoOffMinutes)
                }
                .disabled(autoMode)

                if autoMode {
                    Text("自动模式下定时不可用")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, hInset)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    /// `nil` selects nothing (a custom value keeps 自定义 lit via the flag).
    private var chipSelection: Int? {
        isPreset ? state.autoOffMinutes : nil
    }

    private func applyCustom() {
        defer { isEditingCustom = false }
        guard let minutes = Int(customDraft.trimmingCharacters(in: .whitespaces)),
              (1...240).contains(minutes) else { return }
        state.keepAwakeFor(minutes: minutes)
    }
}

/// Chip flow: leading 不限时 chip, preset chips, trailing 自定义, wrapping to
/// as many rows as the panel width needs. The custom chip lights whenever the
/// current value is neither 0 nor a preset.
private struct FlowChips: View {
    let selected: Int?
    let choose: (Int, String) -> Void
    let custom: () -> Void
    @EnvironmentObject private var state: AppState

    private var isCustomActive: Bool {
        state.autoOffMinutes > 0 && !AutoOff.presetMinutes.contains(state.autoOffMinutes)
    }

    var body: some View {
        FlowLayout(spacing: 6) {
            chip(0, NSLocalizedString("不限时", comment: "duration: no limit"))
            ForEach(AutoOff.presetMinutes, id: \.self) { minutes in
                chip(minutes, AutoOff.optionLabel(minutes: minutes))
            }
            customChip()
        }
    }

    private func chip(_ minutes: Int, _ label: String) -> some View {
        Button {
            choose(minutes, label)
        } label: {
            Text(label)
                .font(.system(size: 11.5))
                .padding(.horizontal, 9)
                .padding(.vertical, 3.5)
                .background(
                    Capsule().fill(selected == minutes
                        ? Color.primary.opacity(0.14)
                        : Color.clear)
                )
                .overlay(
                    Capsule().strokeBorder(Color.primary.opacity(0.14))
                )
                .foregroundStyle(selected == minutes
                    ? AnyShapeStyle(Color.primary)
                    : AnyShapeStyle(Color.primary.opacity(0.72)))
        }
        .buttonStyle(.plain)
    }

    private func customChip() -> some View {
        Button(action: custom) {
            Text("自定义")
                .font(.system(size: 11.5))
                .padding(.horizontal, 9)
                .padding(.vertical, 3.5)
                .background(
                    Capsule().fill(isCustomActive
                        ? Color.primary.opacity(0.14)
                        : Color.clear)
                )
                .overlay(
                    Capsule().strokeBorder(Color.primary.opacity(0.14))
                )
                .foregroundStyle(isCustomActive
                    ? AnyShapeStyle(Color.primary)
                    : AnyShapeStyle(Color.primary.opacity(0.72)))
        }
        .buttonStyle(.plain)
    }
}

/// Left-aligned flow layout (macOS 13 `Layout` protocol): fills a row, then
/// wraps to the next. Each child keeps its ideal size — chips never stretch
/// or truncate their own label.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(maxWidth: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(maxWidth: bounds.width, subviews: subviews)
        for (subview, frame) in zip(subviews, arrangement.frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX,
                                      y: bounds.minY + frame.minY),
                          anchor: .topLeading, proposal: .unspecified)
        }
    }

    /// Shared greedy wrap: walk the children, break to a new row whenever the
    /// next chip would cross the available width.
    private func arrange(maxWidth: CGFloat, subviews: Subviews)
        -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        var width: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return (frames, CGSize(width: width, height: y + rowHeight))
    }
}

// MARK: - Battery + helper rows

/// Amber that stays readable in both appearances: bright on the dark panel,
/// deep on the light one — plain yellow on a light popover is unreadable.
private func warmAmber(_ colorScheme: ColorScheme) -> Color {
    colorScheme == .dark
        ? Color(red: 0.988, green: 0.835, blue: 0.098)
        : Color(red: 0.702, green: 0.494, blue: 0.016)
}

/// Power row: source icon + label, thin charge bar, percentage, and the
/// thermal level at the trailing edge (thermal-row-mockup §2 option 1).
/// The bar stays neutral — color is the tier channel, not a battery channel.
/// Temperature color, in contrast, *is* a warning channel: gray while
/// nominal, then the battery amber, the tier orange at the overheat-pause
/// trigger, and alarm red at critical.
private struct BatteryRow: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: state.batteryOnAC ? "bolt.fill" : "battery.75")
                .font(.system(size: 11))
                .foregroundStyle(state.batteryOnAC
                    ? warmAmber(colorScheme)
                    : Color.secondary)
            Text(state.batteryOnAC ? "电源适配器" : "电池")
                .font(.system(size: 12.5))
                .foregroundStyle(.primary.opacity(0.85))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule()
                        .fill(Color.primary.opacity(0.55))
                        .frame(width: geo.size.width * CGFloat(state.batteryPercent) / 100)
                }
            }
            .frame(height: 4)
            Text("\(state.batteryPercent)%")
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundStyle(.primary.opacity(0.75))
            thermalLabel
        }
        .padding(.horizontal, hInset)
        .padding(.top, 10)
    }

    private var thermalLabel: some View {
        let color: Color
        let text: String
        switch state.thermalState {
        case .nominal:   color = Color.primary.opacity(0.65); text = NSLocalizedString("正常", comment: "thermal: nominal")
        case .fair:      color = warmAmber(colorScheme); text = NSLocalizedString("偏热", comment: "thermal: fair")
        case .serious:   color = warmAmber(colorScheme); text = NSLocalizedString("过热", comment: "thermal: serious")
        case .critical:  color = Color(red: 0.898, green: 0.322, blue: 0.290); text = NSLocalizedString("严重过热", comment: "thermal: critical")
        @unknown default: color = Color.primary.opacity(0.65); text = NSLocalizedString("正常", comment: "thermal: nominal")
        }
        return Label(text, systemImage: "thermometer.medium")
            .font(.system(size: 11.5, weight: state.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue ? .semibold : .regular))
            .foregroundStyle(color)
    }
}

/// Helper availability (mockup §2): a quiet green line when installed; when
/// not, an orange line with the install action — the lid tier is unusable
/// without it, so the panel must say so where the tier is picked.
private struct HelperRow: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 9) {
            if state.usingHelper {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(red: 0.365, green: 0.796, blue: 0.647))
                Text("Helper 已安装 · 合盖档可用")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.primary.opacity(0.85))
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.937, green: 0.624, blue: 0.153))
                Text("未安装 Helper · 合盖档不可用")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.primary.opacity(0.85))
                Spacer(minLength: 8)
                Button("安装") { state.installHelper() }
                    .controlSize(.small)
                    .buttonStyle(.link)
            }
        }
        .padding(.horizontal, hInset)
        .padding(.top, 9)
        .padding(.bottom, 6)
    }
}

// MARK: - Footer

/// Opens the Settings window. Neither `SettingsLink` nor `showSettingsWindow:`
/// reliably activates an LSUIElement app (issue #22), so a plain button drives
/// the AppKit-backed `SettingsWindowController` through `AppState`.
private struct SettingsButton: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Button {
            // The popover won't close on its own: SwiftUI's `dismiss()` can't
            // reach it, and an accessory app can't reliably take key away from it.
            MenuBarExtraPanel.dismiss()
            state.showSettings()
        } label: {
            Label("设置", systemImage: "gearshape")
                .foregroundStyle(.primary.opacity(0.85))
        }
        .keyboardShortcut(",", modifiers: .command)
        .buttonStyle(.plain)
    }
}
