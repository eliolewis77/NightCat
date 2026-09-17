# NightCat — agent notes

> 动手前先读 [`AGENTS.md`](AGENTS.md)：约束、坑清单、交付习惯。

## 本地验证

```bash
xcodegen generate                # project.yml 是唯一事实来源，.xcodeproj 是产物（gitignored）
xcodebuild test -scheme NightCat-CI -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild build -scheme NightCat -destination 'platform=macOS' -configuration Debug
```

## Project basics

- Bundle id：Debug 用 `com.eliokit.nightcat.dev`（与正式版隔离：独立的
  UserDefaults / 登录项 / helper daemon），Release 用 `com.eliokit.nightcat`。
- 自动更新：Sparkle（SPM）。feed 在 GitHub Pages（`docs/appcast.xml`），
  DMG 在 GitHub Releases。发版流程见 `scripts/release.sh` 头部。
