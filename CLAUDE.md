# CLAUDE.md — context for future Claude sessions

This file captures load-bearing context about this repo that is **not** obvious
from reading the code alone. If you're a fresh Claude picking this up, read
this first before proposing changes to anything in `Shared/SharedStore.swift`,
the widget entitlements, or the handoff flow.

## What this project is

macOS menu-bar host app + WidgetKit desktop widget that show Claude Code
usage (5-hour session, weekly, extra-usage) by calling the **undocumented**
`https://api.anthropic.com/api/oauth/usage` endpoint. The access token is
read out of Claude Code's own keychain entry (`Claude Code-credentials`) or,
as a fallback, `~/.claude/.credentials.json`.

Two targets, both defined in `project.yml` (XcodeGen):

- **`ClaudeUsageWidget`** — the host menu-bar app. **Unsandboxed**
  (`App/ClaudeUsageWidget.entitlements` sets `app-sandbox: false`). Polls the
  API, caches snapshot+token, drives the menu-bar UI and `SMAppService`
  launch-at-login toggle.
- **`ClaudeUsageWidgetExtension`** — the WidgetKit extension. **Sandboxed**
  (`Widget/ClaudeUsageWidgetExtension.entitlements`). Read-only view over the
  cached snapshot, plus a `RefreshIntent` button that can refetch using the
  cached token.

## The central constraint: no App Group

This project is meant to build on a **free personal Apple team**, which means
no App Group entitlement provisioning. Every macOS tutorial you'll find tells
you to use an App Group for host↔widget data sharing. **You can't here.** All
host↔widget handoff is file-based, and every file path we pick has to clear
*three* different hurdles:

1. **Host (unsandboxed) can write there** without triggering TCC.
2. **Widget (sandboxed) can read there** — which is much more restrictive
   than most docs suggest.
3. **No macOS dialog fires at runtime** — specifically not the Sonoma TCC
   "ClaudeUsageWidget would like to access data from other apps" prompt, and
   not a keychain prompt.

Satisfying all three simultaneously is the entire story of
`Shared/SharedStore.swift`. Don't "simplify" it without understanding what
each branch is defending against.

## Things that trigger macOS dialogs (learned the hard way)

### "ClaudeUsageWidget would like to access data from other apps"
This is a **Sonoma 14+ TCC prompt**, not a keychain prompt. It fires when an
unsandboxed process reads or writes *anywhere* under another app's
`~/Library/Containers/<other-bundle>/` or `~/Library/Group Containers/<group>/`.
Even a `FileManager.default.fileExists(atPath:)` check triggers it.

Specific call sites we've seen trigger it:
- Host writing `snapshot.json` into
  `~/Library/Containers/com.robert.ClaudeUsageWidget.WidgetExtension/…`.
- Host calling `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:)`
  on every poll tick — that call probes `~/Library/Group Containers/…` even
  when the app has no App Group entitlement, and that probe alone is enough
  to fire TCC. **This was the actual cause of the "popup on every menu-bar
  click" bug.** Fix: short-circuit `appGroupDir` to `nil` on the unsandboxed
  host (see `SharedStore.appGroupDir`).
- Host reading `primaryDir` / `widgetContainerDir` paths during
  `candidateURLs(...)` fallbacks. Fix: `candidateURLs` is sandbox-conditional
  — the host-side branch must not iterate over container paths.

### Keychain prompt
Fires if the host reads the keychain without `kSecUseAuthenticationUISkip`,
or if the widget extension tries to read the keychain at all.
**The widget extension must never touch `CredentialsProvider` or the
keychain** — `Widget/UsageProvider.swift:5-10` has a comment reminding
future-you. The widget only ever reads the token out of the shared file
cache that the host wrote.

### TCC on `~/Library/Containers/<other>/` even from the user's own shell
`rm -rf ~/Library/Containers/<widget-bundle>` will fail with "Operation not
permitted" unless Terminal has Full Disk Access in System Settings → Privacy
& Security. This is SIP-level, not our problem, but it bites during
uninstall. The README's "Complete uninstall" section warns about it.

## The handoff path we ended up with

The canonical shared path is **the widget extension's own sandbox container**:

```
~/Library/Containers/com.robert.ClaudeUsageWidget.WidgetExtension/Data/Library/Application Support/ClaudeUsageWidget/
```

The host writes `snapshot.json` and `token.json` directly into that path. The
widget reads them as its own Application Support directory (free, no
entitlement, no sandbox detour).

### Why this path — and why the others don't work

We went through all four options. None of them are free of cost; this one is
the least-bad under the constraints.

- **App Group (`~/Library/Group Containers/<group>/`)** — the "right"
  answer. Blocked: free personal team signing can't provision App Groups.
- **`~/Library/Application Support/ClaudeUsageWidget/`** — host writes
  freely, but the widget sandbox can't read it back without a temp-exception
  entitlement, and that entitlement is stripped at sign time (next bullet).
