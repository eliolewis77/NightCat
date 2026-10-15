import SwiftUI

/// Shared horizontal inset so every row, divider, and the footer line up on the
/// same leading/trailing columns.
let hInset: CGFloat = 16

/// The panel's type scale. Sizes live here and nowhere else, so retuning the
/// panel's typography is one edit; call sites chain `.weight(_)` or
/// `.monospacedDigit()` when a row needs a variant. The one-off icon glyphs
/// (lock badge, close mark, copy mark) are icon sizing, not text, and keep
/// their literals.
enum PanelFont {
    /// The status-header countdown — the one number worth reading first.
    static let headline = Font.system(size: 17, weight: .semibold)
    /// Footer actions and the battery warning's body.
    static let body = Font.system(size: 12.5)
    /// Status rows, chips, notices — the panel's running text.
    static let footnote = Font.system(size: 11.5)
    /// The smallest text and the leading row icons.
    static let micro = Font.system(size: 11)
}

/// The menu bar popover (panel-redesign §A): status header, inline warnings,
/// tier segments, timer chips, power + helper rows, footer. Secondary settings
/// live in the Settings window.
struct MenuContent: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The headline. Someone opening the menu bar is asking one question
            // — what is it doing right now, and for how much longer — so the
            // answer leads, in the tier's own color.
            StatusHeader()

            TierSegmentRow()

            // The battery warning sits directly under the picker: it is an
            // answer to the switch just made, so it belongs beside the control
            // that raised it rather than further down the column.
            if state.batteryWarning != nil {
                BatteryWarningBanner()
            }

            TimerSection()

            ScheduleStatusRow()

            Divider()
                .padding(.horizontal, hInset)
                .padding(.top, 13)

            // One group, tight leading: power, helper, network. All three are
            // read-only facts about this Mac, so they share a rhythm instead of
            // each claiming a full row of the panel's attention.
            VStack(alignment: .leading, spacing: 7) {
                BatteryRow()
                DisplaySleepBlockerRow()
                HelperRow()
                NetworkStatusRow()
                LocalIPRow()
            }
            .padding(.horizontal, hInset)
            .padding(.top, 10)
            .padding(.bottom, 4)

            // Neutral notices (external takeover / verification / the ordinary
            // error or safety note) sit at the panel's quiet end now. Above the
            // picker they turned the panel's cleanest band into a wall of small
            // print — the status header is meant to be read first, and alone.
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

            if state.panelPurchaseNudgeVisible {
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    Text("喜欢 NightCat？")
                        .font(PanelFont.micro)
                        .foregroundStyle(.secondary)
                    Button("请喝杯咖啡") { state.purchaseNudgeTapped() }
                        .buttonStyle(.link)
                        .font(PanelFont.micro)
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
                .padding(.top, 6)
            }

            HStack {
                SettingsButton()
                Spacer()
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("退出", systemImage: "power")
                        .foregroundStyle(.primary.opacity(0.85))
                        // Inner padding so the hover pill has breathing room
                        // around the label; the row's outer vertical padding
                        // shrinks by the same amount to keep its height.
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                }
                .keyboardShortcut("q")
                .hoverHighlight(in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .font(PanelFont.body)
            .padding(.horizontal, hInset)
            .padding(.vertical, 6.5)
        }
        .frame(width: 324)
        // The popover is the moment the user actually looks at the toggle, so
        // it's the moment it most needs to be true. The support row re-evaluates
        // here too — it would otherwise lag the 30-second tick by up to one
        // panel-open.
        .onAppear {
            state.refreshState()
            state.updatePurchaseNudge()
        }
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

// MARK: - Status header

