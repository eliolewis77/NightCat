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

    var body: some View {
        Form {
            Section("通用") {
                Toggle("登录时启动 NightCat", isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.setLaunchAtLogin($0) }
                ))
                Toggle("启动定时时自动锁定档位", isOn: Binding(
                    get: { state.settings.autoLockOnTimerStart },
                    set: { v in var s = state.settings; s.autoLockOnTimerStart = v; state.updateSettings(s) }
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
                Toggle("启动时自动恢复合盖档", isOn: Binding(
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

            Section("自动") {
                Toggle("充电时自动开启（合盖档）", isOn: Binding(
                    get: { state.settings.autoEnableWhenCharging },
                    set: { v in var s = state.settings; s.autoEnableWhenCharging = v; state.updateSettings(s) }
                ))
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
                    Text("安装一次后台 Helper，切换档位时便不再询问管理员密码，看门狗也能防止 Mac 卡在保持唤醒状态。")
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
            }
        }
        .formStyle(.grouped)
        .frame(width: Self.preferredSize.width, height: Self.preferredSize.height)
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
