# Ascent for iOS

A native SwiftUI port of the web app (iOS 26+, Liquid Glass). Everything is stored on the iPhone:
one JSON log in the App Group container, no account, no iCloud. Backups use the same format as the
web app's `Gyms → Data → Export`, so either app can read the other's file.

## Layout

| Path | What |
|---|---|
| `AscentKit/Sources/AscentCore` | Models, vocab, dates, metrics, taper engine, demo seed, store. A line-for-line port of `src/domain` + `src/db`. |
| `AscentKit/Sources/AscentUI` | Theme, components, every screen, Face ID lock, Live Activity sync. |
| `AscentKit/Sources/AscentWidgetsUI` | Home / Lock Screen widget views and the Live Activity. |
| `Ascent/` | The app target (entry point, icon). |
| `AscentWidgets/` | The widget extension (timeline provider, widget bundle). |
| `project.yml` | XcodeGen spec — `xcodegen generate` rebuilds `Ascent.xcodeproj`. |

## Build

Needs Xcode 26 or later.

```bash
open Ascent.xcodeproj          # pick an iPhone simulator, Run
```

On a device, set your Team under Signing for both targets; the App Group
`group.com.ivancyx.ascent` is created automatically.

## Tests (no Xcode needed)

```bash
cd AscentKit && ./test.sh                     # domain tests, incl. web-parity fixtures
SNAPSHOT_DIR=/tmp/snaps ./test.sh --filter Snapshots   # renders every screen to PNG
```