/// The panel's headline (panel-redesign §A): the tier mark on the left, and —
/// when a countdown is running — how long is left at the trailing edge.
///
/// No tier name, no caption. The mark's color is the tier, and the segments
/// directly below spell out which one is lit; naming it again here only made
/// the header something to read.
private struct StatusHeader: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color { tierAccent(state.mode, colorScheme) }

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            mark

            Spacer(minLength: 8)

            trailing
        }
        .padding(.horizontal, hInset)
        .padding(.vertical, 11)
        .background(accent.opacity(colorScheme == .dark ? 0.10 : 0.085))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(accent.opacity(colorScheme == .dark ? 0.22 : 0.18))
                .frame(height: 1)
        }
    }

    /// The cat-head mark, echoing the app icon and the menu bar indicator. The
    /// lock badge appears only while the tier is pinned — same corner as the
    /// menu bar mark, so the two read as the same object seen twice.
    private var mark: some View {
        CatShape()
            .fill(accent)
            .frame(width: 26, height: 23)
            .overlay(alignment: .bottomTrailing) {
                if state.isModeLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 6.5, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 13, height: 13)
                        .background(Circle().fill(accent))
                        .offset(x: 3, y: 2)
                }
            }
            .frame(width: 26, height: 26)
            .accessibilityHidden(true)
    }

    /// Countdown when a timer is armed; otherwise how long this hold has been
    /// running (`lidClosed` only — a tier that doesn't write system state has
    /// no "how long" worth tracking). Nothing at all when every tier is off.
    @ViewBuilder
    private var trailing: some View {
        if let countdown = MenubarStyle.countdownText(autoOffRemaining: state.autoOffRemaining) {
            Text(countdown)
                .font(PanelFont.headline)
                .monospacedDigit()
                .foregroundStyle(accent)
        } else if !state.keepAwakeDuration.isEmpty {
            Text(state.keepAwakeDuration)
                .font(PanelFont.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// The tier color as panel text. Dark appearance reuses the menu bar's own
/// value; light appearance deepens the two bright tiers, which are tuned
/// against a translucent menu bar and would otherwise land at unreadable
/// contrast on the popover's light background.
private func tierAccent(_ mode: KeepAwakeMode, _ scheme: ColorScheme) -> Color {
    guard scheme == .light else { return MenubarStyle.tierColor(mode, colorScheme: .dark) }
    switch mode {
    case .off:         return Color(red: 0.435, green: 0.427, blue: 0.388)   // #6F6D63
    case .screen:      return Color(red: 0.184, green: 0.431, blue: 0.671)   // #2F6EAB
    case .preventIdle: return Color(red: 0.118, green: 0.498, blue: 0.388)   // #1E7F63
    case .lidClosed:   return Color(red: 0.702, green: 0.416, blue: 0.000)   // #B36A00
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

/// The four-tier segmented picker (panel-redesign §A). The tier's full name and
/// its explanation now live in the status header above, so this row is just the
/// control: segments on the left, the lock at its trailing edge where the two
/// read as one group.
private struct TierSegmentRow: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Picker("档位", selection: Binding(
                get: { state.mode },
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
            // `disabled` alone is easy to miss at this size; dimming the row
            // makes "pinned" legible at a glance, with the lock button staying
            // solid so the state keeps one obvious undo.
            .opacity(state.isModeLocked ? 0.55 : 1)

            Spacer(minLength: 8)

            ModeLockButton()
        }
        .padding(.horizontal, hInset)
        .padding(.top, 11)
    }
}

// MARK: - Notices

/// A quiet inline bar for the panel's tail (mockup §3): neutral tint, no
/// actions. Sized down to match the status rows it now sits among, so a notice
/// reads as a footnote rather than a headline.
private struct NoticeBanner: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label {
            Text(text)
                .font(PanelFont.footnote)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .font(PanelFont.micro)
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
    @Environment(\.colorScheme) private var colorScheme

    private var amber: Color { warmAmber(colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("正在使用电池：合盖不睡每小时耗电约 8–12%，散热受限。")
                    .font(PanelFont.body)
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
                .font(PanelFont.footnote)
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

/// Timer chips (panel-redesign §A): preset chips plus 自定义, with 不限时
/// demoted to the row's trailing clear action. Selecting a duration both sets
/// it and (via `keepAwakeFor`) turns keep-awake on when off — one gesture.
/// D8's note under the chips: expiry closes every tier at once.
private struct TimerSection: View {
    @EnvironmentObject var state: AppState
    @State private var isEditingCustom = false
    @State private var customDraft = ""

    private var isPreset: Bool {
        state.autoOffMinutes == 0 || AutoOff.presetMinutes.contains(state.autoOffMinutes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Label("定时关闭", systemImage: "timer")
                    .font(PanelFont.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 8)

                // "No limit" is the absence of a timer, not a fourth preset —
                // as a chip it sat in the same row as the values people actually
                // pick and read as one of them. Here it's the clear action, and
                // a plain label once there is nothing left to clear.
                if state.autoOffMinutes > 0 {
                    Button("不限时") { state.keepAwakeFor(minutes: 0) }
                        .buttonStyle(.plain)
                        .font(PanelFont.footnote)
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .hoverHighlight(in: Capsule())
                } else {
                    Text("不限时")
                        .font(PanelFont.footnote)
                        .foregroundStyle(.tertiary)
                }
            }

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

            }
        }
        .padding(.horizontal, hInset)
        .padding(.top, 12)
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

/// Chip flow: preset chips plus a trailing 自定义, wrapping to as many rows as
/// the panel width needs. The custom chip lights whenever the current value is
/// neither 0 nor a preset.
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
            ForEach(AutoOff.presetMinutes, id: \.self) { minutes in
                chip(minutes, AutoOff.optionLabel(minutes: minutes))
            }
            customChip()
        }
    }

    /// The chip face both kinds share: label in a capsule that fills when
    /// lit. Presets and 自定义 differ only in label, lit state, and action.
    private func chipFace(_ label: String, lit: Bool) -> some View {
        Text(label)
            .font(PanelFont.footnote)
            .padding(.horizontal, 9)
            .padding(.vertical, 3.5)
            .background(
                Capsule().fill(lit ? Color.primary.opacity(0.14) : Color.clear)
            )
            .overlay(
                Capsule().strokeBorder(Color.primary.opacity(0.14))
            )
            .foregroundStyle(lit
                ? AnyShapeStyle(Color.primary)
                : AnyShapeStyle(Color.primary.opacity(0.72)))
    }

    private func chip(_ minutes: Int, _ label: String) -> some View {
        Button {
            choose(minutes, label)
        } label: {
            chipFace(label, lit: selected == minutes)
        }
        .buttonStyle(.plain)
        .hoverHighlight(in: Capsule(), opacity: 0.06)
    }

    private func customChip() -> some View {
        Button(action: custom) {
            chipFace("自定义", lit: isCustomActive)
        }
        .buttonStyle(.plain)
        .hoverHighlight(in: Capsule(), opacity: 0.06)
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

// MARK: - Schedule status

/// The weekly schedule's one-line status: holding / inside the window /
/// waiting for the next one. It lives with the timer section — both answer
/// "what does the app plan to do with the tier" — not with the about-this-Mac
/// rows below the divider. Hidden unless the feature is on and has something
/// to say.
private struct ScheduleStatusRow: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if state.scheduleEnabled,
           !state.scheduleStatusText.isEmpty {
            Label(state.scheduleStatusText, systemImage: "calendar.badge.clock")
                .font(PanelFont.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, hInset)
                .padding(.top, 8)
        }
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

/// Power row: source icon, thin charge bar, percentage, and the thermal level
/// at the trailing edge (thermal-row-mockup §2 option 1). The bar stays
/// neutral — color is the tier channel, not a battery channel. Temperature
/// color, in contrast, *is* a warning channel: gray while nominal, then the
/// battery amber, the tier orange at the overheat-pause trigger, and alarm
/// red at critical.
private struct BatteryRow: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: state.batteryOnAC ? "bolt.fill" : "battery.75")
                .font(PanelFont.micro)
                .foregroundStyle(state.batteryOnAC
                    ? warmAmber(colorScheme)
                    : Color.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule()
                        .fill(Color.primary.opacity(0.55))
                        .frame(width: geo.size.width * CGFloat(state.batteryPercent) / 100)
                }
            }
            .frame(height: 3.5)
            Text("\(state.batteryPercent)%")
                .font(PanelFont.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
            thermalLabel
        }
        .help(rowHelp)
        // One sentence for VoiceOver. The row's four visual pieces — source
        // icon, charge bar, percent, thermometer — would otherwise be read
        // as fragments one by one.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
    }

    /// Always visible, nominal included: "normal" is a reading the user asked
    /// for by having the row at all, and hiding it made the row's width — and
    /// the bar's — jump every time the Mac warmed up or cooled down.
    /// Shared by the visible thermometer label and the VoiceOver sentence.
    private var thermalText: String {
        switch state.thermalState {
        case .fair:     NSLocalizedString("偏热", comment: "thermal: fair")
        case .serious:  NSLocalizedString("过热", comment: "thermal: serious")
        case .critical: NSLocalizedString("严重过热", comment: "thermal: critical")
        default:        NSLocalizedString("正常", comment: "thermal: nominal")
        }
    }

    private var thermalLabel: some View {
        let color: Color
        switch state.thermalState {
        case .fair:     color = warmAmber(colorScheme)
        case .serious:  color = warmAmber(colorScheme)
        case .critical: color = Color(red: 0.898, green: 0.322, blue: 0.290)
        default:        color = Color.secondary
        }
        return Label(thermalText, systemImage: "thermometer.medium")
            .font(PanelFont.footnote.weight(state.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue ? .semibold : .regular))
            .foregroundStyle(color)
    }

    /// Source, charge, and temperature in one breath — and nothing about the
    /// bar, which is decoration.
    private var a11yLabel: String {
        let source = state.batteryOnAC
            ? NSLocalizedString("已接通电源", comment: "a11y: on AC")
            : NSLocalizedString("使用电池", comment: "a11y: on battery")
        let charge = String(format: NSLocalizedString("电量 %lld%%", comment: "a11y: charge"), state.batteryPercent)
        let thermal = String(format: NSLocalizedString("温度%@", comment: "a11y: thermal"), thermalText)
        return [source, charge, thermal].joined(separator: NSLocalizedString("，", comment: "list separator"))
    }

    /// The source name lives here instead of on the row, so the bar keeps the
    /// width the label used to cost.
    private var rowHelp: String {
        state.batteryOnAC
            ? NSLocalizedString("电源适配器", comment: "power source tooltip")
            : NSLocalizedString("电池", comment: "power source tooltip")
    }
}

/// Helper availability (panel-redesign §A): a quiet green line when installed;
/// when not, an orange line with the install action — the lid tier is unusable
/// without it, so the panel must say so where the tier is picked.
private struct HelperRow: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 9) {
            if state.usingHelper {
                Image(systemName: "checkmark")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color(red: 0.365, green: 0.796, blue: 0.647))
                    .accessibilityHidden(true)
                Text("Helper 已安装 · 合盖档可用")
                    .font(PanelFont.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(PanelFont.micro)
                    .foregroundStyle(Color(red: 0.937, green: 0.624, blue: 0.153))
                    .accessibilityHidden(true)
                Text("未安装 Helper · 合盖档不可用")
                    .font(PanelFont.footnote)
                    .foregroundStyle(.primary.opacity(0.85))
                Spacer(minLength: 8)
                Button("安装") { state.installHelper() }
                    .controlSize(.small)
                    .buttonStyle(.link)
            }
        }
    }
}

