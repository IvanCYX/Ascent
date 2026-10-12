# Ascent iOS: Design Spec (r3)

> **Status: DRAFT, for review.** Decided with the user on 12 Oct 2026. Nothing in this revision is built yet.
> r2 (paper and ink, approved 29 Sep 2026) is in git history; this file replaces it.

Build from this spec and the r3 design canvas (Artifact: https://claude.ai/artifact/JzmnogQNGYm7oxoZesVzAp).
Board names (`Today · dark`, `Load detail`, …) refer to the canvas. Target **iOS 26, SwiftUI, iPhone portrait
first**. Domain rules, vocabulary and metrics in `README.md` and `AscentCore` survive unless §5 says otherwise.

**r3 in one paragraph.** The app keeps its features, tabs and `+`, but drops the editorial paper look for a
Whoop-style structure: dark by default, one sans for text and a wide grotesk for numbers, rounded cards, three
pillar rings on Today, and every deep chart one tap away. Hold colours stay the only rainbow in the app. Logging
gets a real attempt counter. A new **Load** metric compares your last 7 days with your 4-week average, weighted by
grade relative to a **normal grade** you set.

---

## 0. Identity

- **Dark first, light kept.** Dark is the default appearance, on a near-black neutral grey ground (`#0A0A0A`), not pure black.
  Light is a warm stone neutral (off-white ground, white cards), not paper. Both modes use one layout; only tokens change (§7).
- **Surfaces, not rules.** Content sits in rounded cards (radius 22) on the ground colour. No hairline bands,
  no square boxes, no 2 pt borders.
- **Numbers are the hero.** Big values use Archivo at 125 % width, bold, tabular. Everything else is SF Pro.
- **Colour has jobs** (§7.2). The user accent draws normal state, every chart mark and the next action. Amber
  means caution. Injury red means a warning or anything about the body. Hold and tag colours never change and
  are the only other saturated colours. There is **no green "good"** state, so a green hold never reads as status.
- **Glass stays for controls.** The tab bar, the `+`, toolbar buttons, sheets and toasts use system glass. Cards
  never get a second glass layer.

### Copy rules
- Short, sentence case, at a glance. No mono caps micro labels. Section titles are plain words ("Last 7 days").
- Avoid `·` chains. Use a comma or a second line. A single `·` is allowed in tight places (widgets, Live Activity).
- **One insight per screen**, in a tinted row, never under every chart.
- Deltas are small chips: `+1`, `−0.3`, `Flat`. Neutral chip for good or flat, amber chip for worse. No ▲ ▼ arrows.
- Keep the vocabulary in `Vocab.swift` exactly, except the tick labels in §5.1.

## 1. Information architecture

```
TabView (5 tabs, floating glass bar)                   + (floating glass button, unchanged from r2)
├─ Today      pillars, live card, last 7 days,          └─ Quick add (sheet sized to its tiles)
│             one insight, up next                          ├─ Gym send / Board send → Log sheet
│   ├─ push: Load detail                                    ├─ Start session          → Start → Log
│   ├─ push: Progress detail (all deep charts)              ├─ End and rate           → Review
│   └─ Body pillar → selects Body tab                       ├─ Pain check-in / Rehab done → small sheets
├─ Plan       Today | Season (unchanged structure)          └─ Plan → selects Plan tab
├─ History    how sessions felt, session list → Session detail → Review
├─ Body       body map, active injury, rehab, load rules, watching
└─ Settings   Appearance, Accent, Training (normal grade, weekly target), Privacy, Places, Data
```

- Tab, `+`, deep link and pop-to-root behaviour are unchanged from r2.
- **Moved off Today**: KPIs, range segment, send pyramid, Camp5 tally, boards, heatmap, comp readiness → Progress
  detail. Recent sessions → History only. Injury watch → the Body pillar plus the Body tab.

## 2. Tab bar and `+`

**Unchanged in position, size and behaviour** (r2 §2 and the handoff's measured offsets): 58 pt circle, centred,
10 pt above the bar, lifts 8 pt while the 2 pt live ring shows, follows `router.barHidden`. Only colours change:
fill = accent, glyph = `onAccent`. The tab bar keeps the app-driven hide on scroll.

Live Activity, Dynamic Island and the no-Dynamic-Island timer capsule are unchanged from r2 except tokens: the
Lock Screen card uses the `surface` token and an Archivo timer instead of paper and Newsreader.

## 3. Screens

Common: gutter 16, card radius 22, card padding 18, 12 pt between cards. Tab roots use a 34 pt SF Pro Bold large
title with a 15 pt secondary subtitle (plain sentence, e.g. "Monday 12 October"). Pushed screens use a glass back
button and a 17 pt semibold inline title.

### 3.1 Today (`Today · dark`, `Today · light`)
No toolbar items. Order:
1. **Pillars card**: three columns, each a 96 pt ring (8 pt stroke) with the value centred, then a 15 pt name and
   a 12 pt secondary line. Each column is a button: Load → Load detail, Progress → Progress detail, Body → Body tab.
   States in §4 and on `Pillar states`.
2. **Live session card** (only while a session runs): accent dot + "Live at Batuu", intent on the right, a 44 pt
   Archivo timer, three stats (sends, high, flashed), and a full-width accent **Resume** capsule.
3. **Last 7 days**: one bar per day (rest days are 4 pt stubs), today in full accent, the other days at 55 %
   accent, and a dashed line at your average daily load. Right note: "N sessions". Tap → Load detail.
4. **One insight**: icon disc, a one-line headline, a secondary line, chevron. It picks the most notable read
   (pyramid read, chip pattern, Camp5 next tag, a comp readiness gap) and taps through to where it came from.
5. **Up next**: "Up next" label, plan day on the right, the session title (20 pt bold), block summary, and, if a
   load rule bites, an inline red row ("Crimpy off: 2 of 2 this week"). Tap → Plan.

Target length: about 1.5 screens on iPhone 17.

### 3.2 Load detail (`Load detail`)
- 196 pt ring (14 pt stroke) with the % and "of your usual week", then "Last 7 days against your 4-week average".
- **Range bar**: Light (under 80 %), in range (80 to 130 %), amber zone (over 130 %), with an accent marker.
- **Weekly load**: 8 weekly bars with a dashed baseline. A week over 130 % of its own baseline is drawn amber.
- **What counted**: this window's sessions, each with sends, attempts and its load value.
- **Your normal grade** row → Settings › Your normal grade.

### 3.3 Progress detail (`Progress detail`)
- Range segment `8 weeks | 6 months | Season` (system-style rounded segment). Persists `dashboardRange`, and also
  sets the range for the Progress pillar on Today.
- **Key numbers**, 2 × 2 cards: Top grade, Flash rate (grade 8 and up), Tries per send (10 and up), Hard sends
  (10 and up). Each has a delta chip against the previous range.
- **Send pyramid** 13 → 7: rounded tracks, worked at 40 % accent, flashed in full accent, counts on the right.
  The screen's one insight sits under it.
- **Camp5 colours**: 8 rounded bars in hold colours, counts above, codes below, a 4 pt stub for zero.
  Right note: "Next up: <tag>". **No numbers ever.**
- **Boards**: one row per board and angle, delta chip, V grade in Archivo.
- **Where you send**: style × grade band heatmap, cells at accent alpha `0.07 + pct × 0.78`, empty cells in the
  raised surface colour.
- **Comp readiness**, N weeks out: meters, amber below 55. Tap → Plan › Season.

### 3.4 Quick add (`Quick add`)
Same tiles and logic as r2's selector, restyled: the sheet floats 8 pt from the edges with radius 38, the detent
fits the content (no empty space under the tiles), tiles are radius 22 on a raised surface, and the hero tile is
filled with the accent. Pain and rehab subtitles are red. Zoom transition from the `+` stays.

### 3.5 Log a send (`Log a send · dark` is clickable, `Log a send · light`)
Order inside the sheet: header (close, "Log a send" + live timer, gym menu) → `Gym | Board` segment →
**Grade** (top ten, "Show 1 to 15") → **Colour** ("Optional" at numbered gyms; at Camp5 the tag *is* the grade
and stays required) → **Style** chips (multi) → **Not sent** switch → **Where** field → **This session** (latest
three rows, swipe to delete).

**Pinned bottom bar** (always visible, `.safeAreaInset(edge: .bottom)`):
`[ − n + ]  label / hint  ……  [ Send ]`
- `n` starts at **1**, and the label reads **Flash**. `+` gives 2 = "2nd go", 3+ = "N tries". `−` stops at 1.
- With **Not sent** on, the label reads "N attempts" and the button reads **Log**.
- Send is disabled (35 % opacity) until a grade is picked. A grade tap plus Send is the two-tap normal log.
- After every save: `.sensoryFeedback(.success)`, the row is inserted, a toast "Logged 11, Flash · Undo" shows
  for 4 s above the bar, and the form resets: grade and colour cleared, styles cleared, `n = 1`, Not sent off.
- The board log uses the same bar and counter.

### 3.6 Plan (`Plan`)
Structure and taper engine unchanged from r2 §3.2–3.4 and the taper table (kept in §9 below). Restyle:
- System-style `Today | Season` segment.
- Session card: day label, 26 pt title, intent pills in a horizontal row (selected = accent).
- Blocks card: duration in Archivo on the left, title and target on the right. The emphasis block gets an accent
  **Focus** chip instead of a 2 pt border. Blocked focus styles are struck through with the red inline row. Rehab
  block titles are red.
- Total in Archivo, a full-width accent **Start session**, and a "This week" card with one dot per target session.
- Season: the calendar keeps its rules, but cells become rounded (radius 10). Today = accent ring, selected =
  raised fill, comp day = accent fill. Phase shading uses surface tints instead of hatching.

### 3.7 History (`History`)
- Filter button in the toolbar. Title "History", subtitle "N sessions".
- **How sessions felt**, last 12: one row per chip with 12 dots. Positive chips fill accent, negative chips
  (Felt weak, Fatigued early, Poor recovery, Distracted, Hesitant, Scared of the fall, Missed the timing, Sloppy
  feet, Read beta wrong) fill amber. The screen's one insight sits below.
- Session list grouped by week: date block (Archivo day + weekday), gym, then "intent, N sends, high X", and the
  review score on the right. A live session shows an accent **Live** chip. Camp5 highs show the tag name, never a
  number.
- Session detail and Review: same content as r2 §3.7 and 2.6, in cards with the new type.

### 3.8 Body (`Body`)
- Toolbar **Log new**. Subtitle "1 active, 2 watching".
- **Body map card**: compact figure (about 92 × 132 pt) with the legend beside it. Active = injury red,
  watching = amber (replaces r2's yellow, which clashed with the yellow hold). Tap an area to filter.
- **Active injury card**: name, diagnosis and rehab week, `•••` menu, the latest pain in Archivo with a delta chip,
  the pain chart (red bars, latest strongest), and **Pain today**, 11 buttons 0–10, 44 pt tall.
- **Rehab today**: checklist with red check circles, right note "N of 7 this week". Tap toggles and saves.
- **Load rules**: one row per rule with a usage chip: red when used up, amber when one left.
- **Watching**: rows with an Escalate action (unchanged).

### 3.9 Settings (`Settings`) and Your normal grade (`Settings › Your normal grade`)
Grouped cards on the dark ground.

| Section | Rows |
|---|---|
| Appearance | segmented System / Light / Dark. **Default Dark.** |
| Accent | Ink (default), Moss, Cobalt, Ochre, Plum, Custom (`ColorPicker`). One line under it: "<name>. Colours the tab bar, buttons and charts." |
| Training | **Your normal grade** (push) showing "10, Green, V5" · **Weekly target** (moved here from Season; the Season stepper stays as a shortcut) |
| Privacy | Face ID lock switch, "Also hides details in widgets and the Live Activity." Require-after picker unchanged. |
| Places | Gyms and boards (push) |
| Data | Export backup, Import backup, Clear everything (red), Reset to demo data |

**Your normal grade**: one line of explanation ("Load counts climbs above this more, and below it less."), then
three cards:
- **Numbered gyms**: − value + stepper over the 1–15 spine. "Suggested N, from the last 4 weeks".
- **Camp5 tags**: the 8 tag swatches, single select, ring on the selected tag.
- **Boards**: − V + stepper.
- Footer: "Changes apply to all past Load."

## 4. The three pillars

All three are derived on the fly from the log. Nothing new is stored except the normal grades and real attempt
counts. Rings: 8 pt stroke, track = `raised`, start at 12 o'clock, clockwise. Over 100 % draws a second lap on
top with a 3 pt cut-out at its tip (Apple Activity style), capped at 200 %. Ring and number animate on appear (§6).

### 4.1 Load
- **Per climb**: `load = attempts × 2^((g − normal) / 2)`, where `g` and `normal` are on the climb's own scale:
  - numbered gyms: the gym-adjusted grade (`Metrics.adjustedGrade`, so BHUB's −0.5 offset holds) vs the
    numbered normal grade
  - Camp5: the tag's index in `Vocab.camp5Tags` vs the normal tag's index (one tag counts as one step)
  - boards: V number vs the normal V grade

  Normal = 1×, 2 above = 2×, 2 below = 0.5×. **Not-sent attempts count too.**
- **Acute** = the sum over the last 7 days, today included.
- **Baseline** = the sum over the 28 days before that window, ÷ 4.
- **Load %** = acute ÷ baseline. Bands: under 80 % **Light**, 80–130 % **In range**, over 130 % **Spiking**
  (amber ring and caption).
- **Building baseline**: until the log has 28 days of history before the acute window, the ring shows a muted
  dashed partial ring with "N/4" in the centre ("2 of 4 weeks") instead of a percentage.
- Changing a normal grade recalculates everything; nothing is cached.

### 4.2 Progress
- Centre: the top numbered grade sent in the Progress range (`maxGradeSent`) with a delta chip against the
  previous range of the same length.
- Ring: hard sends (`volumeAtHard`, 10 and up) this range ÷ the previous range. 100 % = matched, a second lap =
  beat it. No hard sends: an empty ring and "–".
- Caption: "N hard sends".

### 4.3 Body
- Centre: the latest pain entry of the active injury ("2/10"). With several active injuries, use the worst state.
- Ring: rehab adherence this ISO week (done ÷ due). Caption "Rehab N of M".
- Colour: **red** if any load rule for the injury is used up this week; otherwise **amber** if the latest pain is
  higher than the entry before it, or a rule has one use left; otherwise accent.
- No active injury: centre "Clear", full accent ring, caption "No active injury".

## 5. Domain changes

### 5.1 Real attempt counts
- `Climb.attempts` already exists. It becomes the real count from the counter. `tickType` is **derived** on save:
  Not sent → `.attempt`; 1 → `.flash`; 2 → `.secondGo`; 3 or more → `.project` (raw value kept for backup
  compatibility).
- Display labels: Flash, 2nd go, "N tries", Not sent ("N attempts"). In `Vocab.tickTypes`, "Attempt only" becomes
  "Not sent"; the Project chip is gone from logging.
- Metrics that already read `attempts` (tries per send) become accurate with no formula change.
- **Existing data is left alone**: old climbs keep their inferred 1/2/3 counts. Nothing is migrated destructively.

### 5.2 Normal grades
- App Group defaults: `normalNumbered: Int?`, `normalTag: String?` (a Camp5 tag id), `normalV: Int?`.
- Suggestion = the median sent grade on that scale over the last 28 days, rounded. Unset values use the
  suggestion. With no sends on a scale, its climbs are skipped for Load until it has a value, and the row reads
  "Not set".
- Included in Export backup as an optional `settings` block. Import accepts files with or without it.

### 5.3 New metrics in `Metrics`
`climbLoad`, `loadWindow(today:)` → `{acute, baseline?, pct?, weeksOfBaseline}`, `weeklyLoad(weeks:)`,
`progressPillar(range:)`, `bodyPillar(today:)`, `suggestedNormal(scale:)`. Unit-test each against the demo seed,
including the baseline-building case and Camp5 tag steps.

## 6. Motion and haptics
- Rings draw from 0 on first appear per launch (`.smooth(duration: 0.9)`, staggered 80 ms), numbers use
  `.contentTransition(.numericText())`. Respect Reduce Motion (no draw; fade only).
- Pillar cards and the Last 7 days card use `.matchedTransitionSource` with `.navigationTransition(.zoom)` into
  their detail screens.
- `.sensoryFeedback(.success)` on every write (send, pain, rehab, review, comp). `.selection` on grade, colour,
  chip, counter step and segment changes.
- The log toast slides up from the bar with `.spring(.snappy)`.

## 7. Tokens

### 7.1 Colour
| Token | Dark | Light | Use |
|---|---|---|---|
| ground | `#0A0A0A` (near-black neutral grey) | `#F5F5F4` (warm stone, chosen by the user) | screen background |
| surface | `#161616` | `#FFFFFF` | cards, Live Activity background, widgets |
| raised | `#1F1F1F` / tracks `#262626` | `#ECEBE8` / tracks `#E7E6E3` | segments, grade tiles, inputs, empty ring and bar tracks |
| tile | `#2A2A2A` | `#ECEBE8` | quick-add tiles, toast |
| sheet | `#121212` | `#FAFAF9` | log sheet |
| text | `#F2F3F5` | `#0E1013` | primary text |
| secondary | `#A1A1A1` | `#5F5E5A` | secondary text (≥ 4.5:1 on surface) |
| tab bar | `rgba(32,32,32,0.86)` glass | white 88 % glass | floating tab bar fill |
| hairline | white 6 % | ink 7 % | list row separators inside cards only |
| accent / onAccent | user, default Ink = `#F2F3F5` | user, default Ink = `#0E1013` | §7.2 |
| caution | `#F5A524` (text `#F5B850`) | `#B86E00` | amber: spiking load, rising pain, worse deltas, readiness < 55 |
| injury | `#E5594C` (text `#F08A80`) | `#C0392B` (text `#A8301F`) | anything body or warning |
| hold colours | `Vocab.holdColours` | same | holds and Camp5 tags; black and white get a 1 pt inner outline |

Accent presets are contrast-lifted per scheme as in r2 (at least 3:1 against `surface`). The near-red warning
stays, and a matching **near-amber** warning (CIEDE2000 < 20 against caution) shows a footer on Ochre and similar
picks. Warn only, never block.

### 7.2 Colour roles
| Accent | Caution (amber) | Injury red | Never changes |
|---|---|---|---|
| Selected tab, `+`, primary buttons, selected grade / chip / pill, switches, ring fills in normal state, all chart marks, Live chip, Focus chip | Load over 130 %, Body pillar pain rising or one rule use left, worse delta chips, readiness under 55, negative session chips, watching injuries | Body pillar with a rule used up, injury panels, pain bars and buttons, rehab checks, load-rule rows, Clear everything | Hold and tag colours |

### 7.3 Type
| Role | Face | Size |
|---|---|---|
| Large title | SF Pro Bold | 34 (`.largeTitle`) |
| Hero number (detail ring, timers) | Archivo Bold, width 125 % | 44–50 |
| Pillar value, KPI | Archivo Bold, width 125 % | 22–34 |
| Inline numbers (counts, grades, durations) | Archivo Bold, width 125 % | 13–22 |
| Card title | SF Pro Semibold | 17 |
| Body / row title | SF Pro Regular / Semibold | 15–16 |
| Secondary | SF Pro Regular | 12–14 |
| Tab labels, Form, alerts, Dynamic Island | SF (system) | system |

- Bundle the Archivo variable font with its width axis; drop Newsreader and IBM Plex Mono.
- Every custom size uses `relativeTo:` so Dynamic Type works. At accessibility sizes the pillars stack as rows,
  KPI and heatmap grids go to one column, and the calendar switches to week rows (as in r2).

### 7.4 Shape and spacing
Gutter 16 · card radius 22, padding 18, gap 12 · tiles and grade cells radius 14 · chips and buttons capsule ·
segments radius 12 (inner 9) · sheet radius 38 · tap targets at least 44 × 44 (colour dots 36 pt inside a
44 pt hit area).

## 8. Widgets, Face ID lock, Live Activity
Content, privacy and families are **unchanged from r2 §5–6**. Restyle only:
- Widgets use `surface` + `.containerBackground(for: .widget)`, Archivo numbers instead of Newsreader, and
  accent data marks (`.widgetAccentable()`).
- Lock screen overlay: `ground` background, the "Ascent" wordmark in Archivo at 125 %, "Your log is locked"
  in SF Pro Bold 28, and an accent **Unlock with Face ID** capsule.
- Live Activity Lock Screen card: `surface` tint, Archivo timer.

## 9. Kept from r2 without change
Taper engine and phase table, Add comp sheet fields, comp detail, Session detail content, Review flow, small
sheets (pain check-in, rehab today), deep links, storage (one Codable JSON file in the App Group, no cloud), and
the resolved decisions in r2 §9. See r2 in git history for their full text.

## 10. Open items for the user
1. **Load window.** The spec uses the last 7 days rather than the calendar week, so Load doesn't drop to near
   zero every Monday.
2. **Camp5 tag weighting.** One tag step counts as one grade step in the Load weight. It may need to be 1.5 or 2
   if tags span more than one grade.
3. **Ochre vs amber.** Ochre stays a preset, with a near-amber warning. The alternative is to replace it.
4. **Removed from Today:** comp readiness (now in Progress detail) and recent sessions (History only).
