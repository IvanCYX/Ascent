# Ascent iOS: Design Spec (r2)

> **Status: APPROVED by the user on 29 Sep 2026. Build it.** The open questions in §9 are resolved with the
> defaults written in this spec.

Build from this spec and `design/draft.html` (Artifact: https://claude.ai/artifact/3Zgb5KZejm4UX2H32QzoHZ).
Frame IDs (`1.1`, `3.4`…) refer to the draft. Target **iOS 26, SwiftUI, iPhone portrait first**. Every metric,
domain rule and string in `README.md` / `src/domain/vocab.ts` survives unchanged. Vocab strings are final.

**r2 changes (from user review):**
- Settings is now the **5th tab**. Tab roots have **no toolbar gear or appearance button**.
- The live timer depends on the phone. Without a Dynamic Island it is a capsule **8 pt above the `+`**, no longer
  overlapping. With a Dynamic Island it lives in a **Live Activity**, and the `+` gets an accent ring in-app.
- The accent **always** colours charts. The "Accent in charts" toggle is removed.
- The "Hide details in widgets" toggle is removed. Widget privacy **follows the Face ID lock**. Locked widgets may
  show weeks to comp and session count.
- New **Plan → Season**: calendar, competitions (add/edit), and a taper plan that also shortens daily plans.
- The weekly session target is 4 (drives the circular Lock Screen gauge).
- Demo "today" is **Sun 27 Sep 2026** (ISO week 39). Weekdays in all copy are corrected to match.

---

## 0. The identity decision

- **Content layer = paper & ink.** Everything that scrolls (panels, charts, chips, grade buttons, swatches,
  cards, fields, in-content primary buttons) keeps the web identity: `paper` ground, **0 corner radius, no
  shadows, hairline rules**, Newsreader / Archivo / IBM Plex Mono.
- **Control layer = Liquid Glass.** The tab bar, the `+`, toolbar buttons, the quick-add selector, toasts and
  system sheets, alerts and Form groups all use system glass with capsule or concentric radii.
- **Shape rule:** anything drawn **on paper is square**. Anything drawn **on glass is concentric**. Selector tiles
  use radius 22 with a solid fill, and never get a second glass layer. System surfaces keep system radii.
- `#c0392b` (dark `#e5594c`) is reserved for injury/body. Hold and tag colours never change. The **user accent**
  (default **Ink**) owns navigation, the next action, and **all chart marks** (§4).

## 1. Information architecture

```
TabView (5 tabs, floating glass bar)                 + (floating glass button, centred above bar)
├─ Today     NavigationStack  ← web /                 └─ Quick-add selector (sheet, zooms from +)
│   └─ push: Session detail                              ├─ Start session  → sheet: Start → Log
├─ Plan      NavigationStack  ← web /plan                ├─ Gym send       → sheet: Log a send (Gym)
│   ├─ segment Today  (session plan, taper-aware)        ├─ Board send     → sheet: Log a send (Board)
│   └─ segment Season (calendar, comps, taper plan)      ├─ End & rate     → sheet: Review
│       ├─ sheet: Add / edit comp                        ├─ Pain check-in  → sheet
│       └─ push: Comp detail                             ├─ Rehab done     → sheet
├─ History   NavigationStack  ← web /history             └─ Plan           → selects Plan tab
│   └─ push: Session detail → push: Review
├─ Body      NavigationStack  ← web /body
└─ Settings  NavigationStack  (Form)                  Session live → Live Activity (Dynamic Island + Lock Screen)
    ├─ push: Gyms & boards  ← web /gyms (table)
    └─ Data: export / import / reset ← web /gyms Data
```

- Web `/log`, `/board` and `/review` are **actions, not tabs**. They live in one **logging sheet**
  (`.sheet`, `.large`, own `NavigationStack`). A `Gym | Board` segment switches the log view, and End & rate
  **pushes** Review inside the same sheet.
- Today's live-session card (Resume), Plan's Start session, the no-DI timer capsule, and the Live Activity
  buttons all open the logging sheet.
- Review saved (2.7): the Body log / Dashboard buttons dismiss the sheet and set `selectedTab`. That is allowed
  because the user chose it. Nothing auto-switches tabs otherwise.
- Tap an active tab to pop to root (per-tab `NavigationPath` in an `@Observable Router`).
- Deep links: `ascent://today`, `ascent://body`, `ascent://log`, `ascent://review`, `ascent://rehab`,
  `ascent://season`.

## 2. Tab bar, `+`, live timer (1.1–1.9)

- `TabView(selection:)` with `Tab("Today", systemImage: "chart.bar")`, `Tab("Plan", systemImage:
  "list.bullet.clipboard")`, `Tab("History", systemImage: "clock")`, `Tab("Body", systemImage:
  "figure.stand")`, `Tab("Settings", systemImage: "gearshape")`. The selected tab uses the accent (`.tint`).
- `.tabBarMinimizeBehavior(.onScrollDown)`.
- **Tab roots have no settings or appearance button in the toolbar.** Only content-specific actions go there:
  History filter, Body "Log new", Season "Add comp".
- **`+` placement: a custom overlay, not a tab and not `tabViewBottomAccessory`.**
  - HIG: tabs are destinations, and a `+` tab that opens a modal is an anti-pattern.
  - The accessory is a full-width bar meant for Now Playing-style content.
  - The `+` is a 58 pt circle, centred horizontally (above the middle tab, History), bottom edge **10 pt above the
    tab bar**. The icon is `plus` at 26 pt, semibold.
    `.glassEffect(.regular.tint(accent).interactive(), in: .circle)`, foreground `onAccent`. Wrap it with the tab
    bar in a `GlassEffectContainer`.
- **Minimised** (1.2): when the bar minimises, the `+` animates to 48 pt at `bottom = 32 pt`, still centred. Drive
  it from the same scroll direction signal (`onScrollGeometryChange`). Use `.spring(.snappy)`.
- Every tab's scroll content gets `.contentMargins(.bottom, 80, for: .scrollContent)` (120 on phones without a
  Dynamic Island while a session is live, to clear the capsule).
