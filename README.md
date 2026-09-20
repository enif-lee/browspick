# Browspick

A native macOS link router. Browspick registers itself as the default browser,
intercepts every `http(s)` link you click in a native app, and sends it where it
actually belongs — a specific **browser**, **browser profile**, **private
window**, or **native app** (Slack, Zoom, Notion…).

Pure Swift — SwiftUI + AppKit, no web views, no background daemons beyond the
app itself.

## Why

Browsers are workspaces now. Work docs live in the work profile, personal stuff
in another, and half the "links" you click (Slack, Zoom, Figma) shouldn't open
in a browser at all. Browspick learns from your choices and turns them into
rules.

## Features

- **Link interception** — works as the system default browser; every link
  clicked in Slack, Mail, terminal… flows through Browspick.
- **Centered picker** — wide, centered panel showing the full URL and every
  installed browser + profile. Keys: `1–9`, arrows, `Return`, `Esc`,
  `⌘`-pick to save a rule, `⌃`-pick to open in background, `c` to copy the URL.
- **Browser profiles as first-class targets** — Chrome/Edge/Firefox profiles
  are enumerated from `Local State` / `profiles.ini`, shown with their real
  display names and account pictures, and launched deterministically via
  `--profile-directory=` / `-P` (no "last used profile" ambiguity).
- **Rules** — host patterns, path patterns, regex, per-source-app conditions
  ("only when opened from Slack"), URL rewrites. Each rule targets a browser,
  profile, private/new-window variant, or native app.
- **Native app deep-linking** — built-in presets rewrite web links to app
  schemes: Slack (`*.slack.com/archives/…` → `slack://channel?id=…`),
  Zoom, Notion, Spotify, Teams, Figma, Discord invites, Telegram.
- **Suggestions** — after ~5 repeated manual picks for a pattern (or when your
  per-profile browsing history clearly favors one profile), Browspick offers a
  one-click rule. The suggested target is adjustable via a dropdown before
  accepting.
- **History-aware preselection** — the picker pre-selects the target you last
  used for the same host + path prefix (`github.com/personal/*` vs
  `github.com/work/*`).
- **URL cleaning** — optional stripping of tracking parameters
  (`utm_*`, `fbclid`, …) before routing.
- **Private by design** — everything stays on disk
  (`~/Library/Application Support/Browspick/`). Browser profile/history reads
  go through macOS TCC (Files and Folders); nothing is sent anywhere.
- **No menu-bar presence** — accessory app; settings window on demand,
  onboarding until setup is complete.

## How it works

```
link click in native app
  → Launch Services → Browspick (default http/https handler)
  → GURL Apple Event (sender PID → source-app resolution)
  → URL cleaning (optional)
  → rule match? → rewrite (optional) → launch
  → no match → picker → launch + record pick
```

Browser targets are launched by spawning the browser's own executable with the
right flags — `NSWorkspace.openApplication` silently drops arguments on an
already-running app, which would lose both the URL and the profile.

## Browser extension (Chrome/Chromium)

Links clicked *inside* a browser never reach Launch Services, so intercepting
them needs an extension. `Extensions/chrome` is an MV3 extension that talks to
the app over **native messaging** (`com.ed.browspick` — the manifest is
auto-installed into each installed Chromium browser's `NativeMessagingHosts`
dir), with the `browspick:` URL scheme as a fallback:

- **Hover popover** — hovering a link shows the same target list as the app
  picker (browsers + profiles, with icons), plus a Copy button (toggleable)
- **Context menu** — "Open link/page with Browspick"
- **Toolbar button** / `Alt+Shift+B` — send the current page
- **Alt + Click** — intercept a link click (toggleable)
- **Auto-route domains** — listed hosts always go through Browspick: in-page
  clicks, new-tab opens (`⌘+click`, `target=_blank`), address-bar entries and
  bookmarks. A dedup cache breaks the loop if a rule sends the URL back to the
  same profile (options page)

Install for development: `chrome://extensions` → Developer mode →
**Load unpacked** → select `Extensions/chrome`. `make extension` builds a zip
for Web Store upload. The manifest pins a `key` so the extension ID
(`ccmjimgcgbbgoaelfochaljfjnadjdij`) is stable across machines.

With native messaging there is no confirmation dialog. The scheme fallback
(older app / host missing) shows Chrome's "Open Browspick.app?" prompt — tick
**always allow** once.

## `browspick:` URL scheme

```
browspick:open?url=<encoded>                       → route normally
browspick:open?url=<encoded>&prompt                → force the picker
browspick:open?url=<encoded>&app=<bundleId>        → force a browser/app
browspick:open?url=<encoded>&app=<bundleId>&profile=<dir>&private&newwindow
browspick:open?url=<encoded>&target=<targetKey>    → force an exact target
                                                     (extension popover picks)
browspick:dump                                     → write a profile-store debug dump
```

## Comparison

Browspick started as research into how existing link routers work. Roughly:

| | Choosy | Velja | linkquisition | browser-clutch | quickbrowser | **Browspick** |
|---|---|---|---|---|---|---|
| Default-browser interception | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Picker prompt | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Host/URL rules | ✅ | ✅ | ✅ | ✅ | — | ✅ |
| Source-app conditions | ✅ | ✅ | — | — | — | ✅ |
| Browser profiles | ✅ | ✅ | — | — | — | ✅ (names + avatars) |
| Private/incognito target | ✅ | ✅ | — | — | — | ✅ |
| Native-app deep-link rewrites | — | ✅ | — | — | — | ✅ (presets) |
| Tracking-param stripping | — | ✅ | — | — | — | ✅ |
| In-browser interception (extension) | ✅ | ✅ | — | — | — | ✅ (Chromium) |
| Browsing-history suggestions | — | — | — | — | — | ✅ |
| History-based preselection | — | — | — | — | — | ✅ |
| Open source | — | — | ✅ | ✅ | ✅ | ✅ |
| Price | paid | free | free | free | free | free |

(Comparison is approximate — check each project's current docs for details.)

## Requirements & build

- macOS 14+, Xcode/Swift toolchain
- `make install` — build, self-sign (stable identity so TCC grants survive
  rebuilds), install to `/Applications`
- `make dmg` — produce `.build/Browspick-<version>.dmg`
- `make test` — `CoreChecks` unit checks (92 checks)

On first launch, onboarding asks to set Browspick as the default browser and
to grant **Files and Folders** access for browser profile directories —
without it, profiles still work but display names/history can't be read.