// MARK: - Footer

/// Network reachability (network-keepalive §monitor): what the link looks
/// like right now, so a remote user glancing at the panel knows the machine
/// is online and over what. Unknown (no sample yet) shows nothing — silence
/// beats a false alarm during the first second of a panel's life.
private struct NetworkStatusRow: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        switch state.networkStatus {
        case nil:
            EmptyView()
        case .some(let status):
            if status.online, status.interfaceKind == .wifi, status.ssid == nil {
                // Online Wi-Fi with no name to show: the IP row below already
                // says "online", and a bare "Wi-Fi" says nothing the user
                // didn't know. Wired/other keep their row — there "online" is
                // the whole message.
                EmptyView()
            } else {
                HStack(spacing: 9) {
                    if status.online {
                        Image(systemName: status.interfaceKind == .wired ? "cable.connector" : "wifi")
                            .font(PanelFont.micro)
                            .foregroundStyle(Color.secondary)
                            .accessibilityHidden(true)
                        Text(label(for: status))
                            .font(PanelFont.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(PanelFont.micro)
                            .foregroundStyle(Color(red: 0.937, green: 0.624, blue: 0.153))
                            .accessibilityHidden(true)
                        Text("未连接网络")
                            .font(PanelFont.footnote)
                            .foregroundStyle(.primary.opacity(0.85))
                    }
                }
                .help(tooltip(for: status))
            }
        }
    }

    /// The interface name ("en0") is useful on hover, meaningless in the row —
    /// an empty help shows no bubble at all.
    private func tooltip(for status: NetworkSnapshot) -> String {
        guard status.online, let name = status.interfaceName else { return "" }
        return String(format: NSLocalizedString("网络接口：%@", comment: "network row tooltip"), name)
    }

    /// SSID when macOS hands it over; otherwise just "Wi-Fi" — the interface
    /// name is developer vocabulary, it lives in the tooltip instead.
    private func label(for status: NetworkSnapshot) -> String {
        switch status.interfaceKind {
        case .wifi:
            if let ssid = status.ssid {
                return String(format: NSLocalizedString("Wi-Fi · %@", comment: "network row; ssid"), ssid)
            }
            return NSLocalizedString("Wi-Fi", comment: "network row")
        case .wired:
            return NSLocalizedString("有线网络", comment: "network row; wired")
        default:
            return NSLocalizedString("已连接", comment: "network row; connected")
        }
    }
}


