# Handoff: Ascent r3 redesign (read this first)

**For:** the next agent, who will finish and ship the r3 UI/UX redesign.
**Written:** 12 Oct 2026, when the user asked to stop mid-session. **Updated 13 Oct 2026** (§R7, §R8).
**Status in one line:** r3, the V and French route gym scales, and the logging edits (§R9: edit gym, heel and toe
hooks, the board log with an angle slider and outcomes, review only after End session) are **built and on `main`**.
All tests pass (54 core, 2 snapshot suites). §R9 is the latest work; §R7 and §R8 list what's still open.

The original iOS-port handoff (Sep 2026) is kept below the line at the end of this section. Its machine notes are out
of date (§R2).

## R1. What the user asked for and decided

The goal was a UI/UX redesign so the app looks less AI-generated and more like current apps such as **Whoop**, with
smooth UX. It was decided in a long Q&A with the user and approved from a design canvas before any code was written.

- **Spec:** `design/DESIGN.md`, now r3. r2 (paper and ink) is in git history.
- **Approved design canvas (13 screens):** https://claude.ai/artifact/JzmnogQNGYm7oxoZesVzAp
  - It is private to the user's account.
  - The "Log a send · dark" board is clickable.
  - Its background colours were later changed. The canvas dark ground is still the old `#0A0A0A` palette, which is
    right. Ignore any navy or charcoal values you may see in its history.

