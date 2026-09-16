# 上游代码侦察笔记

对基线 `nghialuong/Lidless` @ `v0.1.3`（commit `1c432ed`）的代码勘察结果。写这份的目的是让接手者不用再从头读一遍。

## 上游概况

| 项 | 情况 |
|---|---|
| 仓库 | https://github.com/nghialuong/Lidless |
| 许可 | MIT，Copyright © 2026 Nghia Luong |
| 基线 | tag `v0.1.3`，commit `1c432ed`（appcast: 0.1.3 build 76） |
| 最后一次提交 | 2026-08-06 |
| 代码量 | 3150 行 Swift（Sources），另有约 1300 行单元测试 |
| 工程 | XcodeGen 生成，`project.yml` 是唯一事实来源 |
| 依赖 | Sparkle 2.6.0（**本项目要拆**） |
| 最低系统 | macOS 13.0 |

## 文件清单与职责

### `Sources/Shared/` — 纯逻辑，全部可单测

| 文件 | 行数 | 职责 |
|---|---|---|
| `HelperProtocol.swift` | 74 | helper 身份派生 + XPC 协议 + **对端签名校验要求** |
| `StateReconciler.swift` | 196 | 状态对账（外部接管检测的核心） |
| `SafetySettings.swift` | 227 | 安全设置模型 + 评估器（热/电/充电） |
| `AutoWriteCoordinator.swift` | 116 | 自动化写入协调 |
| `SettingsStore.swift` | 93 | 设置持久化 |
| `AutoOff.swift` | 78 | 定时自动关闭 |
| `PowerParsers.swift` | 59 | `pmset -g` / 电池输出解析 |
| `Safety.swift` | 19 | 安全判定小工具 |

### `Sources/Helper/` — root 守护进程

| 文件 | 行数 | 职责 |
|---|---|---|
| `HelperService.swift` | 134 | **薄** helper：翻 `disablesleep` flag + 90 秒心跳看门狗 |
| `main.swift` | 12 | 入口 |

### `Sources/Lidless/` — App

| 文件 | 行数 | 职责 |
|---|---|---|
| `AppState.swift` | **869** | 状态机，全 App 的脑。改动主要落这里 |
| `MenuContent.swift` | 472 | 菜单面板 UI（**仅英文**） |
| `OnboardingView.swift` | 195 | 首次启动引导 |
| `HelperManager.swift` | 137 | helper 安装 / XPC 连接 |
| `SettingsView.swift` | 83 | 设置页 |
| `SettingsWindowController.swift` | 81 | 设置窗口 |
| `MenuBarExtraPanel.swift` | 72 | 弹出面板容器 |
| `PowerManager.swift` | 54 | 电源操作封装 |
| `UpdaterController.swift` | 52 | Sparkle 更新（**要拆**） |
| `OnboardingController.swift` | 46 | — |
| `Shell.swift` | 28 | 进程调用 |
| `LoginItemManager.swift` | 25 | 登录项 |
| `BatteryMonitor.swift` | 10 | — |

### `Tests/LidlessTests/` — 8 个测试文件，约 1300 行

覆盖 `AutoOff`、`AutoWriteCoordinator`、`HelperIdentity`、`MenuBarExtraPanel`、`SafetyEvaluator`、`SettingsWindowController`、`SharedLogic`、`StateReconciler`。

**改 `Shared/` 里的东西务必同步改测试**，这些测试是改造过程中的安全网。

## 架构

```
NightCat.app（SwiftUI MenuBarExtra，LSUIElement，非沙盒）
   │  持有全部状态：AppState.swift（869 行）
   │
   │  XPC（Mach service，label = <bundle id>.helper）
   ▼
NightCatHelper（root LaunchDaemon，经 SMAppService 注册）
   │  只做两件事：翻 pmset disablesleep / 收发心跳
   │  90 秒没收到心跳 → 自动还原正常睡眠
   ▼
/usr/bin/pmset -a disablesleep 0|1
```

要点：**状态机在 App，不在 helper**。helper 故意做得很薄。

## XPC 协议

`Sources/Shared/HelperProtocol.swift`：

```swift
func setKeepAwake(_ enabled: Bool, withReply: ...)   // 唯一的写操作，布尔
func getState(withReply: ...)                        // 读 pmset
func heartbeat(withReply: ...)                       // 重置看门狗
func version(withReply: ...)                         // 版本自检
```

注意 `setKeepAwake` 是**布尔**。三档改造时，屏幕档/防空闲档不需要走这里（App 层直接起 `caffeinate`），所以**这个协议可以保持不动**——这也印证了 helper 不用改的判断。

## 看门狗（非常重要的安全网）

`HelperService.swift`：

- `keepAwake == true` 时，每 30 秒检查一次
- 距上次心跳超过 **90 秒** → 自动执行 `disablesleep 0`
- 目的：App 崩溃或被强杀后，Mac 不会卡在"永远不睡"

**不要改这个语义。** 它也是当初决定"不做 CLI"的原因之一（CLI 直接驱动 helper 会被它误杀）。

## 必须改的硬编码