- Accessibility: label "Quick add", hint "Log a send, board climb, pain or rehab". The live timer is announced as
  "Session running, 1 hour 12 minutes".

### Live timer: two device classes
Detect a Dynamic Island with `window.safeAreaInsets.top >= 51` (DI phones report 59–62 pt; notch phones 44–50;
home-button phones 20).

| | Phone **without** Dynamic Island (1.5, 1.6) | Phone **with** Dynamic Island (1.1, 1.7–1.9) |
|---|---|---|
| In app | A glass capsule `● 1:12:05` centred **8 pt above the `+`** (6 pt when minimised). 26 pt tall, Plex Mono 11, `Text(timerInterval: start...Date.distantFuture, countsDown: false)`. The dot is the accent. Tapping it opens the logging sheet. | **No capsule.** A 2 pt accent ring sits 6 pt outside the `+` while a session runs. The elapsed time also shows on Today's live card and the log sheet subtitle. |
| Outside app | Live Activity on the Lock Screen + banner | Live Activity in the **Dynamic Island** + Lock Screen |

**Why not the island while in the app:** iOS does not show an app's own Live Activity in the Dynamic Island while
that app is in the foreground. It appears once the user leaves the app. This is platform behaviour, not a choice.

### Live Activity (ActivityKit)
- Start it when a session starts (`Activity.request`). End it on Save review / End session, or after 8 h with a
  stale state reading "Still climbing?". `ContentState`: `startedAt`, `sends`, `high` (display string, e.g. `12` or
  `PUR` for Camp5 tags, never a number for Camp5), `flashed`, `gymName`, `intent`.
- **Compact** (1.7): leading is the `hold` glyph in the accent plus the top grade tonight (SF Bold 15, white).
  Trailing is the timer in the accent, tabular digits.
- **Minimal**: the timer only.
- **Expanded** (1.8): leading `LIVE · BATUU` + intent. Trailing is a 30 pt timer + "since 19:02". Centre shows
  sends / high / flashed. Bottom has two capsule buttons: **Log a send** (accent) and **End & rate**. Both are
  `LiveActivityIntent`s with `openAppWhenRun`, routing to `ascent://log` and `ascent://review`.
- **Lock Screen** (1.9): the paper card (`.activityBackgroundTint(paper)`) shows micro `● LIVE · GYM · INTENT`, a
  Newsreader 28 timer in the accent, sends / high / flashed, and the two buttons. With the Face ID lock on and the
  device locked, gym, intent, high and flashed are `.privacySensitive()`. Timer and sends stay visible.

### Quick-add selector (1.3 / 1.4)
- Presentation: `.sheet` with `.presentationDetents([.height(452)])`, glass background, zoom transition from the
  `+` (`.matchedTransitionSource(id:"plus", in: ns)` / `.navigationTransition(.zoom(sourceID:"plus", in: ns))`).
