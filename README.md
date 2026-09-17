# NightCat

macOS 菜单栏小工具：控制这台 Mac 什么时候可以睡、什么时候不许睡。

定位很窄——**四档递进 + 防忘记关的安全网**。不是通用电源管理器。

- **关闭**：不干预，一切照常
- **屏幕常亮**：`caffeinate -d`，屏幕不熄灭，方便看盘 / 演示
- **防空闲**：`caffeinate -i -m -s`，系统不因空闲睡眠，屏幕可以灭（跑批、下载、长任务）
- **合盖不睡**：特权 Helper 置 `SleepDisabled`，合上盖子继续跑（无人值守、塞在包里跑完）

安全网：定时关闭（不限时 / 预设 / 自定义 1–240 分钟）、档位锁定 + 二次确认、仅插电保持、低电量阈值、合盖档电池警示、外部接管（Amphetamine 等）识别、退出恢复接手前状态、Helper 看门狗防卡死。

- **过热策略三选一**：自动暂停 / 仅通知不断档 / 忽略
- **启动时自动恢复合盖档**（可选）：远程重启后合盖状态依旧可达
- **中英双语**：跟随系统语言，设置内可切换
- **系统通知**：安全暂停、定时到点、外部程序抢占并自动恢复时主动告知
- **Sparkle 自动更新**：EdDSA 签名 + 公证（feed 托管于 GitHub Pages）

菜单栏图标为猫头剪影，按档位变色（灰 / 蓝 / 青 / 橙），锁定时额头带白色小锁。

## 当前状态

| 项 | 状态 |
|---|---|
| 功能 | ✅ M1–M6 全部完成：四档核心、定时锁定、安全网、双语、通知、自动更新 |
| 代码基线 | ✅ fork 自上游 `nghialuong/Lidless` v0.1.3（含完整 git 历史） |
| UI 设计稿 | ✅ 已确认，见 `docs/design/panel-mockup.html` |
| 版本 | 1.0.0（首次发布待跑通 `scripts/release.sh` 一次性配置） |

**接手开发请先读 [`AGENTS.md`](AGENTS.md)。**

## 来源与许可

本项目是 [`nghialuong/Lidless`](https://github.com/nghialuong/Lidless) 的 fork，基线为 tag `v0.1.3`（commit `1c432ed`）。

上游以 MIT 许可发布，版权归原作者 **Nghia Luong** 所有。本 fork 保留 `LICENSE` 中的原始版权声明，改造部分版权归本仓库所有者。

`upstream` 已配置为 git remote，便于日后对比与择取上游修复：

```bash
git fetch upstream && git log --oneline HEAD..upstream/main
```

## 文档

`AGENTS.md`（接手说明）与代码注释在仓库内。内部开发文档——功能规格、决策记录、
上游侦察笔记、UI 设计稿——保存在维护者本地，不入库。

## 环境要求

| 项 | 版本 / 位置 |
|---|---|
| macOS | 13.0+（由 `project.yml` 的 `deploymentTarget` 决定） |
| Xcode | 15+（String Catalog 需要） |
| XcodeGen | `brew install xcodegen` |
| 签名 | 运行需要开发者证书；特权 Helper 会校验 App 签名（见下） |

## 快速开始

```bash
# 生成 .xcodeproj（该文件被 gitignore，project.yml 才是唯一事实来源）
xcodegen generate

# 跑单元测试
xcodebuild test -scheme NightCat-CI -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO

# 构建 App
xcodebuild build -scheme NightCat -destination 'generic/platform=macOS' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO
```

测试必须以 `** TEST SUCCEEDED **` 结束。

> `CODE_SIGNING_ALLOWED=NO` 只够跑构建和测试。**要真正运行 App 并让特权 helper 生效，必须正常签名**——helper 会校验对端 App 的代码签名。细节见 `docs/FORK-NOTES.md` 的签名章节。

## 架构速览

- **App**：SwiftUI `MenuBarExtra`，`LSUIElement`（无 Dock 图标、不进 Cmd+Tab），非沙盒
- **Helper**：root LaunchDaemon，经 `SMAppService` 注册，通过 XPC 响应 App 请求
- **`Sources/Shared`**：纯逻辑，可单测（pmset 解析、看门狗、安全评估、设置存储）

