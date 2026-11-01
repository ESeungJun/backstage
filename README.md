<p align="center"><img src="docs/images/icon-1024.png" width="120" alt="Backstage"></p>

<h1 align="center">Backstage</h1>

<p align="center">A menu bar app that shows everything running behind the curtain on your Mac.<br>
Scheduled jobs, always-on agents and background programs, with when they run next and whether the last run worked.</p>

<p align="center"><a href="https://github.com/ESeungJun/backstage/releases/latest/download/Backstage-macOS.dmg"><b>⬇ Download for Mac</b></a><br>
<sub>Apple silicon and Intel · signed and notarized · macOS 14+ · <a href="https://github.com/ESeungJun/backstage/releases">All releases</a></sub></p>

<p align="center"><b>English</b> · <a href="README.ko.md">한국어</a></p>

<p align="center"><img src="docs/images/hero.png" width="100%" alt="Backstage: summary cards, a table of scheduled and always-on jobs, and details for a job that failed"></p>

---

Backstage is a small tool for checking on background tasks.
macOS runs a lot of things on a timer or keeps them alive in the background through launchd,
but `launchctl list` only answers in a wall of labels and numbers.
Backstage reads the same information and shows it in plain words: what runs when, what's running now, and what failed.

## What it shows

- **Scheduled jobs** — every launchd job, with its schedule written out (`Every day 19:07`, `Every Monday 09:10`, `Every 30 minutes`)
  and when it will run next.
- **Always-on agents** — jobs that launchd keeps alive, and whether they're running right now (with their PID).
- **Last result** — the exit code of the last run, translated: `OK`, `couldn't run (126) · possibly a file permission problem`, `command not found (127)`, signals and so on.
- **Permission traps** — jobs that use files in Desktop, Documents or Downloads are flagged in orange,
  with a note on why they can fail in the background and how to fix it (move the folder somewhere like `~/Projects`).
- **Details and logs** — pick a job to see its full command, working folder and settings file,
  the last lines of its log, and buttons to reveal the plist in Finder or open the log.
- **Running programs** — a second tab lists the programs running under your account, sorted by CPU, without the macOS system processes.

At a glance, four cards sum it up: how many jobs are scheduled and which one runs next,
what's running now, what failed last time, and what's at risk of being blocked.

## Made to sit in the menu bar

- **One click** — click the clock in the menu bar and a wide panel opens; click anywhere else and it's gone. No Dock icon, no window to manage.
- **It tells you when something breaks** — if any job failed on its last run, the menu bar icon turns into a warning sign with the count.
- **Always fresh** — refreshes every 15 seconds (or press ⌘R).
- **Launch at login** — turned on the first time you open it; untick `로그인 시 실행` in the panel to turn it off.
- **Read-only** — it never starts, stops, edits or deletes a job. It only reads plists, `launchctl` and `ps`.

## Install

Download [`Backstage-macOS.dmg`](https://github.com/ESeungJun/backstage/releases/latest/download/Backstage-macOS.dmg),
open it and drag `Backstage.app` into Applications.
One file works on both Apple silicon and Intel Macs.
It's signed with a Developer ID and notarized by Apple, so it opens without any warning.

Requires macOS 14 or later. No permissions are needed. The interface is in Korean.
The clock icon appears in the menu bar; the app has no Dock icon.

Backstage is macOS only: it reads launchd, which is how macOS runs background jobs.

## Built with

- **SwiftUI + AppKit** in a single file (`Sources/main.swift`), no dependencies.
  The menu bar icon is an `NSStatusItem` with an `NSPopover`; launch at login uses `SMAppService`.
- Schedules come straight from the launchd plists in `~/Library/LaunchAgents`, `/Library/LaunchAgents` and `/Library/LaunchDaemons`;
  status comes from `launchctl list` / `launchctl print`, and processes from `ps`.

Built together with Claude Code.

## Development

```bash
./build.sh               # build/Backstage.app (universal, ad-hoc signed)
./build.sh --install     # build, copy to ~/Applications and launch
open build/Backstage.app --args --demo --window   # sample data in a normal window (for screenshots)
```

<details>
<summary>Project layout and releases</summary>

| Path | Role |
|---|---|
| `Sources/main.swift` | The whole app: plist parsing, schedule wording, status, UI, menu bar |
| `build.sh` | Compiles for arm64 and x86_64, merges them, makes the icon and Info.plist, signs |
| `tools/make_icon.swift` | Draws the app icon (`docs/images/icon-1024.png`) |
| `VERSION` | App version; a release tag must match it (`v1.0.0`) |

Pushing a `v*` tag makes GitHub Actions build the universal app, sign it with a Developer ID with the hardened runtime,
notarize and staple both the app and the DMG, and publish `Backstage-macOS.dmg` as a release.
Required secrets: `MAC_CERT_P12`, `MAC_CERT_PASSWORD`, `APPLE_API_KEY_P8`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER`.

</details>
