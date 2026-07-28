# Ascent

A single-user bouldering progress tracker for several Malaysian gyms that each grade
differently, plus KilterBoard and TensionBoard 2 on the V-scale. It answers one question —
**am I actually improving?** — and supports comp prep by exposing style-specific weaknesses,
session intent, session feel, and an injury/rehab log that feeds load limits back into planning.

Runs on localhost. No auth, no accounts, no server.

## Run it

```bash
npm install && npm run dev
```

Open <http://localhost:5173>.

```bash
npm run build && npm run preview
```

## Stack

React 18 + Vite + TypeScript, with **Dexie (IndexedDB)** for storage — the zero-backend option
the handoff allowed. Everything is one process and one command; data survives restarts, and
`Gyms → Data` has JSON export/import so the log is portable and backup-able. If you later want a
file on disk, `src/db/store.ts` is the only module that talks to the database.

There is no CSS framework. The paper palette lives in `src/styles/global.css` as CSS custom
properties; everything else is plain CSS and inline style objects that mirror the design tokens.

## Screens

| Route | Design id | What it is |
|---|---|---|
| `/` | `2a` | Dashboard — KPIs, send pyramid, Camp5 colour tally, board grades, injury watch, comp readiness, style × grade heatmap, recent sessions |
| `/plan` | `3d` | Session plan — intent picks the blocks, load rules strike out blocked focus styles |
| `/log` | `3a` + `1d` | Quick log — grade → colour → Send; switches to the Camp5 tally mode automatically |
| `/board` | `3b` | Board log — board, angle, V-grade, plus the all-time histogram for that board and angle |
| `/review` | `3c` + `1g` | Session review — chip groups, pain chips, one score; the chip-trend panel appears after saving |
| `/history` | `1g` | Chip trends over the last 12 sessions plus the full session ledger |
| `/gyms` | `3e` | Gyms & grade systems, and the data export/import |
| `/body` | `1k` | Injury & rehab — body map, pain trend, adherence, rehab protocol, load rules |

## The domain rules that matter

- **Numbered gyms share a 1–15 spine.** Batuu 1–15, Bump PBJ/J1/SSQ 1–12 (one scale across the
  three), BHUB 1–10. Each gym carries a soft/hard offset (BHUB is −0.5) so BHUB 10 and Batuu 10
  are not the same climb in aggregate — see `adjustedGrade` in `src/domain/metrics.ts`.
- **Camp5 Eco City is ranked, not numbered.** Eight colour tags, yellow → black. No number ever
  appears for Camp5 — not in logging, tables, charts or export. Sorting uses the tag ordinal.
- **Boards never merge into the gym pyramid.** They have their own panel, their own max-grade
  metric, and an angle is required.
- **Load rules** are evaluated when planning a session *and* when logging a climb whose style
  matches a rule. Usage is counted per ISO week over *sessions*, not climbs — one crimpy session
  is one use. The warn panel is always inline, never a modal.
- **Pain chips in the review write `PainEntry` rows** against the injury; the dashboard sparkline
  and the body log chart both read from them.

## Derived metrics

All in `src/domain/metrics.ts`, all recomputed from the log — nothing is stored pre-aggregated.

- **Max grade sent** — highest grade with ≥1 send in range, offset adjusted.
- **Flash rate** — flashed ÷ total sends, grade 8+.
- **Attempts per send** — mean attempts over sends at grade 10+.
- **Volume at 10+** — sends at grade ≥10 in range.
- **Style send rate** — sends ÷ (sends + attempt-only) per style × grade band; `—` when nothing
  was attempted in that cell.
- **Comp readiness (0–100)** — per style, `0.5 × send rate at your top two occupied bands`
  (normalised against 75%) + `0.25 × recency of exposure` + `0.25 × review-chip signal`.
  Below 55 is flagged and feeds the plan screen's focus list.
- **Rehab adherence** — exercise-days completed ÷ days prescribed over the last 12 days.

The dashboard range switch (8 weeks / 6 months / Season) refilters every panel.

## Demo data

First run seeds ~26 weeks of realistic sessions plus a live session in progress, so every panel
has something to show. It is generated from a fixed seed, so it is the same every time.
`Gyms → Data → Reset to demo data` regenerates it; export first if you have logged anything real.

## Notes on fidelity

Two deliberate departures from the mockups, both to make the app work rather than just look right:

1. The `3a` hold-colour row renders all **nine** token colours; the mockup drew eight and omitted
   black. Black holds exist, and black is in the token list.
2. Review pain chips are generated for **active** injuries only, per the handoff's wording.
   Injuries being watched live on `/body` and can be escalated there.

Everything else — palette, type scale, zero border radius, no shadows, hairline rules, copy — is
as specified. Ink is the only data colour; `#c0392b` is the only accent and is reserved for the
body; saturated colour appears only as hold and tag colours.
