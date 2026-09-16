import SwiftUI

/// The Settings window. Holds the secondary controls and the detailed
/// explanations that used to clutter the menu bar popover: launch at login,
/// background-helper setup, the auto-off timer, and About/GitHub.
struct SettingsView: View {
    /// Fixed size of the window this view lives in — the view isn't resizable,
    /// so `SettingsWindowController` sizes the window from the same constant.
    static let preferredSize = CGSize(width: 420, height: 460)

    @EnvironmentObject var state: AppState

    private let repoURL = URL(string: "https://github.com/nghialuong/Lidless")!

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.setLaunchAtLogin($0) }
                ))
                Toggle("Lock mode when a timer starts", isOn: Binding(
                    get: { state.settings.autoLockOnTimerStart },
                    set: { v in var s = state.settings; s.autoLockOnTimerStart = v; state.updateSettings(s) }
                ))
                Button("Show Setup Guide…") { state.showOnboarding() }
            }

            Section {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Image(systemName: state.usingHelper ? "checkmark.shield.fill" : "exclamationmark.shield")
                            .foregroundStyle(state.usingHelper ? .green : .orange)
                        Text(state.usingHelper ? "Active" : "Using admin prompt")
                            .foregroundStyle(.secondary)
                    }
                }
                if !state.helperInstalled {
                    Text("Install the background helper once so toggling never asks for your password and the watchdog can protect against a stuck-awake Mac.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button(state.helperNeedsApproval ? "Open Login Items to approve…" : "Install background helper…") {
                        state.installHelper()
                    }
                }
            } header: {
                Text("Background helper")
            }

            // The auto-off timer used to live here as a preference — set a
            // duration, then separately remember to flip the switch. It's now a
            // "Keep awake for…" control in the popover next to the toggle it
            // governs, where choosing a duration also turns keep-awake on. One
            // concept, one place; a second entry point here would only be a
            // second thing to keep in step.

            Section("About") {
                HStack(spacing: 12) {
                    if let icon = NSApp.applicationIconImage {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 48, height: 48)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NightCat").font(.headline)
                        Text("Version \(state.appVersion)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("Created by Nghia Luong")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Link("View on GitHub", destination: repoURL)
            }
        }
        .formStyle(.grouped)
        .frame(width: Self.preferredSize.width, height: Self.preferredSize.height)
    }
}