/// Names whoever is holding the display awake (remote tools commonly hold
/// this assertion around the clock). The usual answer to「合盖了怎么还
/// 亮着」— only present when something actually blocks display sleep.
private struct DisplaySleepBlockerRow: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if !state.displaySleepBlocker.isEmpty {
            HStack(spacing: 9) {
                Image(systemName: "moon.zzz.fill")
                    .font(PanelFont.micro)
                    .foregroundStyle(warmAmber(colorScheme))
                    .accessibilityHidden(true)
                Text(String(format: NSLocalizedString("熄屏被 %@ 阻止", comment: "display sleep blocker row"),
                            state.displaySleepBlocker))
                    .font(PanelFont.footnote)
                    .foregroundStyle(.secondary)
            }
        }
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
            // Order matters: the window is shown while the panel is still up,
            // so the panel's dismissal teardown (a simulated status-item
            // click, settling after this event) can't land on a freshly
            // ordered window — dismissing first made the very first click
            // read as "did nothing". Focus itself is won by
            // `SettingsWindowController.show()`'s activation promotion.
            state.showSettings()
            DispatchQueue.main.async {
                MenuBarExtraPanel.dismiss()
            }
        } label: {
            Label("设置", systemImage: "gearshape")
                .foregroundStyle(.primary.opacity(0.85))
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
        }
        .keyboardShortcut(",", modifiers: .command)
        .buttonStyle(.plain)
        .hoverHighlight(in: RoundedRectangle(cornerRadius: 5))
    }
}
