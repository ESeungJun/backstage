<p align="center"><img src="docs/images/icon-1024.png" width="120" alt="Backstage"></p>

<h1 align="center">Backstage</h1>

<p align="center">A menu bar app that shows what's going on behind the scenes on your Mac.<br>
It tells you when your scheduled and always-on jobs run and whether the last run worked,<br>
and shows the programs using your CPU as little jelly characters.</p>

<p align="center"><a href="https://github.com/ESeungJun/backstage/releases/latest/download/Backstage-macOS.dmg"><b>⬇ Download for Mac</b></a><br>
<sub>Apple silicon and Intel · signed and notarized · macOS 14+ · <a href="https://github.com/ESeungJun/backstage/releases">All releases</a></sub></p>

<p align="center"><b>English</b> · <a href="README.ko.md">한국어</a></p>

<p align="center"><img src="docs/images/procs.png" width="100%" alt="Running programs: characters that grow with CPU use, with details and a quit button for the busiest app"></p>

---

## Running programs

Every app running under your account gets its own character. The more CPU it uses, the bigger it gets.

- It sleeps when idle, sweats past 50%, and steams past 100%. One full core is 100%.
- It wears its app icon as a hat.
- Apps with many helper processes, like browsers, become one character. macOS system processes are left out.
- Pick a character to see its CPU, memory, how many processes it has, and how long it has been running. Switch to `표` (table) to see every process.
- Apps that don't fit on the stage are in the `그 밖에 N개` (N more) menu at the top right.

**Quitting a program.** Press `종료…` and confirm. An app is asked to quit normally, so it can still ask you to save.
Anything that isn't an app gets `SIGTERM`. If it's still running after 5 seconds, you can force quit it.
macOS system programs and Backstage itself have no quit button.

The animation runs in Core Animation, so leaving this screen open costs almost nothing (0.6% CPU on average with the window open).
With Reduce Motion on, the characters stand still.

## Scheduled and always-on jobs

macOS uses launchd to run a lot of things on a timer or keep them running in the background.
`launchctl list` answers with a wall of labels and numbers. Backstage reads the same information and lays it out in plain words.

<p align="center"><img src="docs/images/hero.png" width="100%" alt="Full view: a table of scheduled and always-on jobs, and details for a job that failed"></p>

- **Schedules** are written out (`Every day 19:07`, `Every Monday 09:10`, `Every 30 minutes`) along with the next run time.
- **Status** is one of running, OK with the run count, never ran, switched off, interrupted (the signal sent at logout or restart), couldn't run (126), command not found (127), and so on. A job that was registered but never ran is not called OK.
- **Run history.** launchd doesn't say when a job last ran. While Backstage is open it watches the run counts and keeps its own record, then shows the last run, the last 14 results and the success rate.
- **Who put it there.** Each item shows the app it came from, by name and icon. Items whose app has been deleted are marked as such.
- **Items planted by apps** are found even without a file in the `LaunchAgents` folders: agents inside an app bundle and services registered at runtime.
- **New arrivals.** The first list it sees becomes the baseline, and anything added later is tagged as new for 7 days. System notifications are available too (off by default).
- **Permission traps.** Jobs that use files in Desktop, Documents, Downloads, iCloud Drive or an external volume can be blocked in the background, so they're flagged in orange with a note on how to fix it.
- **Details and logs.** See the full command, working folder, settings file and the end of the log, or copy a `launchctl print …` command to check it yourself.

Jobs are read-only. Backstage never starts, stops, edits or deletes them.

## In the menu bar

<p align="center"><img src="docs/images/popover.png" width="420" alt="Menu bar summary: needs a look, new arrivals, the app using the most CPU, next runs"></p>

- Click the character icon in the menu bar for a summary: what needs a look, new arrivals, the app using the most CPU, the next runs, and what's running now.
- The icon turns into a warning sign with a count only when one of your own agents fails. Failed third-party daemons and logout signals don't count.
- It reads when you open the summary or the window, every 30 seconds while one is open, and every 5 minutes otherwise. Press ⌘R to refresh.
- The first time you open it, it asks whether to launch at login. You can change that any time from the `⋯` menu.
- There is no Dock icon.

## Install

Download [`Backstage-macOS.dmg`](https://github.com/ESeungJun/backstage/releases/latest/download/Backstage-macOS.dmg), open it, and drag `Backstage.app` into Applications.
One file runs on both Apple silicon and Intel Macs. It's signed with a Developer ID and notarized by Apple, so it opens without a warning.

Requires macOS 14 or later. No permissions needed. The interface is in Korean.
It reads launchd, so it's macOS only.

The only files Backstage writes are its own records (run history and baseline in `~/Library/Application Support/Backstage/`) and its preferences.

## How it's built

A Swift Package with no dependencies, written in SwiftUI and AppKit.

- `BackstageCore` parses plists and `launchctl` and `ps` output, writes schedules as sentences, decides status, keeps run history and groups processes by app. Foundation only.
- `Backstage` is the menu bar (`NSStatusItem`, `NSPopover`), the full window, the character stage (`ProcsView`), quitting programs (`Quitter`) and launch at login (`SMAppService`).
- Status comes from one `launchctl print` per domain, plus a per-service query only where needed. Services still running under the same PID aren't asked again.

Built together with Claude Code.

## Development

```bash
swift build                    # debug build
swift test                     # tests (without XCTest: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer)
./build.sh                     # build/Backstage.app (universal, ad-hoc signed)
./build.sh --install           # build, copy to ~/Applications and launch
.build/debug/Backstage --demo --window --procs   # sample data, running programs tab
.build/debug/Backstage --probe                   # no UI: process count and time of one collection
.build/debug/Backstage --snapshot <dir>          # render sample screens to PNG (README images; --dark for dark mode)
```

Development builds keep their records in a separate `Backstage-dev` folder so they don't mix with the installed app.

<details>
<summary>Project layout and releases</summary>

| Path | Role |
|---|---|
| `Sources/BackstageCore` | Parsing, schedule wording, status, collection, run history, grouping by app |
| `Sources/Backstage` | Menu bar, summary panel, full window, character stage, quitting programs |
| `Tests/BackstageCoreTests` | Fixtures of `launchctl` output with made-up labels, and the tests |
| `build.sh` | Builds arm64 and x86_64, merges them, makes the icon and Info.plist, signs |
| `tools/make_icon.swift` | Draws the app icon (`docs/images/icon-1024.png`) |
| `docs/` | Design notes, decision log, QA checklist, design system (in Korean) |
| `VERSION` | App version; a release tag must match it (`v2.0.0`) |

Every push and pull request runs `swift build` and `swift test` (`.github/workflows/ci.yml`).
Pushing a `v*` tag makes GitHub Actions build the universal app, sign it with a Developer ID, notarize the app and the DMG, and publish `Backstage-macOS.dmg` as a release.
Required secrets: `MAC_CERT_P12`, `MAC_CERT_PASSWORD`, `APPLE_API_KEY_P8`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER`.

</details>