| # | 文件 | 具体位置 | 现值 | 说明 |
|---|---|---|---|---|
| 1 | `project.yml` | `options.bundleIdPrefix` | `com.nghialuong` | 改前缀 |
| 2 | `project.yml` | `Lidless` target 的 `Debug` / `Release` `PRODUCT_BUNDLE_IDENTIFIER` | `com.nghialuong.lidless.dev` / `com.nghialuong.lidless` | — |
| 3 | `project.yml` | `LidlessHelper` target 的 `Debug` / `Release` `PRODUCT_BUNDLE_IDENTIFIER` | `...lidless.dev.helper` / `...lidless.helper` | 必须与 App 同一前缀 |
| 4 | `project.yml` | `settings.base.DEVELOPMENT_TEAM` | `TAFDRXJZSR` | 见下条，两处必须一致 |
| 5 | `Sources/Shared/HelperProtocol.swift` | `LidlessHelper.teamID` | `TAFDRXJZSR` | **helper 的 `setCodeSigningRequirement` 用它** |
| 6 | `Sources/Shared/HelperProtocol.swift` | `fallbackLabel` | `com.nghialuong.lidless.helper` | 兜底值，一并改 |
| 7 | `Sources/Lidless/Info.plist` | `CFBundleName` / `CFBundleDisplayName` / `NSHumanReadableCopyright` | Lidless / © 2026 Nghia Luong | 改显示名，版权**追加**不删除 |
| 8 | `Sources/Lidless/Info.plist` + `project.yml` | `SUFeedURL` / `SUPublicEDKey` | 指向上游 | **拆 Sparkle 时一起清掉** |
| 9 | `Resources/Assets.xcassets/` | `AppIcon.appiconset`、`MenubarLaptop*` | 上游图标 | 换图 |

**第 4 与第 5 条不一致的后果**：App 永远连不上 helper，界面无报错。这是这套架构最容易踩的坑。

## 规格 → 代码落点映射

| 规格项 | 上游现状 | 落点 | 改动量 |
|---|---|---|---|
| 三档递进 | `AppState.isEnabled: Bool`（第 7 行）+ `setMasterToggle`（251 行） | `AppState.swift` 引入 mode 枚举，贯穿 UI 与持久化 | **大**（动核心） |
| 屏幕档 / 防空闲档 | 无 | App 层起 `caffeinate` 子进程（不必走 helper） | 中 |
| 合盖档 | 已有，布尔 | 复用 `HelperManager` + `HelperService` 原样 | 小 |
| 档位锁定 | 无 | `AppState` + `MenuContent` 新增 | 中 |
| 定时到点直接关 | `AutoOff.swift` + `autoOffMinutes/Deadline/Remaining`（60–64 行）、`keepAwakeFor(minutes:)`（346 行） | 改成档位语义 | 小–中 |
| 电池提示后用户决定 | `SafetySettings`（227 行）+ `evaluateSafety()`（381 行） | 现在是自动降级逻辑，要改成提示流程 | 中 |
| 外部接管检测 | `StateReconciler.swift` + `@Published externalNotice`（19 行）**已存在** | 扩展即可 | 小 |
| 退出恢复原值 | `reconcile()`（300 行）机制已有 | 确认"还原到接手前的值"而非固定 0 | 小 |
| 中文界面 | `MenuContent.swift` 472 行，仅英文 | 全量本地化 | 中 |
| 图标配色 + 倒计时 + 锁标 | 只有两态 template image | 换资源 + 改菜单栏渲染 | 中 |
| 拆 Sparkle | `UpdaterController.swift` + Info.plist + project.yml package | 删除 | 小 |

## 构建与发布链路

```bash
xcodegen generate
xcodebuild test -scheme Lidless-CI -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild build -scheme Lidless -destination 'generic/platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO
```

发布（本项目不做）：上游的 `scripts/release.sh`、`ExportOptions.plist`、`scripts/sparkle/` 已在 M6 清理删除（Sparkle 在 M1 已拆，这条链路整体作废）。真要分发时从 Developer ID archive 手动导出。

`scripts/lidless.sh` 是最早的 M0 spike 脚本（`pmset disablesleep` 的 shell 版），保留作参考。

## 已知坑

| 坑 | 说明 |
|---|---|
| Team ID / bundle id 不匹配 | XPC 静默失败，无报错 |
| `SKIP_INSTALL: YES` | helper target 必需，否则 archive 被 `xcodebuild -exportArchive` 拒绝（两个 install product → 无 ApplicationProperties） |
| `CREATE_INFOPLIST_SECTION_IN_BINARY: YES` | helper 必需，否则 SMAppService 无法形成 launch constraint（LWCR），daemon 根本起不来 |
| `GENERATE_INFOPLIST_FILE: YES` | helper 的 `CFBundleIdentifier` 来源 |
| 测试 target 的 sources 列表 | 只链接了 `SettingsWindowController.swift` 和 `MenuBarExtraPanel.swift`，因为测试 bundle 不能链接 App target（Sparkle）。拆掉 Sparkle 后可以考虑放宽 |
| `.xcodeproj` 被 gitignore | 不要手改，改 `project.yml` |
| Debug 与 Release 隔离 | Debug 用 `.dev` 后缀 bundle id，helper label 也随之不同，两套 daemon 互不干扰 |
