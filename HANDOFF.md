# Handoff: Ascent iOS port

**For:** the next agent, who will build, run and polish the iOS app.
**Written:** 29 Sep 2026, at the end of the first implementation session.
**Status in one line:** every feature is written and the shared Swift package compiles and tests on macOS, but the
iOS app, the widget extension and the Live Activity **have never been compiled for iOS or run**, because this Mac had
no working Xcode. Your first job is to get it building for the iOS Simulator and fix whatever the iOS compile finds.

---

## 1. What the user asked for (the goal)

Port this React web app (`src/`) to a native iOS app, with:

1. **Everything ported.** Every screen, metric and domain rule from the web app.
2. **Navigation.** A **Liquid Glass bottom tab bar** is the main way to move between pages. A **`+` button floats
   above the centre of the bar** for quick adding. It opens a **selector to choose which activity** to add: gym send,
   board send, start session, pain check-in, rehab done, end & rate, or plan.
3. **Settings page:**
   - light / dark / system appearance
   - **accent colour** chosen with a colour picker
   - an optional **Face ID app lock** the user can turn on or off
4. **Widgets.** Home Screen and Lock Screen widgets that show **limited info when the phone is locked and full info
   when it's unlocked**. This only applies when the Face ID lock is on.
5. **No cloud.** Everything is stored locally on the iPhone.
6. **A design step first.** A separate designer agent produced a design that the user approved before implementation.

## 2. Sources of truth (in this order)

| File | What it is |
|---|---|
| `design/DESIGN.md` | **Approved spec (r2).** Screens, tokens, the `+`, Face ID, widgets and the SwiftUI API map. Frame IDs like `3.4` refer to the draft. |
| `design/draft.html` | Every frame in light and dark. It's also published as a private Artifact: https://claude.ai/artifact/3Zgb5KZejm4UX2H32QzoHZ |
| `README.md` + `ios/AscentKit/Sources/AscentCore` | Domain rules and vocabulary. (The web app in `src/` was removed on 30 Sep 2026; the iOS code is now the only source.) |
| `ios/README.md` | Short build notes. |

The designer was a separate Claude session named `ascent-designer`, which may no longer be running. If the spec is
ambiguous, ask the user rather than guessing.

## 3. Machine and environment facts (important)

- **An Intel Mac** (i7-9750H, x86_64) on **macOS 26.6.2**.
  - **Xcode 27 and the App Store version will not install on it.**
  - Use **Xcode 26.x** from developer.apple.com/download/all. **Xcode 26.6** was downloaded once, but when the session
    ended it was no longer in `/Applications`; ask the user where it is.
  - iOS 26 is the last iOS whose Simulator runs on Intel. That's fine for this app.
- **Before building:** Xcode must be in `/Applications/Xcode.app`, and the user must accept the licence and install
  components once. That needs their password: open Xcode, or have them run `sudo xcodebuild -license accept` and
  `sudo xcodebuild -runFirstLaunch`.
- **Avoiding `sudo`:** `xcode-select` currently points at CommandLineTools. Either the user runs
  `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`, or you prefix commands with
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, which needs no sudo.
- **Simulator runtime:** if no iOS 26 runtime is installed, run
  `DEVELOPER_DIR=… xcodebuild -downloadPlatform iOS`.
- **Disk:** about 43 GB free after a cleanup. The user approved deleting developer caches; don't delete anything else
  without asking.
- **Tools already installed:** `xcodegen` and `mas` (both via Homebrew), and Node 16.
- **Running tests without Xcode:** the Command Line Tools' Swift 6.3 plus the macOS 26.5 SDK compile and test the
  package on macOS. `swift-testing` needs the extra framework flags, which `ios/AscentKit/test.sh` already passes.

## 4. What exists

```
ios/
├── project.yml                 XcodeGen spec (app + widget extension). `xcodegen generate` → Ascent.xcodeproj
├── Ascent.xcodeproj            generated, never opened in Xcode yet
├── Ascent/                     app target: AscentApp.swift (@main), Assets.xcassets (AppIcon light/dark)
├── AscentWidgets/              widget extension: timeline provider, WidgetBundle (summary widget + Live Activity)
└── AscentKit/                  local Swift package (most of the code, ~9k lines total)
    ├── Sources/AscentCore      models, Vocab, Day (dates), Metrics, Taper engine, Seed (demo data), Store,
    │                           WidgetSummary, LiveSession (ActivityAttributes, iOS-only part behind canImport)
    ├── Sources/AscentUI        Theme (Palette, AccentTheme, fonts), Components, Charts, Screens/*, State/*
    │                           (AppModel, Router, AppSettings, AppLock), Resources/Fonts (OFL fonts, bundled)
    ├── Sources/AscentWidgetsUI WidgetViews (all 6 families, locked/unlocked), LiveActivityViews (iOS-only)
    ├── Tests/AscentCoreTests   18 tests: dates, PRNG, seed, backup round-trip, metrics, taper, store
    ├── Tests/AscentUISnapshots renders screens to PNG on macOS (SNAPSHOT_DIR=…)
    └── test.sh                 runs the tests with the CLT swift-testing paths
```

