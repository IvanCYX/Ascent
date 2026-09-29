# Ascent iOS — Design Brief (for the designer pane)

You are the **designer**. Another Claude session (the **implementer**) is waiting in the pane
next to you and will build exactly what you draw, in SwiftUI, once the user approves your draft.
**Do not write Swift or touch anything outside `design/`.** Your job ends at an approved design.

## Source material

`/Users/ivan_the_cheah/Desktop/Ascent` is a React/Vite web app (read `README.md`, `src/screens/*`,
`src/components/*`, `src/domain/*`, `src/styles/global.css`). It is a single-user bouldering
progress tracker for Malaysian gyms + KilterBoard/TensionBoard. Every screen, metric and domain
rule in the README must survive the port. Read the code — the screens are dense and you need to
know what is on each one to lay it out on a phone.

Current web routes: Dashboard, Session plan, Quick log (gym sends), Board log, Session review,
History, Gyms (+ data export/import), Body (injury & rehab).

Current visual identity: "paper" palette (`--paper #f5f2ea`, ink `#17150f`, muted/faint greys),
serif (Newsreader) + sans (Archivo) + mono (IBM Plex Mono), **zero border radius, no shadows,
hairline rules**, ink is the only data colour, `#c0392b` reserved for the body/injury, saturated
colour only for hold/tag colours. Decide how much of this carries into an iOS 26 Liquid Glass app
and say so explicitly (my suggestion: keep paper/ink editorial identity for *content*, let Liquid
Glass own the *navigation/control layer* — but it's your call).

## What the user asked for (all must appear in the draft)

1. **Full port** of every web screen to an iOS app (iOS 26, SwiftUI).
2. **Bottom nav bar following Liquid Glass conventions** — the iOS 26 floating glass `TabView`
   tab bar — used to move between pages. iOS shows max ~5 tabs; 8 web screens + Settings will not
   fit, so design the information architecture: which are tabs, which are pushed/sheets.
   (Log/Board/Review are natural "actions", not tabs.)
3. **A `+` button on top of the nav bar, centred**, for quick-adding **sends or workouts**. Tapping
   it opens a **selector to choose which activity to quick add** (e.g. gym send, board send,
   start/plan session, rehab exercise, pain check-in — you decide the list from the domain).
   Show: the button at rest, the selector, and at least one quick-add flow end to end.
   Use glass for the button (`.glassEffect(.regular.interactive())`-style), and show how it
   relates to the tab bar (floating above centre, or `tabViewBottomAccessory`, etc. — pick one and
   justify it against HIG).
4. **Settings page**: light / dark / system appearance toggle; **accent colour with a colour
   picker** (SwiftUI `ColorPicker`) — show how the accent propagates (tint, selected tab, charts?)
   and how it coexists with the reserved injury red and hold colours; **Face ID lock** on/off;
   data export/import/reset (moved from Gyms?), gym & board management location.
5. **Face ID app lock** (optional, user toggles it): design the lock/unlock screen, the
   privacy blur in the app switcher, and the fallback (passcode) state.
6. **Widgets — Home Screen and Lock Screen**, which show **limited info when the phone is locked
   and full info when unlocked** (implementation will use WidgetKit `.privacySensitive()` /
   redaction, gated on the Face ID setting). Design each widget in BOTH states:
   - Home: small, medium (and large if worthwhile)
   - Lock Screen: accessoryCircular, accessoryRectangular, accessoryInline
   Decide what "limited" means (e.g. streak / sessions-this-week only; hide grades, injuries).
7. **All data local only** (SwiftData on-device + App Group for widgets, no iCloud/CloudKit).
   Reflect this in Settings copy ("Stored only on this iPhone").
8. **Light and dark mode** for every screen.

## Deliverables (put everything in `design/`)

1. `design/draft.html` — a single self-contained HTML page: a board of iPhone-sized frames
   (≈393×852) for **every** screen and state above, each in light and dark (a toggle on the page
   is fine), plus the widget gallery in locked/unlocked states. Approximate Liquid Glass with
   `backdrop-filter: blur() saturate()` + specular edge highlights. Rough is fine — it's a draft —
   but it must be complete and legible. Annotate frames with short notes.
   Load the `artifact-design` skill and **publish it as a private Artifact** so the user gets a link.
2. `design/DESIGN.md` — the spec the implementer will build from:
   - Information architecture (tabs, pushes, sheets) and navigation map
   - Per-screen layout: sections in order, components, which web component it replaces
   - Design tokens for light + dark (colours, type ramp mapped to Dynamic Type styles, spacing,
     corner radii) and where the user accent colour is applied
   - The `+` quick-add: placement, selector options, each flow's fields
   - Face ID flow + widget specs (families, locked vs unlocked content)
   - SwiftUI API mapping where it matters (`TabView`/`Tab`, `.tabBarMinimizeBehavior`,
     `glassEffect`, `GlassEffectContainer`, `ColorPicker`, `LocalAuthentication`, WidgetKit families)
   - Open questions for the user
3. When done, tell the user in this pane: the Artifact link, a 5–10 line summary, and the open
   questions. Then create an empty file `design/READY` so the implementer knows.

Use the `apple-skills:ios-development` skill (its `ui-review` and `navigation-patterns` modules)
for HIG compliance. Iterate with the user in this pane until they're happy; update both files and
republish the Artifact to the same URL on each revision, and touch `design/READY` again.