- The header shows the live session summary, or `Quick add / NO SESSION · PLAN: …`, plus a close button.
- 2 × 3 tiles. The first is the hero, filled with the accent.

| No session | Session live | Opens |
|---|---|---|
| **Start session** (hero) · plan summary | **Gym send** (hero) · `BATUU · 1–15` / `CAMP5 · TAGS` | 2.1 / 2.2 / 2.4 |
| Gym send · `STARTS A SESSION` | Board send · last board + angle | Start step first if needed |
| Board send · `STARTS A SESSION` | Pain check-in · `L RING · LAST 2/10` (red) | 2.8 |
| Plan today · phase line | Rehab done · `N DUE TODAY` (red if due > 0) | 2.9 |
| Pain check-in (red) | End & rate · `REVIEW TONIGHT` | 2.6 |
| Rehab done (red) | Plan · `TOMORROW` | selects Plan tab |

## 3. Screens

Gutter 16. Bands are separated by 1 px `rule`, with 20 pt vertical padding. Section heads use a Newsreader title
on the left and a mono caps note on the right. Tab roots use a **large title in Newsreader 36** plus a mono caps
subtitle (`.navigationSubtitle`), set through `UINavigationBarAppearance.largeTitleTextAttributes`. Inline titles
use Archivo SemiBold 16.

### 3.1 Today (web Dashboard `2a`)
No toolbar items. Subtitle `WK 39 · 21–27 SEP` (`weekRangeLabel`).
1. **Live session card** (only when active): 2 pt ink border, a `● LIVE · <GYM> · <elapsed>` micro, the line
   `7 sends · high 12 · 3 flashed`, and an accent **Resume** button.
2. **Range**: square custom segment `8 weeks | 6 months | Season`. It refilters every panel and persists
   `dashboardRange`.
3. **KPIs** in a 2 × 2 hairline grid: micro label, Newsreader 40 value, caption, and a mono delta.
4. **Send pyramid** 13 → 7: track holds a `worked` segment with a `data` flashed segment inside it, count on the
   right, and a legend. "Read:" insight below (tap to hide; `Show reads` brings it back).
5. **Camp5 · colour tags**: 8 bars in hold colours with counts and codes. Zero shows as a 3 pt stub. Read line
   below. Numbers never appear.
6. **Board grades**: one card per board and angle. V max, delta `▲ V5→V6` or `— flat this range`.
7. **Injury watch** (active injury only): red panel with a 7-entry pain sparkline, `pain a/10 → b/10`, and the
   rehab streak. Tapping it selects Body. A **Load flag** card below shows when a rule is nearing or blocked.
8. **Comp readiness · N WEEKS OUT**: meters, with scores below 55 in red. Tapping opens Plan → Season.
9. **Where you send · style × grade**: an 84 pt label column + 5 cells, each 36 pt tall. Fill is `data` at alpha
   `0.07 + pct × 0.78`, with `paper` text when alpha ≥ 0.5. Weak-row gap cells (≤ 20%) are red. `—` means nothing
   was attempted. A red read line lists the weak rows, then the "Comp prep:" insight follows.
10. **Recent sessions** (5): ledger rows (see History). Tapping pushes Session detail.

### 3.2 Plan · Today (web `3d`)
Toolbar empty. Subtitle is the **season phase** (`BUILD · 6 WK TO KL OPEN`). A square **`Today | Season`**
segment sits under the title and persists per launch.
Hero: micro `SUN 27 SEP · BATUU`, then Newsreader 27 "Today is a {intent} day".
**Gym** chips (horizontal scroll) → **Session intent** 3 × 2 tiles (selecting one loads that template) →
**Focus styles** (blocked styles struck through + inline warn panel) → **Blocks** (`N MIN TOTAL`; the emphasis
block gets a 2 pt ink border; the rehab block is auto-appended in red) → **Save as template** + accent **Start
session** (disabled while a blocked focus is selected) → footer
`NEXT COMP · KL OPEN · BOULDERING · 6 WEEKS OUT · TAPER STARTS MON 26 OCT`.

**Taper-aware (3.3).** When today falls in a TAPER or COMP WK phase of an A or B comp:
- A 2 pt ink card appears under the hero: `TAPER · 70% VOLUME` + `KL OPEN · SUN 8 NOV`, the explanation of what
  changed ("Blocks were shortened from 105 to 75 min. The 4×4s block was dropped. Keep the intensity…"), and a
  load bar. The fill is this week's planned minutes; the tick is the 8-week average.
