import SwiftUI

/// First-run setup walkthrough. Explains what NightCat does and walks the user
/// through the one optional system step — installing the background helper —
/// then hands off to the menu bar. Surfaces existing `AppState` flows only; it
/// introduces no new permission logic.
struct OnboardingView: View {
    @EnvironmentObject var state: AppState
    @State private var step = 0

    private let lastStep = 3

    var body: some View {
        VStack(spacing: 0) {
            stepContent
                .padding(.horizontal, 36)
                .padding(.top, 36)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Divider()

            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
        .frame(width: 460, height: 560)
    }

    // MARK: Steps

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:  welcomeStep
        case 1:  howItWorksStep
        case 2:  helperStep
        default: doneStep
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 88, height: 88)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            Text("欢迎使用 NightCat")
                .font(.largeTitle.weight(.semibold))
            Text("让 Mac 保持唤醒——合上盖子也不睡。")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("合上盖子带走 Mac 时，编码代理、下载和构建仍可继续运行。系统自带的 `caffeinate` 做不到这一点——NightCat 可以。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var howItWorksStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            header(symbol: "bolt.fill", title: "工作原理")
            VStack(alignment: .leading, spacing: 16) {
                bullet("macbook", "覆盖「合盖即睡眠」的系统行为——合上盖子，一切照常运行。")
                bullet("thermometer.medium", "Mac 过热或电量过低时自动暂停，无人值守也安全。")
                bullet("shield.lefthalf.filled", "NightCat 退出或崩溃时，看门狗会自动恢复正常睡眠，Mac 不会卡在保持唤醒状态。")
            }
            Label("高负载运行时请保持通风和供电。", systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    private var helperStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            header(symbol: "key.fill", title: "免去密码弹窗")
            Text("安装一个很小的后台 Helper，开关保持唤醒时便不再询问管理员密码，安全看门狗也随之可用。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            helperStatusBox

            Text("可选——不安装也能用，只是每次切换档位时会询问密码。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var helperStatusBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            if state.usingHelper {
                Label("后台 Helper 已安装并运行。", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if state.helperNeedsApproval {
                Label("请在 系统设置 ▸ 登录项 中批准 NightCat，然后回到这里。", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button("前往登录项批准…") { state.installHelper() }
            } else {
                Button("安装后台 Helper…") { state.installHelper() }
                    .buttonStyle(.borderedProminent)
            }

            if let err = state.lastError, !state.usingHelper {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(symbol: "checkmark.circle.fill", title: "一切就绪")
            Text("点击菜单栏的 NightCat 图标，按需在「关闭 / 常亮 / 防空闲 / 合盖」四个档位间切换。安全选项在「设置…」里。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("登录时启动 NightCat", isOn: Binding(
                get: { state.launchAtLogin },
                set: { state.setLaunchAtLogin($0) }
            ))
            .toggleStyle(.switch)
            .padding(.top, 8)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button("上一步") {
                withAnimation { step -= 1 }
            }
            .disabled(step == 0)
            .opacity(step == 0 ? 0 : 1)

            Spacer()

            HStack(spacing: 6) {
                ForEach(0...lastStep, id: \.self) { i in
                    Circle()
                        .fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }

            Spacer()

            Button(step == lastStep ? "完成" : "继续") {
                if step == lastStep {
                    state.completeOnboarding()
                } else {
                    withAnimation { step += 1 }
                }
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: Helpers

    private func header(symbol: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 36))
                .foregroundStyle(.tint)
            Text(title)
                .font(.title.weight(.semibold))
        }
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 26)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