- **`~/.claudeusagewidget/` + `temporary-exception.files.home-relative-path.read-write`** —
  looked clean in theory. In practice **we verified the entitlement is
  silently stripped from the signed widget bundle** during free personal team
  signing:
  ```bash
  codesign -d --entitlements - Widget.appex
  # → only app-sandbox, get-task-allow, network.client remain.
  # No temp-exception, even though it's in the source .entitlements file.
  ```
  The widget sandbox then denies reads of `~/.claudeusagewidget/` no matter
  what. We still write to this path as a **no-TCC host-only safety cache**
  (useful for `ls`-debugging and external tools that run outside the
  sandbox), but the widget can't use it.
- **`~/Library/Containers/<widget>/…` (what we picked)** — the widget can
  trivially read its own container. The *host* writing there is the catch:
  on macOS Sonoma 14+, an unsandboxed process touching another bundle's
  container fires the TCC dialog **"ClaudeUsageWidget would like to access
  data from other apps"**. It fires **once**, the user clicks Allow, and
  macOS remembers the decision keyed on the app's code signature. As long
  as the signature stays stable (see DEVELOPMENT_TEAM below), subsequent
  launches are silent.

This is the compromise: one Allow click at install time in exchange for a
handoff that actually works on free-team signing. Don't try to rebuild
around `~/.claudeusagewidget/` unless you're on a paid developer account
and the temp-exception entitlement actually survives signing.