- High-cost intents (**Max strength**, **Power endurance**) are struck through. The helper line explains why.
- Blocks are scaled: every duration × the phase's volume factor, rounded to 5 min. The emphasis block keeps its
  intensity target, and its tag notes the original (`was 5 × 50 min`). Blocks marked `drop in taper` in the
  template are removed. **Rehab blocks are never scaled.**
- Buttons: **Use full plan** (overrides the taper for today) + **Start session**.

### 3.4 Plan · Season (new)
Toolbar: glass text button **Add comp**. Content in order:
1. **Next comp card** (2 pt ink border): micro `NEXT COMP · A PRIORITY`, `42 DAYS`, Newsreader 26 name,
   `date · where · category · rounds`. Below it, a **phase bar**: BUILD (current phase filled with `data`,
   label `· NOW`), PEAK (`track`), TAPER and COMP WK (hatched), and a comp flag cell in the accent, with mono date
   ticks under it. Tapping pushes **Comp detail**: all fields, edit, delete, a warm-up/notes field, and after the
   comp an optional result (round reached, tops/zones).
2. **Calendar**: a continuous vertical month scroll, Monday first, starting from the current month and going
   through the month of the last upcoming comp. Each month has a Newsreader 20 header, a mono weekday row, and
   46 pt cells.
   - Day number in Archivo 15. **Today** gets a 1.5 pt ink ring. The **selected** date gets an ink fill.
     A **comp day** gets an accent fill with the comp's short name in mono 7.5 accent under it.
   - Dots: a solid `data` square for a logged session, an outlined one for a planned session.
   - Phase shading: PEAK days in `track`, TAPER days hatched `track`, COMP WK days hatched `worked`.
   - Tapping a date updates a **day card** below the calendar: date + phase, what is on it, and **Plan a
     session** / **Add comp** buttons. Add comp pre-fills that date.
   - Legend under the calendar: logged, planned, peak, taper, comp.
3. **Taper plan** (`KL OPEN · A · FROM YOUR 8-WK AVG`): one row per phase week. Each row has a mono phase + date
   range, a bold lead sentence, guidance, and a load bar (fill = volume factor; tick = 100% of the 8-week average).
   An **Injury check** warn panel appears when an active injury has load rules.
4. **Upcoming comps**: ledger rows (date block, name, `where · category · priority · taper summary`). Tapping
   pushes Comp detail.
5. **Sessions / week target** stepper (default **4**, range 1–7): *"Also drives the Lock Screen gauge. Taper weeks
   scale it down automatically."*

### Taper engine (domain, new; add alongside `metrics.ts`)
Input: the next comp with priority A or B, today, the 8-week averages (sessions/wk, planned minutes/wk, sends at
10+/wk), and active load rules. All values are derived; none are stored.

| Priority | Phases (weeks before the comp week) | Volume factor | Guidance lines |
|---|---|---|---|
| **A** | BUILD until −3 · PEAK −2 · TAPER −1 · COMP WK | 100 / 90 / 70 / 50 % | PEAK: 3 comp sims, 4 on / 4 off, no previews. TAPER: 3 sessions, 75 min max, keep one limit session, drop 4×4s and new max-strength. COMP WK: 2 short sessions, last hard session ≥ 4 days out, no limit board in the last 6 days, rest the day before. |
| **B** | BUILD · TAPER (comp week only) | 100 / 70 % | One lighter week. The last hard session is ≥ 3 days out. |
| **C** | none | 100 % | Rest the day before. |

- Sessions/week target in a phase = `round(target × factor)`, with a minimum of 2 in TAPER and COMP WK.
- Phase for the Today subtitle: the phase of the nearest A/B comp within 8 weeks. Otherwise the training block
  phase (the existing `blockPhase` setting).