IDs: bundle `com.ivancyx.ascent` and `com.ivancyx.ascent.widgets`; App Group `group.com.ivancyx.ascent`; URL
scheme `ascent://` (with `today`, `body`, `log`, `review`, `rehab` and `season`). `DEVELOPMENT_TEAM` is empty. The
Simulator doesn't need a team; a real iPhone does, and the user will have to provide one.

### Feature map → code

| Feature | Where |
|---|---|
| 5 tabs (Today · Plan · History · Body · Settings), floating `+`, timer capsule for phones without a Dynamic Island, sheets, deep links, lock overlay window | `Screens/RootView.swift` |
| Quick-add selector (2×3 glass tiles), Pain check-in, Rehab today, toasts | `Screens/QuickAdd.swift` |
| Logging sheet: Start session → Log a send / Camp5 tally / Board → Review → Saved | `Screens/LoggingSheet.swift` |
| Today (dashboard) | `Screens/TodayView.swift` |
| Plan: Today (taper-aware) / Season (calendar, comps, taper plan, weekly target), comp editor and detail | `PlanView.swift`, `SeasonView.swift`, `CompViews.swift` |
| History, Session detail | `HistoryView.swift` |
| Body: map, pain, adherence, rehab, load rules, injury/exercise/rule sheets | `BodyView.swift` |
| Settings (appearance, accent + ColorPicker + near-red warning, Face ID, data export/import/reset/clear), Gyms & boards | `SettingsView.swift` |
| Face ID lock and privacy cover | `State/AppLock.swift`, `Screens/LockView.swift`, overlay window in `RootView.swift` |
| Widget reloads and Live Activity sync after every write | `State/AppModel.swift` |

## 5. Decisions already made (don't re-litigate)

- **Storage is a single Codable JSON file** in the App Group container (`ascent-log.json`) with file protection
  `completeUntilFirstUserAuthentication`, not SwiftData as DESIGN §6 says. The user was told about this.
  - **Why:** it mirrors the web app's snapshot model, is unit-testable, and uses **the same format as the web app's
    backup export**, so `Import backup` accepts files from the web app.
  - No CloudKit or iCloud anywhere.
- **Live Activity buttons are `Link("ascent://log")` and `Link("ascent://review")`**, not `LiveActivityIntent`s.
  They do the same job with fewer moving parts.
- **Demo data seeds on first launch.** It's a port of the web seed, driven by the web's bit-exact mulberry32 PRNG.
  `Settings → Clear everything…` gives an empty log.
- **The accent colours every chart mark.** Injury red `#c0392b` and hold colours never change (DESIGN §4).
- **Widget and Live Activity privacy follows the Face ID lock flag.** It's stored as `privacyLock` in App Group
  defaults, and there's no separate toggle.
- **Days are ISO `yyyy-MM-dd` strings in local time,** so the metrics port line for line from the web.

## 6. What has been verified

- `cd ios/AscentKit && ./test.sh` passes **18/18** tests.
- **Metric parity with the web:** the same demo log was run through the original TypeScript `metrics.ts` in Node and
  through the Swift port. Every compared value matched across all 3 dashboard ranges:
  - KPIs, pyramid, tally, boards, heatmap, readiness
  - chip trends, adherence, load rules, histogram, top grades

  The harness is described in the session history; it isn't committed. The comparison needs `TZ=UTC`, because the web
  uses UTC dates for climbs.
- **Snapshot renders on macOS**, in light and dark, of:
  - Today, Plan (normal and taper), Season, History, Body, Settings
  - Quick add, Log, Review, Lock
  - all home widgets, locked and unlocked

  They looked right against the draft. Bugs found and fixed along the way:
  - calendar days 1–6 were missing
  - the Quick add sheet clipped its last row
  - the large widget named the wrong comp
  - comp names were capitalised badly

## 7. Not verified or known gaps (your checklist)

**Compile and run (do first):**
- [ ] `cd ios && xcodegen generate`, then
      `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Ascent.xcodeproj -scheme Ascent -destination 'platform=iOS Simulator,name=iPhone 17' build`.
      Pick a simulator with `xcrun simctl list devices available`.
