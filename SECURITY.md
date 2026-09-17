# Security Policy

## Supported versions

NightCat is a small personal project; security fixes land on the latest `main`
and are shipped in the most recent release. Please test against the latest code
before reporting.

## Reporting a vulnerability

**Please do not open a public issue for security problems.**

Report privately via GitHub's **Security Advisories** — go to this repository's
**Security** tab → **Report a vulnerability**.

Please include steps to reproduce, the macOS version, and the impact you
observed.

## Security-relevant surface

NightCat is not sandboxed and installs a **privileged background helper** to do
its job, so a few areas matter more than usual:

- **Root LaunchDaemon** (`NightCatHelper`) registered via `SMAppService`. It
  runs as root and toggles the macOS `SleepDisabled` flag (`IOPMrootDomain`).
- **XPC interface** (`NightCatHelperProtocol`) between the menu-bar app and the
  helper — the only channel the app uses to change power state. The helper
  verifies the connecting app's code signature (bundle id + team) before
  serving any request.
- **Heartbeat watchdog**: if the app stops checking in (>90s), the helper
  restores normal sleep on its own, so the Mac can't get stuck awake after a
  crash or force-quit.
- **Update channel**: releases are notarized, and update DMGs are EdDSA-signed
  (Sparkle) — a public key pinned in the app's Info.plist.
- **Admin-prompt fallback** (`PowerManager`): when the helper isn't installed,
  the app shells out to `pmset` via an admin-privileges prompt.
