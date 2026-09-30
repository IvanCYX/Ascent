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
| **Today** | Dashboard: KPIs, send pyramid, Camp5 colour tally, board grades, injury watch, comp readiness, style × grade heatmap, recent sessions |
| **Plan** | *Today*: session intent picks the blocks, load rules strike out blocked focus styles, and the plan shortens automatically in a taper. *Season*: calendar, competitions, the taper plan and the weekly session target |
| **History** | Chip trends over the last 12 sessions, plus the full session ledger with session detail |
| **Body** | Injury and rehab: body map, pain trend, adherence, rehab protocol, load rules |
| **Settings** | Appearance, accent colour, Face ID lock, gyms and boards, backup export and import |

**Quick add.** A floating `+` above the Liquid Glass tab bar opens a selector for the next action:
start a session, log a gym or board send, end and rate the session, check in pain, tick off rehab, or
open the plan. Logging a send, the Camp5 tally, board climbs and the review all live in one sheet.

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
| `design/` | The approved iOS design spec (`DESIGN.md`) and the HTML draft of every screen |

**Storage.** One JSON file lives in the App Group container, so the widgets read the same log as the
app. `Settings → Export backup` saves that file, and `Import backup` restores it.

**Status.** The app builds and runs on the iOS 26 Simulator. Face ID, the widgets and the Live
Activity views still need a check on a real device. `HANDOFF.md` lists what's done and what's open.

## The domain rules that matter

- **Numbered gyms share a 1–15 spine.** Batuu runs 1–15, Bump PBJ/J1/SSQ run 1–12 on one scale across
  the three gyms, and BHUB runs 1–10. Each gym carries a soft/hard offset (BHUB is −0.5), so BHUB 10
  and Batuu 10 are not treated as the same climb in aggregate.
- **Camp5 Eco City is ranked, not numbered.** It has eight colour tags, from yellow to black. No
  number ever appears for Camp5: not in logging, tables, charts or export. Sorting uses the tag's
  position in that order.
- **Boards never merge into the gym pyramid.** They have their own panel and their own max-grade
  metric, and an angle is required.
- **Load rules** are checked both when planning a session and when logging a climb whose style
  matches a rule. Usage is counted per ISO week over *sessions*, not climbs, so one crimpy session
  counts as one use. The warning is always shown inline, never as a pop-up.
- **Pain chips in the review write pain entries** against the injury. The dashboard sparkline and the
  body log chart both read from them.
- **Competitions drive a taper.**
  - An A comp gets PEAK (90%), TAPER (70%) and COMP WK (50%) weeks.
  - A B comp gets one 70% week.
  - A C comp is trained through.
  - Plans scale block times by the week's factor, but rehab blocks are never scaled.

## Derived metrics

Everything is recomputed from the log; nothing is stored pre-aggregated. The dashboard range
(8 weeks / 6 months / Season) refilters every panel.

- **Max grade sent**: highest grade with at least one send in range, offset adjusted.
- **Flash rate**: flashed ÷ total sends, grade 8+.
- **Attempts per send**: mean attempts over sends at grade 10+.
- **Volume at 10+**: sends at grade 10 or above in range.
- **Style send rate**: sends ÷ (sends + attempt-only) per style × grade band. A `—` means nothing was
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

Content is paper and ink: square corners, hairline rules, no shadows, and the Newsreader, Archivo
and IBM Plex Mono typefaces. Controls and navigation use Liquid Glass. `#c0392b` is reserved
for injury and body, and hold and tag colours never change. See `design/DESIGN.md` for the full spec.
