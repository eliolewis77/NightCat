import SwiftUI

/// Shared horizontal inset so every row, divider, and the footer line up on the
/// same leading/trailing columns.
private let hInset: CGFloat = 14

/// The menu bar popover (panel-mockup §2): status row, tier segments, inline
/// warnings, timer chips, battery + helper rows, footer. Secondary settings
/// live in the Settings window.
struct MenuContent: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StatusRow()

            TierSegmentRow()

            // Neutral notices first (external takeover / verification / the
            // ordinary error or safety note), strongest slot above the picker
            // so they're read before any decision (mockup §3 variant 2).
            if !state.autoWarningReasons.isEmpty {
                NoticeBanner(text: "自动模式已开启，但当前条件不满足：\(state.autoWarningReasons.map { $0.checkLabel }.joined(separator: "、"))。",
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
                .padding(.top, 13)

            BatteryRow()
            HelperRow()

            HStack {
                SettingsButton()
                Spacer()
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("退出 NightCat", systemImage: "power")
                        .foregroundStyle(.secondary)
                }
                .keyboardShortcut("q")
            }
            .buttonStyle(.plain)
            .font(.callout)
            .padding(.horizontal, hInset)
            .padding(.vertical, 10)
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
        return "档位已锁定。切换到「\(name)」可能中断正在运行的任务。"
    }
}

// MARK: - Status row

/// Top row (mockup §2): tier full name in the tier's color, one-line meaning,
/// remaining time in monospaced digits, lock button at the trailing edge.
private struct StatusRow: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var colorScheme

    private var tierColor: Color {
        MenubarStyle.tierColor(state.controlMode, colorScheme: colorScheme)
    }

    private var countdown: String? {
        MenubarStyle.countdownText(mode: state.controlMode,
                                   autoOffRemaining: state.autoOffRemaining)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(state.controlMode.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tierColor)
                Text(state.controlMode.explanation)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let countdown {
                Text(countdown)
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(.primary.opacity(0.85))
            }
            ModeLockButton()
        }
        .padding(.horizontal, hInset)
        .padding(.top, 14)
        .padding(.bottom, 12)
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
        .help(state.isModeLocked ? "已锁定，点击解锁" : "锁定当前档位")
        .accessibilityLabel(state.isModeLocked ? "档位已锁定" : "档位未锁定")
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
            // A locked mode can't be clicked away — the whole point of the
            // lock is that a stray click mustn't change the tier. Selections
            // while locked can only arrive before the disabled view lands.
            .disabled(state.isModeLocked)

            if state.isModeLocked {
                Label("档位已锁定，点击其他档需二次确认 · 重启后自动解锁", systemImage: "lock")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .labelStyle(.titleAndIcon)
            } else if autoMode {
                Text("自动模式开启时不使用常亮与防空闲档——它只驱动合盖档。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, hInset)
        .padding(.bottom, 2)
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
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, hInset)
        .padding(.top, 6)
    }
}

// MARK: - Battery warning banner (SPEC §8)

/// The inline battery warning: the lid tier is requested — or already
/// running — on battery, and the user decides. Continues are never offered
/// for hard refusals (low battery, thermal): those never produce a banner.
private struct BatteryWarningBanner: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("当前使用电池。合盖不睡约每小时耗电 8–12%，且合盖散热受限。")
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color(red: 0.937, green: 0.624, blue: 0.153))
            }
            .foregroundStyle(.primary.opacity(0.85))

            HStack(spacing: 7) {
                Button("继续") { state.resolveBatteryWarning(.keepLid) }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.937, green: 0.624, blue: 0.153))
                Button("改用防空闲") { state.resolveBatteryWarning(.useIdle) }
                Button("取消") { state.resolveBatteryWarning(.cancel) }
                Spacer(minLength: 0)
            }
            .controlSize(.small)

            Toggle("本次会话不再提醒（重启前）",
                   isOn: $state.suppressBatteryWarningThisSession)
                .font(.system(size: 11.5))
                .controlSize(.small)
                .tint(Color(red: 0.937, green: 0.624, blue: 0.153))
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.937, green: 0.624, blue: 0.153).opacity(0.13))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color(red: 0.937, green: 0.624, blue: 0.153).opacity(0.38))
                )
        )
        .padding(.horizontal, hInset)
        .padding(.top, 10)
    }
}

// MARK: - Timer (SPEC §7)

/// Timer chips (mockup §2A): 不限时 / presets / 自定义…. Selecting a duration
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
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

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
                    Text("自动模式开启时不使用定时——由充电状态自动控制。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("到点将直接关闭全部档位，不逐级回落")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, hInset)
        .padding(.top, 11)
        .padding(.bottom, 2)
    }

    /// `nil` selects nothing (a custom value keeps 自定义… lit via the flag).
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

/// Chip row: leading 不限时 chip, preset chips, trailing 自定义…. The custom
/// chip lights whenever the current value is neither 0 nor a preset.
private struct FlowChips: View {
    let selected: Int?
    let choose: (Int, String) -> Void
    let custom: () -> Void
    @EnvironmentObject private var state: AppState

    private var isCustomActive: Bool {
        state.autoOffMinutes > 0 && !AutoOff.presetMinutes.contains(state.autoOffMinutes)
    }

    var body: some View {
        HStack(spacing: 6) {
            chip(0, "不限时")
            ForEach(AutoOff.presetMinutes, id: \.self) { minutes in
                chip(minutes, AutoOff.optionLabel(minutes: minutes))
            }
            customChip()
            Spacer(minLength: 0)
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
                .foregroundStyle(selected == minutes ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func customChip() -> some View {
        Button(action: custom) {
            Text("自定义…")
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
                .foregroundStyle(isCustomActive ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Battery + helper rows

/// Power row (mockup §2): source icon + label, thin charge bar, percentage.
/// The bar stays neutral — color is the tier channel, not a battery channel.
private struct BatteryRow: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: state.batteryOnAC ? "bolt.fill" : "battery.75")
                .font(.system(size: 11))
                .foregroundStyle(state.batteryOnAC
                    ? Color(red: 0.941, green: 0.780, blue: 0.369)   // #F0C75E
                    : Color.secondary)
            Text(state.batteryOnAC ? "电源适配器" : "电池")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, hInset)
        .padding(.top, 10)
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
                Text("特权 Helper 已安装 · 合盖档可用")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.937, green: 0.624, blue: 0.153))
                Text("未安装特权 Helper · 合盖档不可用")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("安装…") { state.installHelper() }
                    .controlSize(.small)
                    .buttonStyle(.link)
            }
        }
        .padding(.horizontal, hInset)
        .padding(.top, 6)
        .padding(.bottom, 4)
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
            Label("设置…", systemImage: "gearshape")
                .foregroundStyle(.secondary)
        }
        .keyboardShortcut(",", modifiers: .command)
        .buttonStyle(.plain)
    }
}