**Observed in practice (2026-04-13):** after switching to this scheme with
a stable `DEVELOPMENT_TEAM` set in `project.yml`, the first cold launch
did **not** actually produce the "access data from other apps" dialog at
all — likely because a previous TCC Allow from earlier experimentation
was still cached against the matching signature, or because macOS only
prompts when the target container already exists (the widget's container
hadn't been created yet on the test machine). Either way: do not *promise*
the user the dialog will appear. It may or may not, depending on prior
TCC state. If it does, one Allow click is the expected cost. If it
doesn't, even better.

### Asymmetric read/write rules

Because even a `FileManager.default.fileExists(atPath:)` probe from the
unsandboxed host into `widgetContainerDir` would retrigger TCC, the host
side of `SharedStore` has one hard rule:

**The host never reads from `widgetContainerDir`. Only writes.**

This is enforced by `candidateURLs(...)` branching on `isSandboxed`: the
unsandboxed (host) branch skips widget-container paths entirely. The host
reads only from `sharedDataDir` (`~/.claudeusagewidget/`, which it wrote
itself) and `primaryDir` (legacy). The widget reads from its own container
first, then falls through.

### Subtlety about `getpwuid`

`getpwuid(getuid())->pw_dir` lets you *compute* the real-home path from
inside a sandbox, but it does **not** grant sandbox permission to actually
read files there. We use it in `SharedStore.realHome()` only so that both
host and widget can agree on canonical absolute paths — not as a sandbox
escape. I got this wrong once and assumed the trick was a blanket bypass;
it isn't.

## Sandbox detection

`SharedStore.isSandboxed` is the gate for every conditional behavior:

```swift
private var isSandboxed: Bool {
    NSHomeDirectory() != Self.realHome().path
}
```

`NSHomeDirectory()` returns the container root inside a sandboxed process
and the real home in an unsandboxed one; `getpwuid` always returns the real
home. Comparing the two is a cheap, dependency-free sandbox detector — no
entitlement check, no `SecTask` incantation. Use this whenever you need to
branch on "am I the host or the widget right now".

## Rebuild sequence

Any time you change entitlements, `Info.plist`, or `project.yml`, you need a
full clean rebuild or macOS will keep using the cached extension
registration:

```bash
cd "/path/to/claude-usage-widget"
rm -rf ClaudeUsageWidget.xcodeproj
rm -rf "$HOME/Library/Developer/Xcode/DerivedData"/ClaudeUsageWidget-*
killall chronod 2>/dev/null; killall Dock
xcodegen generate
open ClaudeUsageWidget.xcodeproj
# then ⌘R in Xcode
```

`chronod` is the macOS daemon that hosts desktop widgets — killing it forces
macOS to re-scan extension registrations. `Dock` rescans the menu-bar side.

**Always select the `ClaudeUsageWidget` scheme** (the host app), not the
`ClaudeUsageWidgetExtension` scheme. Widget extensions can't run standalone
— Xcode will attempt to launch them and you'll get a "Could not attach to
pid" dialog from `chronod`.

## Debugging via Console.app

Subsystem filter: `subsystem:com.robert.claude-usage-widget`

Useful categories:
- `SharedStore` — file read/write attempts, sandbox denials show up here
- `Poller` — host fetch cycle
- `UsageService` — API call results, 401/429 handling
- `UsageProvider` — widget timeline reads

`SharedStore.read()` and `readToken()` have explicit per-URL logging of
`exists`/success/failure — use them to distinguish "file isn't there" from
"sandbox denied read" (the latter shows up as a `try?`-swallowed failure
paired with a `sandbox` subsystem denial log).

Sandbox denials proper:
```bash
log stream --predicate 'subsystem == "com.apple.sandbox.reporting"' --info
```

## Signing gotcha: DEVELOPMENT_TEAM

`project.yml` has a comment telling you to set `DEVELOPMENT_TEAM` but the
actual `settings.base` block does **not** set it. Xcode picks a team
interactively. **Set it explicitly** if you want TCC Allow decisions to
persist across rebuilds — macOS keys TCC decisions by code signature, and
re-signing with a different cert invalidates prior decisions.

```yaml
settings:
  base:
    DEVELOPMENT_TEAM: YOURTEAMID   # from Xcode → Settings → Accounts
```

Without this, every rebuild can re-prompt for any previously-allowed
permission. With it, allow-once-and-done actually works.

## Things *not* to change without a good reason

- **`SharedStore.writeDirs` writes to both `widgetContainerDir` AND
  `sharedDataDir` from *both* host and widget.** The widget container is
  the actual handoff point (widget reads from here). The dot-directory is
  a host-only safety cache. Dropping either breaks something — dropping
  `widgetContainerDir` empties the widget; dropping `sharedDataDir` loses
  the no-TCC debugging cache.
- **The `isSandboxed` short-circuit in `appGroupDir`.** Removing it brings
  back the "popup on every menu-bar click" TCC bug — calling
  `containerURL(forSecurityApplicationGroupIdentifier:)` from the
  unsandboxed host probes `~/Library/Group Containers/…` and fires TCC
  even when we have no App Group.
- **The `isSandboxed` guards in `candidateURLs`.** The host-side branch
  must never iterate over `widgetContainerDir` — even a `fileExists` probe
  retriggers TCC. Only the sandboxed (widget) branch is allowed to touch
  that path on reads.
- **Do not add `temporary-exception.files.home-relative-path.*`
  entitlements.** We tried. They're stripped during free personal team
  signing (verified via `codesign -d --entitlements -`). Adding them gives
  false confidence; the widget still can't read the path.
- **`UsageProvider.swift`'s rule that the widget never touches the
  keychain.** The widget is hosted by `chronod` and has no UI — a keychain
  prompt there is invisible and deadlocks the timeline.
- **Don't have the host read from `widgetContainerDir`.** Writes are gated
  by a one-time TCC Allow; reads would retrigger the dialog. The host
  reads from `sharedDataDir` (which it wrote itself) or `primaryDir`.

## Open questions / known risks

- **TCC decision persistence across rebuilds.** The "access data from other
  apps" Allow is keyed to code signature. Without a stable
  `DEVELOPMENT_TEAM` in `project.yml`, every clean rebuild can re-sign with
  a different cert and re-prompt. Mitigation: set `DEVELOPMENT_TEAM`
  explicitly. If the user still sees repeat prompts, run
  `tccutil reset All com.robert.ClaudeUsageWidget` once and click Allow.

- **Stale data in `widgetContainerDir` from old builds.** The widget reads
  its own container first. If an in-place upgrade left an old
  `snapshot.json` there, it will be served until the host (or widget
  `RefreshIntent`) overwrites it. Usually not a problem because the host
  writes on first poll anyway, but if you see unexplained stale data,
  delete the widget container and relaunch.

- **API endpoint stability.** `api.anthropic.com/api/oauth/usage` is
  undocumented and could change or vanish at any point. `UsageService.swift`
  is the only decoder — if it starts returning wire-format decode errors
  after an update, that's the first place to look.

## History of failed approaches (so we don't re-try them)

1. **Temp-exception entitlement on `/.claudeusagewidget/`.** Entitlement
   was present in the source `.entitlements` file but stripped from the
   signed bundle. Verified via `codesign -d --entitlements - Widget.appex`
   showing only `app-sandbox`, `get-task-allow`, `network.client`.
2. **Temp-exception on `/Library/Application Support/ClaudeUsageWidget/`.**
   Same stripping behavior expected — free team signing drops all
   temp-exception entitlements. Not retried.
3. **Having the host probe paths with `fileExists` before writing.** Even
   the probe fires the TCC dialog on Sonoma+. Removed.
4. **`containerURL(forSecurityApplicationGroupIdentifier:)` from the host
   side.** Probes `~/Library/Group Containers/…` and fires TCC on every
   call, even with no App Group entitlement. Guarded by `isSandboxed`.

## User preferences

- Prefers concise explanations that lead with the diagnosis, not the fix.
- Does want rebuild/retest commands spelled out as copy-pasteable blocks.
- Wants the README uninstall section to be exhaustive enough that a future
  user can wipe every artifact without guessing.
