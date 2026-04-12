# Claude Usage Widget

A native macOS desktop widget that shows everything from
[claude.ai/settings/usage](https://claude.ai/settings/usage) at a glance:

- **5-hour session** utilization with live reset countdown
- **Weekly (7-day)** utilization with reset countdown
- **Extra-usage** credits (used / limit in USD)
- **Current remaining balance** of extra-usage credits
- A discreet **menu-bar icon** with configurable auto-refresh (1–15 min) and a manual refresh button

Reset countdowns animate every second so the widget always feels alive, even between polls.

> ⚠️ **Unofficial endpoint.** There is no public API for consumer Claude usage. This project
> calls `https://api.anthropic.com/api/oauth/usage`, the same undocumented endpoint Claude Code
> uses internally. Anthropic could change or remove it without notice — if that happens the
> widget will simply show "No data yet" until it's updated.

---

## Requirements

| | |
|---|---|
| macOS | **14.0 Sonoma or later** (desktop widgets and interactive widget buttons require Sonoma) |
| Xcode | **16.0 or later** ([free download](https://apps.apple.com/app/xcode/id497799835)) |
| XcodeGen | `brew install xcodegen` |
| Claude Code | Installed and signed in (`claude /login` at least once) |
| Apple ID | Any free personal Apple ID works for signing — no paid Developer Program needed |

---

## Fresh install

### 1. Clone and generate the Xcode project

```bash
git clone <this-repo>
cd claude-usage-widget
xcodegen generate
```

`xcodegen generate` creates `ClaudeUsageWidget.xcodeproj` from `project.yml`. Run it once
before opening Xcode, and again after any `git pull` that changes `project.yml`.

### 2. Open in Xcode and set your team

```bash
open ClaudeUsageWidget.xcodeproj
```

In Xcode:

1. Click the **`ClaudeUsageWidget`** target in the project navigator → **Signing & Capabilities**
   → set **Team** to your personal Apple ID.
2. Do the same for the **`ClaudeUsageWidgetExtension`** target.

> **Tip:** Your team ID is saved in `project.yml` under `DEVELOPMENT_TEAM`. Set it once there
> so you don't have to re-enter it after future `xcodegen generate` runs:
> ```bash
> # find your team ID
> security find-identity -v -p codesigning | grep -o '([A-Z0-9]\{10\})' | head -1
> # then edit project.yml:  DEVELOPMENT_TEAM: "XXXXXXXXXX"
> ```

### 3. Build and run

Select the **`ClaudeUsageWidget`** scheme (top-left of the Xcode toolbar, next to the device
selector) and press **⌘R**.

Xcode will:
- Build both the host app and the widget extension.
- Launch the host app — a **gauge icon** appears in your menu bar.
- Register the widget extension with macOS.

### 4. Grant keychain access

On first launch, macOS prompts for access to the `Claude Code-credentials` keychain item.
Click **Always Allow** so the app doesn't ask again.

### 5. Add the widget to your desktop

1. Right-click an empty area on your desktop → **Edit Widgets…**
2. Search for **Claude Usage**.
3. Drag the size you want (small, medium, or large) onto the desktop.

The rings will populate within the first poll interval (default 5 minutes). Use the
**↻** button on the widget or in the menu-bar popover to trigger an immediate refresh.

---

## Upgrading after a code change

```bash
cd claude-usage-widget
git pull

# Regenerate the project if project.yml changed
xcodegen generate
```

Then in Xcode press **⌘R** to rebuild and relaunch. WidgetKit will pick up the new widget
extension binary automatically — you don't need to remove and re-add the widget.

If the widgets look stale after a rebuild:

```bash
killall chronod 2>/dev/null; killall Dock
```

Then right-click the desktop → **Edit Widgets** → remove and re-add the widget.

---

## What each widget size shows

| Size   | Contents                                                                              |
|--------|---------------------------------------------------------------------------------------|
| Small  | 5-hour ring with % and live reset countdown                                           |
| Medium | All three rings (5-hour, weekly, extra-usage) with reset countdowns and cost figures, plus a refresh button |
| Large  | All three rings + info panel (Used / Limit / Remaining / Plan), header with plan badge and refresh button, last-updated footer |

---

## How it works

```
┌─────────────────────────────┐                ┌──────────────────────────┐
│  Host app (LSUIElement)     │  configurable  │  api.anthropic.com       │
│  ─ MenuBarExtra UI          │ ─────────────► │  /api/oauth/usage        │
│  ─ Poller.swift (1–15 min)  │                └──────────────────────────┘
│  ─ KeychainHelper           │                            │
│  ─ UsageService             │ ◄───── JSON ───────────────┘
└─────────────┬───────────────┘
              │ writes snapshot.json
              ▼
   ┌────────────────────────────────────┐
   │ Widget container                   │
   │ ~/Library/Containers/              │
   │   com.robert.ClaudeUsageWidget.    │
   │   WidgetExtension/Data/…           │
   └─────────────┬──────────────────────┘
                 │ reads
                 ▼
   ┌──────────────────────────┐    interactive
   │ Widget extension         │ ◄── refresh    ┌──────────┐
   │ ─ TimelineProvider       │    button      │ User     │
   │ ─ Small/Medium/Large     │    (AppIntent) │ click    │
   └──────────────────────────┘                └──────────┘
```

### The OAuth call

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <token from "Claude Code-credentials" keychain entry>
anthropic-beta: oauth-2025-04-20
```

Sample response:

```json
{
  "five_hour":   { "utilization": 0.42, "resets_at": "2026-04-11T17:00:00Z" },
  "seven_day":   { "utilization": 0.61, "resets_at": "2026-04-17T03:00:00Z" },
  "extra_usage": {
    "is_enabled": true,
    "used_credits": 6417,
    "monthly_limit": 10000,
    "currency": "USD"
  }
}
```

`used_credits` and `monthly_limit` are in **cents**:

```
balance_usd = (monthly_limit - used_credits) / 100   →   $35.83
```

A second best-effort call to `/api/oauth/profile` retrieves the plan name (Pro / Max) shown
in the Large widget header.

### Refresh strategy

WidgetKit gives each widget a daily reload budget (~40–70 reloads/day, minimum ~15 minutes
between system-driven entries). To keep the widget feeling live:

- **The host app polls on a configurable timer** (default 5 min) while it's running, writes
  the latest snapshot to the widget's container, and calls
  `WidgetCenter.shared.reloadTimelines(ofKind:)`. macOS redraws within ~1 minute.
- **Reset countdowns use `Text(date, style: .relative)`**, which animates every second on its
  own — no timeline reload needed.
- **The ↻ refresh button** on the widget runs an `AppIntent` that fetches directly from
  inside the widget extension and asks WidgetKit to reload immediately.

If the host app isn't running, the widget falls back to the timeline's own 15-minute reload
schedule, drawing the most recent cached snapshot with a small "stale" indicator.

---

## Project layout

```
claude-usage-widget/
├── App/                          # Host app target
│   ├── ClaudeUsageWidgetApp.swift
│   ├── MenuBarView.swift
│   ├── Poller.swift
│   ├── Info.plist
│   └── ClaudeUsageWidget.entitlements
├── Widget/                       # Widget extension target
│   ├── ClaudeUsageWidgetBundle.swift
│   ├── ClaudeUsageWidget.swift
│   ├── UsageProvider.swift
│   ├── UsageEntry.swift
│   ├── RefreshIntent.swift
│   ├── Views/
│   │   ├── SmallWidgetView.swift
│   │   ├── MediumWidgetView.swift
│   │   ├── LargeWidgetView.swift
│   │   └── WidgetPrimitives.swift
│   ├── Info.plist
│   └── ClaudeUsageWidgetExtension.entitlements
├── Shared/                       # Compiled into BOTH targets
│   ├── UsageSnapshot.swift
│   ├── UsageService.swift
│   ├── CredentialsProvider.swift
│   ├── KeychainHelper.swift
│   ├── SharedStore.swift
│   ├── Theme.swift
│   └── RingView.swift
├── Resources/Assets.xcassets/
├── project.yml                   # XcodeGen spec — DEVELOPMENT_TEAM lives here
├── LICENSE
└── README.md
```

---

## Troubleshooting

### "No data yet" / empty rings

The host app couldn't fetch data. In order:

1. Make sure the host app is running — look for the gauge icon in the menu bar. If it's not
   there, open `ClaudeUsageWidget.app` (or press ⌘R in Xcode).
2. Click the menu-bar icon and check the status message at the bottom.
3. If it says "Not authenticated": run `claude /login` in your terminal, then click **Refresh**
   in the menu.
4. Verify the keychain entry exists:
   ```bash
   security find-generic-password -s "Claude Code-credentials"
   ```

### Widget doesn't appear in Edit Widgets

1. The host app must have been launched at least once after the build (this registers the
   extension with macOS).
2. If it still doesn't appear:
   ```bash
   killall chronod 2>/dev/null; killall Dock
   ```
   Then re-open Edit Widgets and search again.
3. If it still doesn't appear, in Xcode verify that the **ClaudeUsageWidgetExtension** target's
   entitlements include `com.apple.security.app-sandbox = YES` (Signing & Capabilities tab).

### Numbers are stuck / "stale" badge

The host app hasn't fetched recently. Click the menu-bar icon to see the exact error. Common
causes: the app was quit, the network is down, or the token expired. Click **Refresh** to
retry immediately.

### 401 Unauthorized

Your OAuth token expired. Run `claude /login` again — Claude Code will refresh the keychain
entry and the widget picks up the new token on the next poll.

### Keychain prompt keeps appearing

Open **System Settings → Privacy & Security → Keychain Access**, find `Claude Code-credentials`,
and add `ClaudeUsageWidget` to its access control list. Click **Always Allow** in the prompt.

### "The endpoint changed and now everything is broken"

Anthropic can change the OAuth endpoint or beta header at any time. The fix is usually a
one-line change in `Shared/UsageService.swift`. Issues and PRs are welcome.

---

## Uninstall

```bash
# 1. Quit the app (click the menu-bar icon → Quit, or kill it)
#    macOS automatically unregisters the widget extension when the app is gone.

# 2. Delete the app (if installed outside Xcode)
rm -rf /Applications/ClaudeUsageWidget.app

# 3. Delete cached data
rm -rf "$HOME/Library/Containers/com.robert.ClaudeUsageWidget.WidgetExtension"
rm -rf "$HOME/Library/Application Support/ClaudeUsageWidget"
```

---

## Limitations & non-goals

- **macOS 14+ only** — desktop widgets and interactive AppIntent buttons require Sonoma.
- **No Notification Center widget** — desktop only by design.
- **No Opus-only ring** — the field is parsed but not displayed.
- **No iCloud sync, no multi-account.**
- **No auto-updater** — `git pull` + `xcodegen generate` + ⌘R.

---

## Credits & prior art

Community tools that reverse-engineered the undocumented OAuth endpoint:

- [TokenEater](https://github.com/AThevon/TokenEater) — architecture template (host app + widget
  extension + shared container) and the `kSecUseAuthenticationUISkip` keychain pattern.
- [ClaudeUsageWidget](https://github.com/dependentsign/ClaudeUsageWidget) — first to demonstrate
  the `getpwuid` trick for reading `~/.claude/` from inside a sandboxed widget extension.
- [ccstatusline](https://github.com/ohugonnot/claude-code-statusline) — shell-script reference
  implementation of the OAuth call.
- [Tray-Usage-Monitor](https://github.com/Firnschnee/Tray-Usage-Monitor) — Windows equivalent,
  useful as a reference for response shapes and refresh strategy.

---

## License

MIT — see [LICENSE](./LICENSE).