- [ ] **Code that has never been compiled at all:**
  - everything under `#if os(iOS)` / `canImport(UIKit)` / `canImport(ActivityKit)`, i.e. `OverlayWindowController`,
    `WindowSceneReader`, `LiveActivityController`, `LiveActivityViews.swift` and `styleNavigationBars()`
  - `ios/Ascent/*` and `ios/AscentWidgets/*`

  Expect some Swift 6 concurrency or availability errors.
- [ ] **Project checks:**
  - The app target sets `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor`; the extension doesn't. Adjust if the provider
    complains.
  - The package uses `swift-tools-version: 6.2` and `.defaultIsolation(MainActor.self)`, which needs Xcode 26+.
  - Make sure the AscentUI font resource bundle is embedded in **both** the app and the appex
    (`AscentFonts.register()` uses `Bundle.module`).
- [ ] Boot the Simulator, install, launch, screenshot. The `apple-skills:ios-development` skill has a `run-simulator`
      module with the exact steps.

**Visual and behaviour checks on iOS:**
- [ ] **Tinted interactive glass rendered blank on macOS.** `.glassEffect(.regular.tint(accent).interactive())` made
      the Lock screen render empty in the offscreen macOS snapshot; it rendered fine with a plain fill. Check the Lock
      screen **and** the `+` on iOS. If it's broken there too, wrap the button in a `GlassEffectContainer` or change
      how the tint is applied.
- [ ] **`+` placement** (`PlusButton` in `RootView.swift`) is estimated, not measured:
  - 10 pt above the tab bar: `bottom = safeAreaInset + 64`
  - when minimised, `bottom = inset − 2`
  - the minimise state is inferred from scroll direction by `BarMinimizeTracker`, not read from the system

  Tune these on a real Simulator for both Dynamic Island and non-island devices (the draft is frame 1.1 / 1.2 / 1.5).
- [ ] **Newsreader large titles** are set through `UINavigationBar.appearance()` in `AppModel.styleNavigationBars()`.
      Confirm this works with iOS 26 bars.
- [ ] **Lock overlay window** (`windowLevel .alert + 1`) should cover open sheets, hide cleanly and pass touches
      through when hidden. The Simulator can test Face ID via Features → Face ID → Enrolled / Matching Face.
- [ ] **Live Activity:** it starts on launch because the demo seed has a live session. Check the Dynamic Island
      compact, minimal and expanded views and the Lock Screen card, the redaction when the lock is on, and that it ends
      after "Save review".
- [ ] **Widgets:** the locked/unlocked switch relies on `redactionReasons.contains(.privacy)` plus
      `.privacySensitive()` (`WidgetViews.swift`). Confirm on a locked Simulator with a passcode set and the Face ID
      lock on. Also check the accessory families: the circular `Gauge`, rectangular and inline.
- [ ] **Pop to root on tapping the active tab:** `Router.select` handles it, but SwiftUI may not call the `TabView`
      selection setter when the same tab is tapped again. Verify.
- [ ] **Deep links:** `xcrun simctl openurl booted ascent://season` (and the others).

**Spec items only partly done (small):**
- [ ] At accessibility text sizes, the heatmap should reflow to one column and the calendar should become a week-row
      list (DESIGN §7). Only the KPI grid reflows so far.
- [ ] Some swipe-to-delete places use a context menu instead: log-sheet rows, load rules, rehab exercises. Session
      detail does use real swipe actions.
- [ ] "Use passcode" on the Lock screen runs the same `.deviceOwnerAuthentication` policy, because iOS has no
      passcode-only policy.
- [ ] The `design/DESIGN.md` §6 note still says SwiftData; update it or leave a note.

**Device install (later, needs the user):** set `DEVELOPMENT_TEAM` for both targets in `project.yml`, regenerate the
project, and sign with the user's Apple ID.

## 8. How to work on it

- **Unit tests:** `cd ios/AscentKit && ./test.sh`. Keep them green.
- **Screen snapshots without a Simulator:** `SNAPSHOT_DIR=/some/dir ./test.sh --filter Snapshots`. This renders through
  `NSHostingView` offscreen; `ImageRenderer` can't draw `ScrollView`s.
- **Regenerate the Xcode project after adding files:** `cd ios && xcodegen generate`. Sources are folder-based.
- **Style rules from the spec:**
  - content is paper with zero radius, hairlines and no shadows
  - glass is only for controls and navigation
  - micro labels use mono caps
  - never show a number for Camp5 tags
- **Git:** nothing has been committed. `design/` and `ios/` are untracked and `.gitignore` is modified. Don't
  commit or push unless the user asks.

## 9. User preferences observed

