# Ascent

A single-user bouldering progress tracker for your iPhone. It answers one question: **am I actually
improving?** It also supports comp prep: it exposes style-specific weaknesses, tracks session intent
and how each session felt, and keeps an injury and rehab log whose load limits feed back into planning.

It covers several Malaysian gyms that each grade differently, plus KilterBoard and TensionBoard 2 on
the V-scale.

Ascent is a native SwiftUI app for iOS 26. It stores everything on the phone: no account, no server,
no iCloud.

## The iOS app

| Tab | What it is |
|---|---|
| **Today** | A short summary: three pillar rings (Load, Progress, Body), the live session, the last 7 days, one insight and up next. Load opens Load detail (weekly load and what counted). Progress opens Progress detail: key numbers, send pyramid, Camp5 colours, boards, style × grade heatmap and comp readiness |
| **Plan** | *Today*: session intent picks the blocks, load rules strike out blocked focus styles, and the plan shortens automatically in a taper. *Season*: calendar, competitions, the taper plan and the weekly session target |
| **History** | Chip trends over the last 12 sessions, plus the full session ledger with session detail |
| **Body** | Injury and rehab: body map, pain trend, adherence, rehab protocol, load rules |
| **Settings** | Appearance, accent colour, training (your normal grade per scale, weekly target), Face ID lock, gyms and boards (add a gym on numbers, colour tags, V or French routes; tap a gym to edit it), backup export and import |

**Quick add.** A floating `+` above the Liquid Glass tab bar opens a selector for the next action:
start a session, log a gym or board send, end the session, check in pain, tick off rehab, or
open the plan. Logging a send, the Camp5 tally, board climbs and the review all live in one sheet.
Each climb records a real attempt count from a pinned `[ − n + ]` bar: 1 is a flash, 2 a second go,
3 or more "N tries". At a gym, pick any styles that apply (heel and toe hooks included) and turn on
"Not sent" to log attempts on a climb you didn't top. On a board there are no styles: set the angle on a
10° to 70° slider (it starts at 40°) and pick Flash, 2nd go, Project or Attempt only; the count follows,
and you can type it for a long project. The bar resets to Flash after every save. "How did that feel?"
only opens after End session, which asks first and stops the timer.

**On the phone:**
- A Live Activity runs during a session, in the Dynamic Island and on the Lock Screen.
- Home Screen and Lock Screen widgets show your week at a glance.
- The optional Face ID lock also hides details in the widgets and Live Activity while the phone is
  locked, leaving only counts, your streak and weeks to the next comp.
- You pick one accent colour, and it colours the tab bar, primary buttons and every chart.

### Build and run

You need Xcode 26 or later and an iOS 26 Simulator runtime.

```bash
cd ios && xcodegen generate
```

```bash
open ios/Ascent.xcodeproj
```

Pick an iPhone simulator and Run. To run on a real iPhone, set your Team under Signing for the
`Ascent` and `AscentWidgets` targets. The App Group `group.com.ivancyx.ascent` is created
automatically.

The domain and snapshot tests run without Xcode:

```bash
cd ios/AscentKit && ./test.sh
```

### Layout

| Path | What |
|---|---|
| `ios/AscentKit/Sources/AscentCore` | Models, vocab, dates, metrics, taper engine, demo seed, store |
| `ios/AscentKit/Sources/AscentUI` | Theme, components, every screen, the Face ID lock, Live Activity sync |
| `ios/AscentKit/Sources/AscentWidgetsUI` | Widget views and the Live Activity views |
| `ios/Ascent`, `ios/AscentWidgets` | The app target and the widget extension |
| `ios/project.yml` | XcodeGen spec; `xcodegen generate` rebuilds `Ascent.xcodeproj` |
| `design/` | The approved r3 design spec (`DESIGN.md`, which links the design canvas). `draft.html` and `BRIEF.md` are the r2 draft |

**Storage.** One JSON file lives in the App Group container, so the widgets read the same log as the
app. `Settings → Export backup` saves that file, and `Import backup` restores it.

**Status.** The app builds and runs in the iOS Simulator with the r3 design. Face ID, the widgets and
the Live Activity views still need a check on a real device. `HANDOFF.md` lists what's done and what's open.

## The domain rules that matter