Decisions (don't re-litigate):

| Area | Decision |
|---|---|
| **Look** | Whoop-style structure. Dark is the default appearance; light is kept. Rounded cards (radius 22), no hairline bands, no square boxes. Hold colours are the only rainbow. |
| **Grounds** | Dark `#0A0A0A` (near-black neutral grey; the user tried navy and charcoal and came back to this). Light `#F5F5F4`, with white cards. |
| **Type** | SF Pro for all text. Numbers use Archivo bold at width 125, from the variable font's `wdth` axis via CoreText. Newsreader and IBM Plex Mono are removed. |
| **Colour roles** | The accent draws normal state and all chart marks. Amber `#F5A524` means caution. Injury red means warnings and anything body-related. There is no green "good" state. |
| **Today** | Short screen: 3 pillar rings (Load, Progress, Body), the live session card, the last 7 days, one insight, up next. The deep charts moved to a Progress detail screen. |
| **Load** | Each climb scores `attempts × 2^((grade − normal)/2)`. Not-sent attempts count too. **Last 7 days ÷ (the 28 days before ÷ 4).** Under 80 % = light, over 130 % = amber "Spiking". With less than 4 weeks of history it shows "Building baseline N/4". |
| **Normal grade** | Set per scale (numbered 1–15, Camp5 tag, board V) in Settings › Training › Your normal grade. Defaults to the median of the last 28 days of sends. |
| **Camp5** | New order from the user's chart: Pink VB–V1, Blue V0–2, Yellow V1–3, Orange V2–4, Green V3–5, Purple V4–6, Red V5–7, Black V6–8+. **One tag step = 2.5 grade steps** in the Load weight (`Load.camp5StepGrades`). |
| **Progress pillar** | Top grade in the centre with a delta chip. The ring is hard sends (10+) against the previous period, with a second lap when you beat it. |
| **Body pillar** | Latest pain in the centre. The ring is rehab days done in the **last 7 days, rolling**. Red if a load rule is used up; amber if pain is rising or a rule has one use left. "Clear" when there's no active injury. |
| **The `+`** | Unchanged: same position, size and behaviour as r2. The user was explicit about this. |
| **Logging** | Real attempt counts. A pinned bar `[ − n + ] label …… [Send]`: 1 = Flash, 2 = 2nd go, 3+ = "N tries". "Not sent" switch, then the button reads "Log". The form **resets to Flash (1) after every save**. Colour is optional at numbered gyms. Haptic and an undo toast on save. The Camp5 tally and the board log use the same bar. |
| **Copy** | Sentence case, no spaced mono caps labels, few "·" chains, one insight per screen, deltas as small chips. |
| **Motion** | Rings draw in, numbers roll, haptics on every write, zoom from the Load and Progress pillars into their screens. |
| **Confirmed** | Ochre stays a preset, with a near-amber warning. Comp readiness moved to Progress detail. Recent sessions are in History only. |

The user wants a **spec plus visual draft, approved, before any new UI work**. There is a memory note for this.

## R2. Machine facts (these changed since the port handoff)

- The Mac is now **Apple Silicon (arm64)** with **Xcode 27** at `/Applications/Xcode.app`, already selected.
  `xcode-select -p` returns `/Applications/Xcode.app/Contents/Developer`. iOS 27 Simulators are available.
- **Plain `swift test` works now.** `ios/AscentKit/test.sh` was updated to use it when Xcode is selected, and falls
  back to the old Command Line Tools flags otherwise.
- Simulator used: **iPhone 18 Pro**, UDID `5A58AC60-4806-4B3F-B21E-C156C1DD4788`. It is currently booted, with the
  app installed.
  - The app is set to **Dark** appearance (the user's default) again.
- **Build the app:**
  ```bash
  cd ios && xcodebuild -project Ascent.xcodeproj -scheme Ascent -destination 'id=5A58AC60-4806-4B3F-B21E-C156C1DD4788' -derivedDataPath /tmp/ascent-dd build
  ```
  The `.app` ends up in `/tmp/ascent-dd/Build/Products/Debug-iphonesimulator/Ascent.app`. No `xcodegen` was needed:
  new files live in the local Swift package.
- **Simulator automation quirks:**
  - Taps often need `duration` 0.15–0.25 s to register.
  - A tap during a scroll bounce or a sheet animation is dropped.
  - The first cold launch can take several seconds and look like a crash. It isn't.

## R3. What was built (all uncommitted, on `r3-redesign`)

`git status` shows 33 files changed, about +2.1k and −1.7k lines. Key pieces:

- **Core (`ios/AscentKit/Sources/AscentCore`):**
  - `Pillars.swift` (new) holds `NormalGrades`, `Load` (`climbLoad`, `window`, `daily`, `weekly`, `sessions`,
    `suggestedNormals`, `normals`), `Pillars.progress`, `Pillars.body` and `Insights.today`.
  - `Vocab`: the new `camp5Tags` order, `camp5Ranges`, `tickType(attempts:sent:)`, `attemptsLabel(...)`.
    "Attempt only" is now "Not sent".
  - `Database.rerankTags()` runs inside `normalise()`. Logs saved with the old yellow-first order get the ranked
    gym's tag list and each tag climb's ordinal re-ranked from the tag id. It is idempotent.
  - `Settings` gains `normalNumbered`, `normalTag` and `normalV`, persisted as settings rows so they travel in the
    backup. `AscentStore.setNormal…` setters were added.
  - `Day.fullDate`, `Day.relative` and `Day.weekdayShort` were added. `Phase.label` and `Taper.seasonText` add
    sentence-case versions. `Metrics.watchChips` is now public.
  - The seed's `tagWeights` were reordered to match the new tag order.
- **Theme:**
  - `Palette.swift` has the r3 tokens: `ground`, `surface`, `raised`, `track`, `tile`, `sheet`, `segment`, `text`,
    `secondary`, `tertiary`, `hairline`, `caution*` and `injury*`. All old token names were renamed across the code.
  - `AccentTheme` resolves contrast against `surface` and gains `isNearCaution`.
  - `Typography.swift` provides `Font.sans` (SF Pro at the nearest text style, so Dynamic Type works) and
    `Font.num` (Archivo, width 125). `.serif` and `.mono` remain as shims mapped onto these.
  - Only `Archivo.ttf` is bundled now. The OFL notice now credits Archivo; it wrongly named Newsreader before.
- **Components and charts:**
  - `Components.swift`: `Card`; `Band` (now a card); chips; `SquareSegment` (rounded now, name kept); buttons;
    fields; `StepButton`; `DeltaChip`; `String.sentenceCased`.
  - `Charts.swift`: `PillarRing` (animated, second lap with a cut-out, laps under 2 % skipped); `StatGrid`; and
    every r2 chart restyled.
- **Screens:**
  - `TodayView` (rewritten).
  - `PillarDetails.swift` (new): `LoadDetailView`, `ProgressDetailView`, `NormalGradeView`.
  - Router routes `.load`, `.progress` and `.normalGrade`. The zoom transition uses a `zoomNamespace` environment
    value set in `RootView`.
  - `LoggingSheet`: `AttemptBar`, `NotSentRow`, `HoldStrip` dots, tally rows with V ranges.
  - Quick add is sized to its content via `onGeometryChange`.
  - Plan, Season (tints instead of hatching), History (weekly groups), Body, Settings (Training section), comps and
    the lock screen were all restyled.
  - `AppSettings` defaults to `.dark`. Nav bars are back to system SF Pro.
- **Widgets and Live Activity:** sentence-case copy and rounded marks. `AscentWidgets.swift` uses `Palette.surface`.
- **Tests:**
  - `Tests/AscentCoreTests/PillarsTests.swift` (new): attempts, Camp5 order and re-ranking, Load weights and
    windows, normals, body states.
  - The snapshot test was updated for r3 and renders Load, Progress and Normal grade too.
  - **29 core and 2 snapshot tests pass** (`cd ios/AscentKit && ./test.sh`).

**Verified in the Simulator (dark):**
- Today, Load detail, Progress detail, Quick add, Log a send. Pick 11, step to 3: it logged "11, 3 tries" and reset
  to Flash.
- Plan, Season, History, Body, Settings, Your normal grade.
- The zoom transition back from Load.
- Camp5 shows Pink → Black on the existing log after re-ranking.

**Verified in light:** Today and Settings.

**Via snapshots:** widgets small, medium and large, locked and open.

## R4. Known issues and small things noticed

- **Widget pyramid labels wrapped** ("1" over "3"). Fixed in `WidgetViews.swift:98` (`.num(11)`, width 22,
  `fixedSize`), but **not yet re-rendered**. Re-run the snapshots to confirm:
  ```bash
  cd ios/AscentKit && SNAPSHOT_DIR=/tmp/snaps ./test.sh --filter Snapshots
  ```
- **The Review screen's pain chip** (`Menu` wrapping a `Chip`) rendered as a square bordered button in the macOS
  snapshot. Check it on iOS; if it looks wrong, give the Menu label a plain button style.
- **A Load ring just over 100 %** (for example 104 %) shows a short second lap with a notch at 12 o'clock. This is
  intended (Activity style); laps under 2 % are hidden.
- Not checked visually: the accessory widgets (circular, rectangular, inline), the Dynamic Island and Lock Screen
  Live Activity, the Face ID lock screen, the comp editor, the Gyms and boards screen, and light mode on screens
  other than Today and Settings.
- `Taper.seasonLine` (the old upper-case version) is still used where `seasonText` wasn't swapped in. A `grep` will
  show the call sites.
- `Competition.shortName` is still upper case ("KL OPEN"). UI views were switched to `displayName`. Any other caller
  still shows upper case.

## R5. How to work

- Keep tests green with `cd ios/AscentKit && ./test.sh`. `swift build` from `ios/AscentKit` is a fast compile check.
  The full app needs `xcodebuild` (see §R2). The widget extension target compiles only there.
- Copy style: short, sentence case, at a glance (Whoop or Google Health style). See DESIGN.md §0.
- **Don't commit or push unless the user asks.** The work was done on branch `r3-redesign` and is merged to `main`;
  start new work on a fresh branch from `main`.

## R6. Open to-dos, in order

1. **Finish `design/DESIGN.md`.** A scripted edit failed and changed nothing, so these are still stale:
   - The status line still says "DRAFT". It should say approved and built on `r3-redesign`.
   - §4.3: the rehab ring is the **last 7 days, rolling**, not the ISO week.
   - §4.1: a Camp5 step is **2.5 grade steps**.
   - §5.2: normal grades live in the **log's settings rows** (exported with the backup), not in App Group defaults.
   - Add the **Camp5 order and V ranges** and the re-ranking on load.
   - Point §5.3 at `Pillars.swift`.
   - Replace §10 "Open items" with the confirmed decisions in §R1.
2. **Update `README.md`:**
   - The Today row of the tab table should describe the pillars, live card, last 7 days, insight and up next.
     Pyramid, Camp5, boards, heatmap and comp readiness are now in Progress detail.
   - Line 78 says Camp5 goes "from yellow to black". It should say **pink to black**, with the V ranges.
   - Mention attempt counts and Load.
3. Re-render the snapshots to confirm the widget label fix (§R4). Check the Review pain chip on iOS.
4. Walk the screens not yet checked (§R4), especially light mode across the app, the accessory widgets and the Live
   Activity.
5. Set the Simulator app back to **Dark** appearance.
6. Show the user, then commit when they ask. Suggested message: "r3 redesign: Whoop-style UI, Load/Progress/Body
   pillars, real attempt counts".

## R7. Session 13 Oct 2026

**Done from §R6 (committed in `7f661ca`):**
1. `design/DESIGN.md`: status says approved and built; §4.1 Camp5 step = 2.5 grade steps; §4.3 rehab ring is the last
   7 days, rolling; §5.2 normal grades live in the log's settings rows; §5.3 points at `Pillars.swift`; new §5.4 for
   the Camp5 order, V bands and re-ranking; §10 is now the confirmed decisions.
2. `README.md`: Today row (pillars, live card, last 7 days, insight, up next; deep charts in Progress detail), Settings
   training row, attempt counts, Load and the pillars under derived metrics, Camp5 pink to black with V bands, the r3
   design paragraph.
3. Snapshots re-rendered: the widget pyramid labels sit on one line now. The Review pain chip is a proper red capsule
   on iOS; the square look was only the macOS snapshot.
4. Walked in the Simulator in light: Today, Plan, Season, the comp editor, History, Body, Settings, Gyms and boards,
   Review. Load, Progress, Log, Normal grade and Quick add were checked in the light snapshots.
5. The app is back on Dark.

**Fixed along the way:**
- **Dynamic Island content was invisible** (Ink resolved to near-black on the black island whenever the system was in
  light). Every island region now forces a dark colour scheme (`island()` in `LiveActivityViews.swift`), and the keyline
  uses the dark accent.
- **The expanded island clipped its buttons.** Dropped the "since 15:50" line (the timer already shows it), tightened
  the gaps and used 36 pt buttons on the island (44 pt stays on the Lock Screen card). The 30 pt timer can scale to 60 %.
- Live Activity Lock Screen card uses `surface`, as the spec says (was `ground`).
- Widget delta copy: `+2`, `−1`, `Flat` instead of `▲ +2` (DESIGN §0 copy rules). "No numbered sends yet" is
  capitalised.
- Snapshot test also renders the rectangular and inline Lock Screen widgets. The circular gauge style is iOS-only.

**Still open:**
- **Face ID lock screen** is still unverified on iOS. The macOS snapshot draws blank (glass), and headless Face ID times
  out; enrol Face ID from Simulator.app's Features menu, or test on a device.
- The circular accessory widget and the widgets on a real locked phone are not yet seen on iOS.
- Body's rehab note says "N of 7 this week" but counts the last 7 days, rolling.
- `Taper.seasonLine` and `Competition.shortName` are now used only by `seasonLine()` in the tests; no UI shows them.
- The demo's live session started at seed time, so after a day its timer runs past 24 h (the compact island then
  truncates it). Real sessions are fine.
- iOS showed "Allow Live Activities from Ascent?" on the Lock Screen; it was left for the user.

## R8. V and French route gym scales (13 Oct 2026)

**What the user asked:** before committing, a user must be able to add a gym graded in V or French grades. Settled in
a Q&A, drawn on the canvas (row 4, "Gyms and grade scales"), approved, then built. Spec: `design/DESIGN.md` §11.

**Decisions (don't re-litigate):**
- **Boulders and rope climbs share one logging flow.** TensionHouse grades in V. Batuu's rope area grades its rope
  climbs in **French route grades**, lowercase (5a, 5b+, 6a …); it's the only gym that does. Rope climbs log like
  boulders (same attempt bar), with **no lead or top rope**. Camp5's ropes and lead walls use its colour tags, so they
  need nothing new.
- **No Font (capital 6A+) bouldering scale**: no gym uses it.
- **Scale-aware, never converted.** Each scale keeps its own grades. Progress detail has a **scale switch**
  (`1–15 | V | French | Camp5`, only scales with climbs in range); it opens on your main scale (most climbs) and then
  remembers the pick (`progressScale`). Camp5 shows its tally only under its own chip.
- **Thresholds**: 1–15 keeps 8+ and 10+. V and French derive them from your normal grade: flash from normal, hard from
  two grade steps above (V+2, French +4 steps, e.g. 6b → 7a).
- **Load steps**: V grade = 1, French step (6a → 6a+) = 0.5, Camp5 tag = 2.5. A rope attempt counts like a boulder
  attempt for now (routes are longer, so rope days may read light; revisit with real data).
- **UI copy the user picked**: the Gyms and boards toolbar button and the Add gym sheet's button both say **Add**, with
  the text centred. Add gym's scale tiles centre both lines.

**Built:**
- Core: `ScaleType.v/.french`, `GradeKind.gymV ("gym-v")/.french` (boards keep `.v`), `Gym.minGrade`, `gradeKind`,
  `grades`, `gradeSpan`; `Vocab.frenchGrades/gradeLabel/gradeBands(_:)/scaleName/lowestGrade`; `Load.stepGrades`;
  `NormalGrades.gymV/.french`; `Metrics.thresholds`, scale-aware key numbers, pyramid (`PyramidRow.label`), heatmap,
  readiness, `topGrades(.labels)`, `sessionHigh`; `Pillars.scales/mainScale/progressScale/gradedScale`, scale-aware
  Progress pillar and insight; `WidgetSummary.scale`; settings rows `normalGymV`, `normalFrench`, `progressScale`;
  store setters. Demo adds TensionHouse and Batuu rope area with fixed sessions (`Seed.scaleDemo`).
- UI: Gyms and boards in cards with grade strips (`GymCard`), Add gym sheet (`AddGymSheet`, `ScaleOption`),
  Progress detail scale switch (`ScaleSwitch`), Your normal grade cards per scale, log grid per scale (V: whole range,
  6 per row; French: ten around your normal + "Show 5a to 8b+"), Today pillar label, Quick add subtitle, widgets.
- Tests: `Tests/AscentCoreTests/ScalesTests.swift` (17 tests), snapshot renders `gyms-*`, `addgym-*`,
  `progress-v-*`, `progress-french-*`, `progress-camp5-*`.

**Verified in the Simulator (dark):** added TensionHouse through Add gym (V scale, VB to V10), logged "V5, 2nd go"
at it from the log sheet's gym menu, saw the V chip appear in Progress detail with V key numbers and a VB–V5 pyramid,
and the Today pillar read V5. Switched back to 1–15 and the live session back to Batuu afterwards. The Simulator's log
predates the new demo gyms; it now has a user-added TensionHouse with one V5 climb in the live session. Settings ›
Reset to demo data gives the full demo with both new gyms.

**Still open from this work:**
- The old Progress detail board (row 1) on the canvas shows the pre-switch layout; row 4's `Progress detail · by
  scale` is the current one.
- No way to edit a gym after adding it (name, range); only Remove while it has no climbs.
- Routes vs boulders Load weighting (see Decisions).


## R9. Logging edits (14–15 Oct 2026)

**What the user asked:** edit a gym after adding it; Heel hook and Toe hook styles; on boards no styles, only Flash,
2nd go, Project or Attempt only with a way to enter attempts; a 10°–70° angle slider in 5° steps, showing 40° before
any tap; "How did that feel?" only when the session ends. "Confused with beta" was drafted and then dropped (it
overlaps "Read beta wrong"). Spec: `design/DESIGN.md` §12, canvas row "Logging" (board logs) and "Edit gym, end of
session". Approved 15 Oct 2026.

**Built:**
- Core (`Vocab.swift`): `climbStyles` + Heel hook, Toe hook; `ruleStyles` (styles a load rule can cap, keeps Tension
  and Campus) replaces `boardStyles`; `boardAngles` 10…70 by 5, `defaultBoardAngle` 40; `BoardOutcome` (label,
  `of(attempts:sent:)`, `attempts(from:)`, hint); `GymEdit.loggedRange/climbCount`; `Gym.renamed` (a short name that
  matched the name follows it, a separate one like "Camp5" stays). Tests: `LoggingEditsTests.swift` (8).
- Edit gym: `AddGymSheet(editing: [ids])`, opened from every gym card (`SheetRoute.editGym`). Scale locked once the gym
  has climbs; the range can't cut out logged grades; Remove gym only with no climbs; the Bump card edits all three.
- Board log: `BoardLogView` + `AngleRow`; `AttemptBar` gained `title` and `typeable` (the count is a text field; while
  typing, the bar's button reads Done because the number pad has no return key).
- End session: `LogStep.end`, `Router.endSession()` (+ `endRequests`, so a sheet already up re-shows the card),
  `EndSessionCard`, `EndedRoute` → `ReviewView(justEnded:)` with "Session ended, 1:20." and no back button. Quick add
  tile "End session", Live Activity button "End session" → `ascent://end` (`ascent://review` still works).

**Verified in the Simulator (dark):** edited TensionHouse (name and range, stepper stops at the logged V5, toast);
gym log multi-select with both hooks; board log angle slider 40° → 45°, Project → typed 7 → "Logged V6, 7 tries" with
"7 tries, 40°"; End session from the log, the Quick add route and a second End while the sheet was up; Keep climbing;
End and rate → review → Save → Saved; closing the review leaves the session ended and unrated. Snapshots render
`editgym-*`, `editgym-bump-*`, `logboard-*`.

**Simulator state:** the demo's 65-hour live session was ended and rated during the test (it now holds one V6 board
climb, 7 tries). TensionHouse is back to its name and VB to V10. Settings › Reset to demo data restores the demo.

**Then, boards became angle-agnostic (DESIGN §13, 15 Oct 2026):** every board takes 10° to 70°, Moon boards included;
the angle lives on each climb. Gyms and boards reads "V scale, any angle". The board log opens on the board climbed last,
and the slider opens at that board's last logged angle from any session (`Vocab.lastBoardAngle`, snapped to 5°
steps; 40° only for a board with no climbs). `Board.angles` stays in the model for older backups but nothing reads it.
Verified: KB opened at 40°, switching to TB2 moved to its last 25°, a V3 logged at 55° reopened at 55° on TB2. The test
session was deleted afterwards.

**Still open:**
- The Live Activity's end button was changed but not tapped on a real Lock Screen.

---

# Handoff: Ascent iOS port (Sep 2026, historical)

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
