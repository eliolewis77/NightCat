# AGENTS.md — 接手开发说明

给接手本仓库的 Agent 的操作说明。**先读这份，再动代码。**

## 你的任务

把 fork 过来的 Lidless 改造成 **NightCat**：把单一「合盖不睡」开关扩展为**三档递进**的保持唤醒工具，中文界面，加上档位锁定与防忘关的安全网。功能规格以 `docs/SPEC.md` 为准，任务顺序见 `docs/PLAN.md`。

上游代码是**可用的基线**，不是要重写的东西。提权 helper、XPC、看门狗、签名、发布脚本都是现成且经过验证的，沿用即可。

## 必读顺序

1. `docs/SPEC.md` — 要做出什么（定稿，以此为准）
2. `docs/FORK-NOTES.md` — 上游代码长什么样、哪些硬编码必须改
3. `docs/DECISIONS.md` — 为什么这么定、什么被砍掉了（**别把砍掉的东西加回来**）
4. `docs/PLAN.md` — 分阶段任务与验收标准

## 环境准备

```bash
# XcodeGen 必需，本机尚未安装
/opt/homebrew/bin/brew install xcodegen
```

| 项 | 本机情况 |
|---|---|
| Xcode | 26.6 ✅ |
| Swift | 6.3.3 ✅ |
| XcodeGen | ❌ 需安装 |
| 签名证书 | ✅ 见下 |

## 构建与测试

```bash
xcodegen generate
xcodebuild test -scheme Lidless-CI -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild build -scheme Lidless -destination 'generic/platform=macOS' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO
```

**硬性约束：**

- `NightCat.xcodeproj` / `Lidless.xcodeproj` 是 `xcodegen generate` 的产物，被 gitignore。**永远不要手改 `.xcodeproj`**，改 `project.yml` 后重新生成。
- `Sources/Shared/` 有约 1300 行单元测试覆盖，改这里的逻辑要同步维护测试（是否自行跑测试见文末「交付与验证习惯」）。

## 签名（最容易卡住的地方，务必先读）

helper 是 root LaunchDaemon，监听一个**全机可达**的 Mach service。为了防止任何本地进程都能命令它以 root 身份长期阻止睡眠，上游在 `Sources/Shared/HelperProtocol.swift` 里做了对端签名校验：

```swift
public static let teamID = "TAFDRXJZSR"   // ← 上游的 Team ID，必须换掉
public static func codeSigningRequirement(appBundleID: String) -> String {
    """
    identifier "\(appBundleID)" \
    and anchor apple generic \
    and certificate leaf[subject.OU] = "\(teamID)"
    """
}
```

**Team ID 出现在两个地方，必须同时改且保持一致：**

| 位置 | 键 |
|---|---|
| `project.yml` | `settings.base.DEVELOPMENT_TEAM` |
| `Sources/Shared/HelperProtocol.swift` | `LidlessHelper.teamID` |

不一致的后果是 App 永远连不上 helper，表现为开关点了没反应，且**不会有明显的报错提示**。

本机可用的两个身份：

| 证书 | Team ID | 用途 |
|---|---|---|
| `Developer ID Application: TAO LIU` | `UAT3Y8UXCQ` | **建议统一用这个**，开发与分发同一套 |
| `Apple Development: xiaohees@foxmail.com` | `5V2J4DPU4L` | 仅本地开发 |

`anchor apple generic` 对两种证书都成立，所以本地 Debug 构建同样能通过校验。注意 Debug 和 Release 的 bundle id 不同（`.dev` 后缀），helper 的 label 也是从 bundle id 派生的——两套是隔离的，互不干扰。

## 第一批改动（让仓库成为「你的」）

1. `project.yml`：`bundleIdPrefix` 与两处 `PRODUCT_BUNDLE_IDENTIFIER`
2. `project.yml` + `HelperProtocol.swift`：Team ID 两处
3. **拆除 Sparkle**：`project.yml` 的 package 依赖、`Sources/Lidless/Info.plist` 的 `SUFeedURL`/`SUPublicEDKey`、`UpdaterController.swift`、`AppState.swift` 里对 updater 的持有。
   不拆的后果：你的 fork 会自动去**上游服务器**拉更新包。详见 `docs/FORK-NOTES.md`。
4. `Info.plist`：`CFBundleName` / `CFBundleDisplayName` / `NSHumanReadableCopyright`
5. 图标资源

### 重命名的两种做法

上游的工程名、target 名、目录名都叫 Lidless，彻底重命名要动 `project.yml` 的 `name`/`targets`/`schemes`、`Sources/Lidless` 目录、`LidlessHelper` target、以及从 bundle id 派生的 label。

- **推荐**：先只改**身份**（bundle id、Team ID、显示名、图标），target 名和文件名暂时不动，先把 App 跑起来。工程内部名不影响用户看到的东西。
- 彻底重命名放到功能做完之后的独立提交里，避免和功能改动混在一起、把 diff 搅浑。

## 关键约束（别做这些）

- **不要删除 `LICENSE` 里的原始版权声明。** MIT 要求保留上游作者版权。可以追加自己的版权行。
- **不要把状态机搬进 helper。** 曾经考虑过（为了让 CLI 独立于 App），但 CLI 已被砍掉（理由见 `docs/DECISIONS.md`），helper 保持"薄"的现状即可。
- **不要重新引入 Sparkle 自动更新**，除非你打算维护自己的 appcast。
- **不要动 helper 的 90 秒看门狗语义**：App 停止心跳超过 90 秒，helper 会自动还原正常睡眠。这是防"卡在永远不睡"的核心安全网，非常有意保留。
- 不要在未明确要求的前提下引入第三方依赖。

## 坑清单

| 坑 | 说明 |
|---|---|
| helper 静默失效 | Team ID / bundle id 不匹配时 XPC 连不上，界面无报错。先查签名，再查代码 |
| `SKIP_INSTALL` / `CREATE_INFOPLIST_SECTION_IN_BINARY` | `project.yml` 里这两项是必需的，删了会导致 helper 无法被 exec 或 archive 被拒。注释里有解释，别随手删 |
| 需要真实签名才能运行 | `CODE_SIGNING_ALLOWED=NO` 只能编译测试，跑起来的 App 连不上 helper |
| 合盖测试会锁屏 | 合盖后屏幕熄灭并立即锁屏（本机锁定策略为 immediate），后台任务照跑。这不是 bug |
| 合盖跑有热量代价 | 合盖散热差，长时间跑批建议垫高，别塞在包里 |
| 上游 docs/ | 上游的 `docs/appcast.xml` 与 `docs/menu-popover.png` 是它发布链路的一部分，拆 Sparkle 后 appcast.xml 可清理 |

## 交付与验证习惯（项目所有者的明确偏好）

- **改完直接报告**：改了什么、在哪个文件、哪一步没做完、哪里还没验证。不要用"已完成"笼统盖过没做完的部分。
- **不要主动跑单测、全量回归、装机截图来自证。** 验证是他自己的环节。例外：他在当轮明确要求测试或要证据。
- 建议的最低限度：提交前确认**能编译**（`xcodebuild build`）。若没验证就如实说"未验证"。

> 上游 `CLAUDE.md` 里写的"提交前必须跑绿 `xcodebuild test`"是针对**给上游提 PR** 的场景。本项目阶段不适用，以上面这条为准。
