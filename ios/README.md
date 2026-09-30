# Ascent for iOS

A native SwiftUI app for iOS 26+. Everything is stored on the iPhone: one JSON log in the App Group
container, no account, no iCloud. The overview is in the root `README.md`.

## Layout

| Path | What |
|---|---|
| `AscentKit/Sources/AscentCore` | Models, vocab, dates, metrics, taper engine, demo seed, store. |
| `AscentKit/Sources/AscentUI` | Theme, components, every screen, Face ID lock, Live Activity sync. |
| `AscentKit/Sources/AscentWidgetsUI` | Home / Lock Screen widget views and the Live Activity. |
| `Ascent/` | The app target (entry point, icon). |
| `AscentWidgets/` | The widget extension (timeline provider, widget bundle). |
| `project.yml` | XcodeGen spec — `xcodegen generate` rebuilds `Ascent.xcodeproj`. |

## Build

Needs Xcode 26 or later.

```bash
xcodegen generate && open Ascent.xcodeproj
```

Pick an iPhone simulator and Run. On a device, set your Team under Signing for both targets; the App
Group `group.com.ivancyx.ascent` is created automatically.

## Tests (no Xcode needed)

```bash
cd AscentKit && ./test.sh
```

```bash
cd AscentKit && SNAPSHOT_DIR=/tmp/snaps ./test.sh --filter Snapshots
```

The second command renders every screen to PNG.