- When comps overlap (a C comp inside an A comp's taper), the A plan wins, and the C comp shows a note in its row.
- Load rules stay in force. If the injury's pain is above the rule's threshold at the start of PEAK, show the
  Injury check panel and drop that style from the comp-sim focus.

### 3.5 Add comp (sheet)
A large paper sheet with a close button, the title "New comp" (or "Edit comp"), and **Done** (accent).
Fields, in order:

| Field | Control | Model |
|---|---|---|
| Name | text field `NAME` | `name: String` (required) |
| Date | inline `DatePicker(.graphical)` in a card, tinted with the accent; the header shows `Sun 8 Nov 2026` | `date: Date` (required) |
| Multi-day | toggle; when on, a second date row `ENDS` appears | `endDate: Date?` |
| Where | text field `WHERE` + a Menu to pick a saved gym | `location: String?`, `gymId: String?` |
| Category | chips: Open · Youth · Masters · Para · League · Local jam (single) | `category: String` |
| Format | chips: Onsight rounds · Flash · Redpoint / jam (single) | `format: String` |
| Rounds | chips: Qualifiers · Semi-final · Final (multi) | `rounds: [String]` |
| Priority | square segment: `A · peak` / `B · mini taper` / `C · train through`, plus a helper line | `priority: A/B/C` (default A) |
| Notes | dashed note box | `notes: String?` |

A pinned accent **Add comp** button (or **Save**). Extend the web `Competition` entity with these fields; the
export/import JSON gains them too.

### 3.6 History (web `1g` + ledger)
Toolbar: filter `Menu` (gym, intent, rated only). Subtitle `86 SESSIONS · NEWEST FIRST`.
1. **What keeps coming up · LAST 12 SESSIONS**: chip label, 12 cells (`data` / `track`), `n×`, then **Pattern:**.
2. **Ledger**, grouped by month. Each row: date block (Newsreader day + mono weekday), gym + intent · boards, top
   grades (first chip ink, or Camp5 swatches + codes), `N SENDS` + felt meter or `NOT RATED`, and a chevron.
   Tapping pushes Session detail.

### 3.7 Session detail
Back button, trailing glass **Edit review**. Micro `GYM · INTENT · DURATION`, then a Newsreader 32 date, a 2-up KPI
(Sends / Felt with average), review chips (pain in red), the note in Newsreader italic, Gym climbs, Board climbs,
and the Plan summary. Rows swipe to delete, with a confirmation.

### 3.8 Body (web `1k`)
Toolbar: glass **Log new** (new-injury sheet). Subtitle `1 ACTIVE · 2 WATCHING`. The body map sits beside the
legend (tap a part to filter). The injury card has the `•••` Menu (Downgrade / Resolve / Reopen, Edit), pain chart,
an 11-cell **Log today** row (30 × 44 pt), and adherence. Then **Rehab protocol** (tap to toggle today; `+ Add
exercise` sheet), **Load rules & notes** (red capped rules with pips; swipe to delete; `+ Add load rule` sheet;
dashed physio note), and **Watching** with an **Escalate** link.

### Logging sheet (2.1–2.7)
One `.sheet` with `.large` and its own NavigationStack. Nav bar: close on the left, then a title with a mono
subtitle `GYM · SCALE · ELAPSED`, then a glass gym Menu (`Batuu ▾`) on the right.
- **2.1 Start session**: plan card, gym chips, optional intent chips, focus from the plan, and a pinned **Start
  session**. It starts the session **and the Live Activity**, then pushes the log.
- **2.2 Log a send** (`3a`): `Gym | Board` segment → `1 · GRADE` (top 10, `Show 1–N`) → `2 · HOLD COLOUR` (9-cell
  strip, 40 × 48 pt) → inline load flag → optional block (tick type, styles, WHERE, Clear) → **This session**
  rows (swipe to delete) → pinned confirmation bar with an accent **Send**.
- **2.3 Sent**: `.sensoryFeedback(.success)`, row inserted, glass toast `✓ Sent · 12 blue · 3 tries  Undo` (4 s),
  and the Live Activity state is updated.
- **2.4 Camp5 tally** (`1d`): automatic for ranked-colour gyms. **No numbers.**
- **2.5 Board** (`3b`): board buttons, angle cells, V1–V10, CLIMB name, board styles (+ Tension), tick types, load
  flag, `Log V6 · KilterBoard 40°`, tonight's rows, and the all-time histogram (max bar in `data`).
- **2.6 Review** (`3c`): chip groups, pain chips (tap cycles 0→10, long-press opens a 0–10 Menu), `+ new pain`,
  score `Slider` 0–10 step 0.1, note, and a pinned **Save review**.
- **2.7 Saved**: `7.4, above your 6.8 average`, then ChipTrendPanel, Body log / Dashboard, Update review. Saving
  ends the session and the Live Activity.

### Small sheets
- **2.8 Pain check-in**: opaque paper sheet, `.height(520)` / `.large`. It shows an 11-cell 0–10 row per active
  injury, `ALSO WATCHING` rows, and `+ New pain`. Writes PainEntry rows with `sessionId = nil`.
- **2.9 Rehab today**: `.height(500)`. Each tap saves immediately, with a toast and a live adherence strip.

## 4. Settings tab (4.1–4.6)

The 5th tab root is a `NavigationStack { Form }`, `.formStyle(.grouped)`, `.scrollContentBackground(.hidden)` over
the `grouped` token. The large title "Settings" is in Newsreader, and section headers are mono caps. The `+` and
tab bar float over it like any tab.

| Section | Rows |
|---|---|
| Appearance | `Picker` segmented: System / Light / Dark → `.preferredColorScheme(nil/.light/.dark)` at root. **This is the only appearance control in the app.** |
| Accent | preset dots **Ink (default) · Moss `#4a6b3a` · Cobalt `#2c55c7` · Ochre `#b07a12` · Plum `#7a3f73`** + custom `ColorPicker("Custom", selection:, supportsOpacity:false)` as a rainbow dot; a preview row: a mini bar chart, `+` and Send, all in the accent |
| Privacy | **Face ID lock** `Toggle` · **Require Face ID** `Picker` Immediately / After 1 minute / After 15 minutes |
| Climbing | Gyms & boards (push, 4.4) · Dashboard range. Footer: "Competitions, the season calendar and your weekly target live in Plan → Season." |
| Data | Export backup (`fileExporter`, JSON) · Import backup (`fileImporter`, confirm replace) · Reset to demo data… (`confirmationDialog`) |
| About | Version, climbs logged |

Footers (copy is final):
- Accent: "Used for the tab bar, the + button, primary buttons and every chart. Injury red and hold colours never
  change."
- Accent when near red (4.3), shown in red: "This colour is close to the injury red. Charts will use it too, so
  pain bars and load flags may be harder to tell apart."
- Privacy: "Asks for Face ID when you open Ascent and hides the app in the app switcher. While the lock is on and
  your iPhone is locked, widgets and the live session show only session counts, your streak and weeks to the next
  comp."
- Data: "**Stored only on this iPhone.** No account, no iCloud. Nothing leaves this phone unless you export it.
  Export a backup before you delete the app."

**Accent propagation**

| Takes the accent | Stays ink | Never changes |
|---|---|---|
| Selected tab · `+` tint + live ring · no-DI timer dot · Live Activity timer and primary button · primary content buttons (Send, Start session, Save review, Log V…, Resume, Add comp) · selector hero tile · comp day in the calendar and the phase-bar flag · `Toggle`, `Slider`, `DatePicker`, links · **all chart/data marks** (`data` token: pyramid flashed segment, heatmap, chip-trend cells, adherence, board histogram max, load bars, widget data marks) | Text · selection state (chips, grade cells, segments, intent tiles, swatch ring, selected calendar date, today ring) · borders · empty tracks | Injury red (panels, pain chips and bars, DUE, load flags) · hold/tag colours · system destructive red |

- `data` is always the accent. With Ink it is identical to the web.
- Stored as hex in App Group `UserDefaults` (`accentHex`, empty = Ink). Ink resolves per scheme (`#17150f` light,
  `#ece6d8` dark).
- Legibility guard: lift the accent in dark mode, or darken it in light mode, until contrast against `paper` is at
  least 3:1. `onAccent` = ink when relative luminance > 0.42, otherwise white.
- **Near-red warning**: if CIEDE2000(accent, `#c0392b`) < 20, show the red footer. Nothing is blocked.

## 5. Face ID lock (5.1–5.5)

- `LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your climbing log")`. iOS
  supplies the passcode fallback. `NSFaceIDUsageDescription`: "Ascent uses Face ID to keep your climbing and injury
  log private."
- Turning it on requires one successful evaluation. If `canEvaluatePolicy` fails, the toggle is disabled with
  "Set up a passcode in iOS Settings to use the lock." If Face ID is not enrolled, the row reads "Passcode lock".
- **Lock screen (5.1)**: a full-screen paper overlay above everything (tabs, sheets). It shows the `ASCENT`
  wordmark, Newsreader 30 "Your log is locked", micro `STORED ONLY ON THIS IPHONE`, a glass accent capsule
  **Unlock with Face ID**, and a **Use passcode** link. It auto-evaluates on appear.
- **Relock**: record the time on `.background`. On `.active`, lock if the elapsed time is at least the Require
  interval. Cold launch always locks.
- **Privacy cover (5.5)**: whenever `scenePhase != .active` and the lock is on.
- The Face ID lock flag is mirrored to App Group defaults as `privacyLock`. Widgets and the Live Activity read it
  (§6).

## 6. Widgets

**Storage** *(as built: a single Codable JSON file, `ascent-log.json`, in the App Group container, in the same
format as the web backup export, instead of SwiftData. Still local-only, no CloudKit.)*: SwiftData store in the App
Group container, `cloudKitDatabase: .none`. The widget extension reads it
through the shared domain package, so values are recomputed, never stored. Call `reloadAllTimelines()` after
writes. Keep file protection at `completeUntilFirstUserAuthentication`.

**Redaction follows the Face ID lock. There is no separate toggle.** When `privacyLock == true`, sensitive views
use `.privacySensitive()` and redact while the device is locked. When it is off, full content always shows.

**Limited (locked)** shows sessions this week, the Mon–Sun strip, the weekly streak, and **weeks to the next comp**
(no name). **Hidden**: grades, gym names, flash rate, pyramid, Camp5 tags, injuries, pain, rehab, and comp name.

| Family | Unlocked | Locked |
|---|---|---|
| `systemSmall` (also StandBy) | `THIS WEEK · TOP`, Newsreader 52 top grade, `Batuu · ▲ +1`, `3 SESSIONS · 21 SENDS`, red `REHAB DUE · 2/10` | `THIS WEEK`, Newsreader 52 session count, week strip, `5-WEEK STREAK` |
| `systemMedium` | top grade + flash rate, week strip; mini pyramid 13–9, red `L RING 2/10 · 9-DAY REHAB` | count, strip, `5-WEEK STREAK · COMP IN 6 WK`; redaction bars + "Unlock to see grades and the body log" |
| `systemLarge` | 3 KPIs, pyramid 13–8, Camp5 strip, footer: injury + rehab / next comp + weakest readiness | count + streak, strip, redaction bars, `NEXT COMP · 6 WEEKS OUT`, "Unlock for details" |
| `accessoryCircular` | `Gauge` = sessions / weekly target (**4**; the taper-scaled target in taper weeks), centre top grade + `TOP` | same ring, centre `3` + `OF 4` |
| `accessoryRectangular` | `ASCENT · BATUU` / `Top 12 · 21 sends` / `Rehab due · L ring 2/10` | `ASCENT` / `3 sessions this week` / `5-wk streak` + redacted span |
| `accessoryInline` | `Top 12 · 3 sessions · rehab due` | `3 sessions this week` |

- Home widgets use `paper`/`ink` + `.containerBackground(for: .widget)`. Data marks use the accent and are
  `.widgetAccentable()`. Lock Screen families are monochrome.
- Taps: Home widgets → `ascent://today`. Rehab line → `ascent://rehab`. Accessory widgets → `ascent://log`.

## 7. Tokens

### Colour
| Token | Light | Dark | Use |
|---|---|---|---|
| paper | `#f5f2ea` | `#12110e` | ground, opaque sheets, Live Activity background |
| card | `#ffffff` | `#1d1b17` | chips, cards, fields, grade cells |
| ink | `#17150f` | `#ece6d8` | text, selection fill |
| muted | `#6f6a5e` | `#a39c8c` | secondary text |
| faint | `#a09a8c` | `#6e6859` | tertiary, empty |
| rule / ruleStrong / ruleChip | ink 12 / 22 / 16 % | ink 12 / 24 / 18 % | hairlines, outlines, chip border |
| track | ink 6 % | ink 7 % | empty bars, PEAK calendar days |
| worked | ink 20 % | ink 26 % | pyramid worked, non-max bars, COMP WK hatch |
| warn | `#c0392b` | `#e5594c` | injury only |
| warnBg / warnBorder | warn 7 / 40 % | warn 12 / 50 % | red panels |
| watch | `#f2c744` | `#f2c744` | watching injuries |
| grouped / groupedRow | `#ece8de` / `#fbfaf6` | `#0d0c0a` / `#1d1b17` | Settings Form |
| accent / onAccent | user (default ink) | user, contrast-lifted | §4 |
| **data** | **= accent** | **= accent** | every chart mark |
| hold colours | vocab.ts hexes | unchanged (black/white get an inner `ruleStrong` hairline) | |

### Type (bundle the three OFL families; `Font.custom(_:size:relativeTo:)`)
| Role | Face / size | relativeTo |
|---|---|---|
| Large title | Newsreader 36 | `.largeTitle` |
| KPI / hero numerals | Newsreader 40 (widgets 52) | `.largeTitle` |
| Screen hero line / comp name | Newsreader 26–28 | `.title` |
| Section title / month header | Newsreader 20–21 | `.title3` |
| Body | Archivo 14–15 | `.subheadline` |
| Calendar day | Archivo 15 | `.body` |
| Chip | Archivo Medium 13 / 14 | `.subheadline` |
| Button | Archivo SemiBold 15 | `.headline` |
| Micro label | IBM Plex Mono 10.5 caps +12 % | `.caption2` |
| Data mono / timer capsule | IBM Plex Mono 11–12 | `.caption` |
| Grade cell | IBM Plex Mono Medium 17 | `.body` |
| System (tab labels, Form, alerts, Dynamic Island) | SF | system |

At accessibility sizes the heatmap and KPI grid reflow to one column (`ViewThatFits`), chips wrap, and the
calendar switches to a week-row list.

### Spacing & shape
Gutter 16 · band 20 · stacks 6 / 8 / 10 / 14 / 18 · tap ≥ 44 × 44 (hold cells 40 × 48, contiguous; calendar cells
≈ 51 × 46) · content radius **0** · on-glass radius 22 · glass controls capsule/circle · system radii for sheets,
Form, alerts and the Live Activity.

## 8. SwiftUI API map
| Need | API |
|---|---|
| Tabs | `TabView(selection:)` + 5 × `Tab(_:systemImage:value:)`; `.tabBarMinimizeBehavior(.onScrollDown)` |
| `+` | overlay `Button` + `.glassEffect(.regular.tint(accent).interactive(), in: .circle)`, `GlassEffectContainer`, `.matchedTransitionSource` |
| No-DI timer | glass capsule overlay, `Text(timerInterval:countsDown:false)`, shown when `safeAreaInsets.top < 51` |
| Live Activity | ActivityKit `ActivityAttributes` + `ContentState`; `ActivityConfiguration` with `DynamicIsland { expanded / compactLeading / compactTrailing / minimal }`; `LiveActivityIntent` buttons; `.activityBackgroundTint`; `.privacySensitive()` |
| Selector | `.sheet` + `.presentationDetents([.height(452)])` + `.navigationTransition(.zoom(sourceID:in:))` |
| Plan segment | custom square segment (content layer) bound to `@SceneStorage("planSegment")` |
| Calendar | custom `LazyVGrid` month views in a `ScrollView` (content layer; phase shading needs custom cells); the comp form uses `DatePicker(.graphical)` |
| Log sheet | `.sheet` `.large`, inner `NavigationStack`, `.safeAreaInset(edge: .bottom)` |
| Haptics | `.sensoryFeedback(.success)` on send and save; `.selection` on grade, colour, chip and date |
| Settings | `Form`, `Picker(.segmented)`, `ColorPicker(supportsOpacity:false)`, `Toggle`, `confirmationDialog`, `fileExporter` / `fileImporter` |
| Appearance | `.preferredColorScheme(_:)` at the root, from `@AppStorage(store: groupDefaults)` |
| Lock | `LAContext.evaluatePolicy(.deviceOwnerAuthentication)`, `@Environment(\.scenePhase)` |
| Persistence | *As built:* Codable JSON file in the App Group container (web backup format), no CloudKit |
| Widgets | WidgetKit small/medium/large + accessory families, `.privacySensitive()`, `.widgetAccentable()`, `.containerBackground(for: .widget)`, `Gauge` |

## 9. Resolved decisions (user approved the defaults, 29 Sep 2026)
1. **Taper numbers**: A comp = PEAK 90%, TAPER 70%, COMP WK 50%, last hard session 4 days out, rest the day
   before. B comp = one 70% week, last hard session 3 days out. C = rest the day before. These are fixed per
   priority; they are not editable per comp in v1.
2. **Comp fields**: exactly the §3.5 table. No fee, deadline, reminders or result logging in v1 (Comp detail may
   show an optional result, as described in §3.4; skip it if time is short).
3. **Near-red accent**: warn only (red footer). Never block the colour.
4. **Live Activity privacy**: locked + Face ID lock on shows the timer and sends only. Gym, intent, high and
   flashed are redacted.
