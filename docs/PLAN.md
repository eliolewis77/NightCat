# 分阶段任务清单

原则：**先把身份改对、基线跑通，再动功能。** 每阶段结束能独立验证，不要把改名和功能改动混在一个提交里。

---

## M0 · 环境准备

| # | 任务 | 命令 / 说明 |
|---|---|---|
| 1 | 安装 XcodeGen | `/opt/homebrew/bin/brew install xcodegen` |
| 2 | 生成工程 | `xcodegen generate` |
| 3 | 确认基线可编译 | `xcodebuild build -scheme Lidless -destination 'generic/platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO` |

**验收**：能生成 `.xcodeproj` 且构建通过。

---

## M1 · 让它成为「你的」仓库

只改身份，不碰功能。

| # | 任务 | 位置 |
|---|---|---|
| 1 | 换 bundle id 前缀 | `project.yml`（`bundleIdPrefix` + 4 处 `PRODUCT_BUNDLE_IDENTIFIER`） |
| 2 | 换 Team ID（**两处必须一致**） | `project.yml` 的 `DEVELOPMENT_TEAM` + `Sources/Shared/HelperProtocol.swift` 的 `LidlessHelper.teamID` |
| 3 | 改兜底 label | `HelperProtocol.swift` 的 `fallbackLabel` |
| 4 | 改显示名与版权 | `Sources/Lidless/Info.plist`（`CFBundleName`、`CFBundleDisplayName`、`NSHumanReadableCopyright`） |
| 5 | **拆除 Sparkle** | `project.yml` 的 package、`Info.plist` 的 `SUFeedURL`/`SUPublicEDKey`、删 `UpdaterController.swift`、清理 `AppState.swift` 里的 updater 引用 |
| 6 | 换图标 | `Resources/Assets.xcassets/`（可先占位，M5 再做正式图） |
| 7 | 清理上游发布残留 | `docs/appcast.xml`、`ExportOptions.plist` 按需 |

**验收**：

- 签名构建出的 App 能运行，helper 能安装成功（首次会弹授权）
- 切换开关后 `pmset -g | grep SleepDisabled` 结果随之变化
- 无 Sparkle 相关的网络请求或链接错误

**这一阶段最容易失败的地方是第 2 条。** Team ID 不一致时开关点了没反应且无报错。

---

## M2 · 三档核心

| # | 任务 | 落点 |
|---|---|---|
| 1 | 用 mode 枚举替换 `AppState.isEnabled: Bool` | `AppState.swift` 第 7 行、`setMasterToggle`（251 行）、`setArmed`（260 行） |
| 2 | 新增 caffeinate 管理层 | 新建文件，负责起停 `caffeinate` 子进程并跟随档位 |
| 3 | 屏幕档 → `caffeinate -d` | 同上 |
| 4 | 防空闲档 → `caffeinate -i -m -s` | 同上 |
| 5 | 合盖档 → 复用现有 helper 通道 | `HelperManager.swift` + `HelperService.swift` **原样不改** |
| 6 | 分段控件替换原来的开关 | `MenuContent.swift` |

**验收**：

- 屏幕档：屏幕不灭，系统可休眠（可观察 `pmset -g assertions` 出现 caffeinate 断言）
- 防空闲：屏幕照常熄灭，系统不睡
- 合盖档：合盖后任务继续跑（**需要真机合盖实测**）
- 档位可连续切换，无残留进程

---

## M3 · 定时与锁定

| # | 任务 | 落点 |
|---|---|---|
| 1 | `AutoOff` 从 on/off 语义改为档位语义 | `Sources/Shared/AutoOff.swift` + 对应测试 |
| 2 | 到点**直接关闭全部档位** | 不逐级回落 |
| 3 | 档位锁定 + 二次确认 | `AppState` + `MenuContent` |
| 4 | 可选「定时器启动时自动锁定」 | `SafetySettings` 或独立设置项 |
| 5 | 锁定状态不跨重启 | 确认不写入持久化 |

**验收**：定时到点行为正确；锁定后切档弹确认，取消后档位不变。

---

## M4 · 电池、外部接管、退出恢复

| # | 任务 | 落点 |
|---|---|---|
| 1 | 电池下开启合盖档 → 内联警示条，用户选择 | 现在 `evaluateSafety()`（381 行）是自动降级逻辑，要改成提示流程 |
| 2 | 电量 < 20% → 直接拒绝 | 阈值走 `SafetySettings` |
| 3 | 运行时拔电源 → 同样走提示，**不静默降级** | 同上 |
| 4 | 扩展外部接管提示 | `StateReconciler.swift` + `externalNotice`（19 行） |
| 5 | 退出恢复**接手前的值**，而非固定 0 | `reconcile()`（300 行） |

**验收**：拔电源时确实弹提示而不是悄悄降档；Amphetamine 开着时界面显示"外部控制"而不是骗人说已开启。

---

## M5 · 中文与图标

| # | 任务 | 落点 |
|---|---|---|
| 1 | 中文界面（当前仅英文） | `MenuContent.swift`（472 行）、`OnboardingView.swift`、`SettingsView.swift` |
| 2 | 菜单栏图标：灰/蓝/青/橙四色 | 换资源，替代原 template image |
| 3 | 倒计时显示规则（仅定时时；合盖档强制） | 菜单栏渲染逻辑 |
| 4 | 右下角锁定标 | 同上 |
| 5 | 正式 App 图标 | `Resources/Assets.xcassets/AppIcon.appiconset`，可用 `scripts/make_iconset.sh` |

**前置条件**：面板与图标的 **HTML 设计稿尚未产出**。项目所有者习惯是「改 UI 前先出设计稿确认」，所以动 UI 前应当先出稿给他确认，不要直接改代码。

---

## M6 · 可选延后项

| 项 | 说明 |
|---|---|
| 工程内部彻底重命名 | target 名、`Sources/Lidless` 目录、`LidlessHelper` target、scheme 名。放在功能完成后的独立提交里 |
| 自建分发链路 | 需要自己的 Sparkle appcast + EdDSA 密钥 + 公证流程。当前不做 |
| CLI / URL Scheme | 已明确砍掉，理由见 `docs/DECISIONS.md` D10 / D11。**不要加回来** |

---

## 交付与验证习惯

项目所有者的**明确偏好**：

- **改完直接报告**：改了什么、在哪个文件、哪一步没做完、哪里还没验证。不要用"已完成"笼统盖过。
- **不要主动跑单测、全量回归、装机截图来自证**——验证是他自己的环节。
- 例外：他当轮明确要求测试或要证据时才跑。

建议的最低限度：提交前确认**能编译**（`xcodebuild build`）。若没验证就如实说明"未验证"。
