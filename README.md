# NightCat

**English** | [中文](README.zh-CN.md) | [日本語](README.ja.md)

A macOS menu bar keep-awake utility. Four escalating modes — not a general-purpose power manager.

| Mode | Behavior |
|---|---|
| **Off** | Everything as usual |
| **Keep Display On** | Screen never sleeps — presentations, market watching |
| **Prevent Idle Sleep** | System stays awake, screen may sleep — downloads, batch jobs, long tasks |
| **Clamshell Awake** | Keeps running with the lid closed — unattended, remote access |

Safety nets: scheduled shutoff, mode locking + confirmation, AC-power-only keep-awake, low-battery threshold, battery alerts, external-takeover detection, restore on quit, and a Helper watchdog against hangs. Overheating policy, pick one of three: **Auto Pause / Notify Only / Ignore**. Optional "restore clamshell mode on launch" — your Mac stays remotely reachable after a reboot.

Optional "Network Keep-Alive": pings the gateway on a timer to prevent idle-link drops; disconnect and IP-change events are logged automatically to `~/Library/Logs/NightCat/network.log`, so remote dropouts leave a trace.

Bilingual (Chinese/English, follows system, switchable), system notifications, a menu bar cat icon that changes color by mode, and Sparkle auto-updates.

<p align="center">
  <img src="panel.png" width="420" alt="NightCat menu bar panel">
</p>

## Download

💛 Support development: if NightCat is useful to you, you can support it on Gumroad ($4.99 one-time, lifetime updates) — your support goes straight into new features. The GitHub version is free and open source, forever.

Download the DMG from [Releases](https://github.com/eliolewis77/NightCat/releases/latest)
(notarized + EdDSA signed). Installed users upgrade automatically via "Settings → About → Check for Updates".

## Build

```bash
brew install xcodegen        # Xcode 15+
xcodegen generate
xcodebuild build -scheme NightCat -destination 'platform=macOS' -configuration Debug
```

Tests: `xcodebuild test -scheme NightCat-CI -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`

> Running requires developer signing — the privileged Helper verifies the app's code signature. Details in [`AGENTS.md`](AGENTS.md).

## Architecture

```
NightCat.app (SwiftUI MenuBarExtra, LSUIElement, non-sandboxed)
   │ XPC (Mach service = <bundle id>.helper)
   ▼
NightCatHelper (root LaunchDaemon, registered via SMAppService)
   │ pmset -a disablesleep · 90-second heartbeat watchdog
   ▼
IOPMrootDomain SleepDisabled
```

- **App**: all state machines and UI; `Sources/NightCat`
- **Helper**: deliberately thin, just sets flags + exchanges heartbeats; `Sources/Helper`
- **Shared**: pure logic (safety evaluation, state reconciliation, timers), ~1300 lines covered by unit tests; `Sources/Shared`

## Origin & License

Forked from [nghialuong/Lidless](https://github.com/nghialuong/Lidless) v0.1.3 (MIT).
Upstream copyright in [`LICENSE`](LICENSE); modifications belong to this repository's owner.
Auto-update feed: https://eliolewis77.github.io/NightCat/appcast.xml