- **Numbered gyms share a 1–15 spine.** Batuu runs 1–15, Bump PBJ/J1/SSQ run 1–12 on one scale across
  the three gyms, and BHUB runs 1–10. Each gym carries a soft/hard offset (BHUB is −0.5), so BHUB 10
  and Batuu 10 are not treated as the same climb in aggregate.
- **Camp5 Eco City is ranked, not numbered.** It has eight colour tags, easiest first: pink (VB–V1),
  blue (V0–V2), yellow (V1–V3), orange (V2–V4), green (V3–V5), purple (V4–V6), red (V5–V7) and
  black (V6–V8+). No 1–15 number ever appears for Camp5: not in logging, tables, charts or export.
  Sorting uses the tag's position in that order, and logs saved with the old yellow-first order are
  re-ranked when they load.
- **V gyms and French routes keep their own scales.** A gym can grade in V (VB to V17, like TensionHouse) or in
  French route grades (4a to 9a, like Batuu's rope area). Their climbs are never converted onto the 1–15 spine.
  Progress detail has a scale switch (1–15, V, French, Camp5), and the Today pillar and the widgets follow it.
  Rope climbs are logged like boulders, with the same attempt counter.
- **Boards never merge into the gym pyramid.** They have their own panel and their own max-grade
  metric, and an angle is required.
- **Load rules** are checked both when planning a session and when logging a climb whose style
  matches a rule. Usage is counted per ISO week over *sessions*, not climbs, so one crimpy session
  counts as one use. The warning is always shown inline, never as a pop-up.
- **Pain chips in the review write pain entries** against the injury. The Body pillar on Today and the
  pain chart on the Body tab both read from them.
- **Competitions drive a taper.**
  - An A comp gets PEAK (90%), TAPER (70%) and COMP WK (50%) weeks.
  - A B comp gets one 70% week.
  - A C comp is trained through.
  - Plans scale block times by the week's factor, but rehab blocks are never scaled.

## Derived metrics

Everything is recomputed from the log; nothing is stored pre-aggregated. The Progress range
(8 weeks / 6 months / Season) refilters Progress detail and the Progress pillar.

- **Load**: each climb scores `attempts × 2^((grade − normal) / 2)` against your normal grade on its own
  scale (numbered, Camp5 tag, V gym, French route, or board V), and not-sent attempts count too. One
  Camp5 tag step counts as 2.5 grade steps; one French step (6a to 6a+) counts as half a grade. Load is the last 7 days ÷ (the 28 days before ÷ 4): under 80% is light, over
  130% is spiking. With less than 4 weeks of history it shows "Building baseline N/4". Your normal
  grade per scale is set in Settings and defaults to the median of the last 28 days of sends.
- **Progress pillar**: the top grade in the Progress range with its change, and a ring of hard sends
  against the previous range, on the scale picked in Progress detail. Hard is 10+ on the 1–15 spine and two
  grades above your normal on V and French.
- **Body pillar**: the latest pain, and a ring of rehab days done in the last 7 days. Red when a load
  rule is used up, amber when pain is rising or a rule has one use left.

- **Max grade sent**: highest grade with at least one send in range, offset adjusted.
- **Flash rate**: flashed ÷ total sends, grade 8+.
- **Attempts per send**: mean attempts over sends at grade 10+.
- **Volume at 10+**: sends at grade 10 or above in range.
- **Style send rate**: sends ÷ (sends + not sent) per style × grade band. A `—` means nothing was
  attempted in that cell.
- **Comp readiness (0–100)**: per style, `0.5 × send rate at your top two occupied bands` (normalised
  against 75%), plus `0.25 × how recently you trained that style`, plus `0.25 × signal from review chips`.
  Scores below 55 are flagged and feed the plan's focus list.
- **Rehab adherence**: exercise-days completed ÷ days prescribed over the last 12 days.

## Demo data

The first launch seeds about 26 weeks of realistic sessions, plus a live session in progress, so
every panel has something to show. The data comes from a fixed seed, so it's the same every time.

`Settings → Reset to demo data` regenerates it, and `Settings → Clear everything` starts an empty
log. Export a backup first if you've logged anything real.

## Design

Whoop-style and dark by default, on a near-black neutral grey, with a warm stone light mode. Content
sits in rounded cards. Text is SF Pro and numbers use Archivo at 125% width. Controls and navigation
use Liquid Glass. Your accent draws every chart, amber means caution, injury red is kept for the body
and warnings, and hold and tag colours are the only rainbow. See `design/DESIGN.md` for the full spec.
