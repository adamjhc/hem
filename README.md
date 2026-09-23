# Hem

A macOS 26 menu bar list. Open it from Xcode, add a few tasks, check them off.

This is a native rewrite of the daily-list idea in [Hotlist](https://pqina.nl/hotlist) by [PQINA](https://pqina.nl/hotlist). The original UI is Svelte inside Tauri. This app is AppKit plus SwiftUI. It does not read or write the official Hotlist file.

## Run

Open `Hem.xcodeproj` in Xcode 26 and run the `Hem` scheme. The app has no Dock icon. Look for a rounded badge in the menu bar.

Left click toggles the list. Right click is Settings and Quit.

If you use Ice or another menu bar manager, the extra is `com.adamcox.hem`. New extras often start hidden. Show it there if you cannot see a rounded badge next to official Hotlist.

## Data

Tasks live in `~/Library/Application Support/Hem/state.json`.

```json
{ "items": [ { "id": "uuid", "text": "buy milk" } ] }
```

## Credit

Inspired by [Hotlist](https://pqina.nl/hotlist) by PQINA. The original web and Tauri sources are MIT.