- Wants to see it running in the Simulator and to walk through every screen together once it builds.
- Is fine with local-only storage and wants no cloud at all.
- Is fine with commands that need a password, but has to run them personally. Keep those to a minimum and say
  exactly what to type (the `! <command>` prefix works in Claude Code).

---

## 10. Session 2 update (29 Sep 2026, evening)

**Builds and runs.** Xcode 26.4 is in `/Applications` and selected; the iOS 26.4 Simulator runtime is installed.
`xcodebuild … -destination 'platform=iOS Simulator,name=iPhone 17'` → BUILD SUCCEEDED; the app runs on iPhone 17.
The font bundle is embedded in both the app and the appex. Tests: 20/20.

**Fixed:**
- Widget extension didn't compile (Swift 6 isolation): `RGB`, `Palette`, the `Color` helpers, `AccentTheme` and
  `SharedAccent` are now `nonisolated`.
- `+` and the root toast double-counted the bottom safe area (sat ~50 pt above the bar). Offsets are now relative to
  the safe area: `+` bottom = 58 (10 pt above the bar), minimised = −2. Measured on iPhone 17.
- Lock overlay window: hands key status back to the app window when hidden; reads the accent live.
- Swipe to delete on log-sheet rows, rehab exercises and load rules (`Components/SwipeToDelete.swift`, a UIKit
  horizontal-only pan; long-press menu and VoiceOver action kept).
- Accessibility sizes: heatmap goes to one column; Season calendar becomes week rows.

**Verified in the Simulator:** Today, Plan (Today + Season), History, session detail, pop-to-root on re-tapping a
tab, Body, Settings; `+` placement expanded and minimised; tinted glass `+` renders fine (the macOS blank-glass
issue doesn't happen on iOS); quick add; log a send → toast → persisted across relaunch; swipe delete;
`ascent://log` deep link; accent + dark mode propagation; Face ID row switches from "Passcode lock" to "Face ID lock"
after enrolment; Live Activity starts and updates (seen in logs).

**Still open:**
- Face ID evaluation fails in this Simulator with `LAError -1000 "UI activation timed out"` (the headless device
  can't show the system Face ID sheet; the app correctly leaves the toggle off). Retry with Simulator.app in front,
  or test on a device. Lock screen overlay therefore not yet seen on iOS.
- Dynamic Island / Lock Screen Live Activity views and the widgets are not yet visually checked.
- Inline nav title on Session detail duplicates the Newsreader date below it, and looks like SF rather than
  Archivo SemiBold 16 — check `styleNavigationBars()`.
- Launch screen is white; should be `paper`.
- Simulator quirks: toggles need a ≥0.2 s press from `simctl`/automation taps; this Intel Mac is slow on first launch.

### Session 2, round 2 (user feedback)
- **`+` live ring** no longer overlaps the tab bar: the `+` lifts 8 pt while the ring shows (`PlusButton`).
- **Done after Save review** closes the whole logging sheet and lands on Today (`Router.closeSheet(then:)`).
  `dismiss()` inside the sheet's own NavigationStack only popped one step; every close/Done/Body log/Dashboard in
  `LoggingSheet.swift` now goes through the router. Done from a History re-review closes back to that session.
- **Tab bar on scroll** is app-driven now: `.tabBarMinimizeBehavior(.never)` + `toolbarVisibility(.hidden, for:
  .tabBar)` from `BarScrollTracker` (`RootView.swift`); the bar hides once you scroll down 12 pt and returns once
  you scroll up 12 pt, anywhere on the page; the `+` follows the same `router.barHidden` flag. The old system
  minimise lingered and re-expanded on the end-of-page bounce. The tracker ignores the offset jump and height change
  caused by the bar's own inset, and the rubber-band settle after a fling (see the comment there) — without that the
  bar oscillated at the bottom.
- Testing note: automated swipes that start on the `+` (y≈745 on iPhone 17) don't scroll the page.

### Session 3 (30 Sep 2026)
- **Copy pass:** on-screen text is short and direct across every tab, sheet and widget (user preference: "at a glance",
  like Whoop / Google Health; no long explanatory sentences). E.g. "Max Strength Day", "NEXT COMP", "Upcoming",
  "Crimpy off · 2/2 this week for L ring finger. Try compression." Keep new copy in that style.
- **Comp categories:** Novice, Intermediate, Open, Youth, Masters, Para. League / Local jam removed; old comps with a
  retired category load as Open in the editor.
- **Load usage** now reports the ruled style (`LoadRuleUsage.headline = rule.styleOrType`), not the full rule sentence.
- **Web app removed** (`src/`, `package.json`, Vite config, `.claude/launch.json`). `Import backup` still reads old web
  exports (`readsWebExport` test).
