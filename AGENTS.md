# Agent notes

## After you finish changes

When the requested work is done and you changed app source or the Xcode project, build Release and restart Hem. Do this once at the end, not after every intermediate edit. Skip it for docs-only edits.

Quit the running app first, then build, then open the Release `.app`. Debug products from this DerivedData path are Xcode stubs and do not show the menu bar extra.

```sh
pkill -x Hem 2>/dev/null
xcodebuild -project Hem.xcodeproj -scheme Hem -configuration Release -derivedDataPath .derivedData -destination 'platform=macOS' build
open .derivedData/Build/Products/Release/Hem.app
```
