# NightCat

macOS 菜单栏小工具：控制这台 Mac 什么时候可以睡、什么时候不许睡。

定位很窄——**三档「保持唤醒」+ 防忘记关的安全网**。不是通用电源管理器。

- 屏幕常亮：屏幕不熄灭，方便看盘 / 演示
- 防空闲：系统不因空闲睡眠，屏幕可以灭（跑批、下载、长任务）
- 合盖不睡：合上盖子继续跑（无人值守、塞在包里跑完）

## 当前状态

| 项 | 状态 |
|---|---|
| 功能规格 | ✅ 已定稿，见 `docs/SPEC.md` |
| 代码基线 | ✅ 已 fork 上游 `nghialuong/Lidless` v0.1.3（含完整 git 历史） |
| 改造 | ⬜ 未开始 |
| UI 设计稿 | ⬜ 未出（面板 HTML 稿尚未产出） |

**接手开发请先读 [`AGENTS.md`](AGENTS.md)。**

## 来源与许可

本项目是 [`nghialuong/Lidless`](https://github.com/nghialuong/Lidless) 的 fork，基线为 tag `v0.1.3`（commit `1c432ed`）。

上游以 MIT 许可发布，版权归原作者 **Nghia Luong** 所有。本 fork 保留 `LICENSE` 中的原始版权声明，改造部分版权归本仓库所有者。上游 README 存档在 `docs/upstream-README.md`。

`upstream` 已配置为 git remote，便于日后对比与择取上游修复：

```bash
git fetch upstream && git log --oneline HEAD..upstream/main
```

## 文档索引

| 文件 | 内容 |
|---|---|
| `AGENTS.md` | 接手开发的操作说明：环境、构建、必改项、坑 |
| `docs/SPEC.md` | 功能规格定稿（三档、图标、锁定、电池、定时） |
| `docs/DECISIONS.md` | 已拍板决策与理由，含被砍掉的范围 |
| `docs/FORK-NOTES.md` | 上游代码侦察：架构、关键文件、必须改的硬编码、改造映射 |
| `docs/PLAN.md` | 分阶段任务清单与验收标准 |
| `docs/upstream-README.md` | 上游 README 存档 |

## 环境要求

| 项 | 版本 / 位置 |
|---|---|
| macOS | 13.0+（由 `project.yml` 的 `deploymentTarget` 决定） |
| Xcode | 26.6（本机已装） |
| Swift | 6.3.3（工程 `SWIFT_VERSION` 仍为 5.0） |
| XcodeGen | **未安装**，需 `brew install xcodegen`（本机 brew 位于 `/opt/homebrew/bin/brew`） |
| 签名 | 本机已有 `Apple Development: xiaohees@foxmail.com (5V2J4DPU4L)` 与 `Developer ID Application: TAO LIU (UAT3Y8UXCQ)` |

## 快速开始

```bash
# 生成 .xcodeproj（该文件被 gitignore，project.yml 才是唯一事实来源）
xcodegen generate

# 跑单元测试
xcodebuild test -scheme Lidless-CI -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO

# 构建 App
xcodebuild build -scheme Lidless -destination 'generic/platform=macOS' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO
```

测试必须以 `** TEST SUCCEEDED **` 结束。

> `CODE_SIGNING_ALLOWED=NO` 只够跑构建和测试。**要真正运行 App 并让特权 helper 生效，必须正常签名**——helper 会校验对端 App 的代码签名。细节见 `docs/FORK-NOTES.md` 的签名章节。

## 架构速览

- **App**：SwiftUI `MenuBarExtra`，`LSUIElement`（无 Dock 图标、不进 Cmd+Tab），非沙盒
- **Helper**：root LaunchDaemon，经 `SMAppService` 注册，通过 XPC 响应 App 请求
- **`Sources/Shared`**：纯逻辑，可单测（pmset 解析、看门狗、安全评估、设置存储）

详细架构、关键文件与坑见 `docs/FORK-NOTES.md`。
