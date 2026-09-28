# Hem

A macOS 26 menu bar list. Open it from Xcode, add a few tasks, check them off.

This is a native rewrite of the daily-list idea in [Hotlist](https://pqina.nl/hotlist) by [PQINA](https://pqina.nl/hotlist). The original UI is Svelte inside Tauri. This app is AppKit plus SwiftUI. It does not read or write the official Hotlist file.

## Run

Open `Hem.xcodeproj` in Xcode 26 and run the `Hem` scheme. The app has no Dock icon. Look for a rounded badge in the menu bar.

Left click toggles the list. Right click is Settings and Quit.

If you use Ice or another menu bar manager, the extra is `com.adamcox.hem`. New extras often start hidden. Show it there if you cannot see a rounded badge next to official Hotlist.

## Format and lint

Formatting uses [swift-format](https://github.com/swiftlang/swift-format), which ships with Xcode. Its settings are in `.swift-format`. Linting uses [SwiftLint](https://github.com/realm/SwiftLint), configured in `.swiftlint.yml`. Install it with `brew install swiftlint`.

```sh
xcrun swift-format format --in-place --recursive Hem HemTests
xcrun swift-format lint --recursive --strict Hem HemTests
swiftlint lint --strict
```

Xcode builds also run both linters in a Lint build phase and show findings as warnings. If SwiftLint is not installed, the build shows one warning saying so.

The release workflow runs both linters in strict mode before testing, so a lint failure blocks the release.

## Install

Download the latest `Hem-x.y.z.zip` from [Releases](https://github.com/adamjhc/hem/releases/latest), unzip it, and move `Hem.app` to Applications. Hem checks for updates daily with [Sparkle](https://sparkle-project.org). Right click the badge and choose Check for Updates… to check now.

## Releases

Every push to `main` that changes more than Markdown or YAML files triggers `.github/workflows/release.yml`. The workflow tests, archives, signs with Developer ID, notarizes, and publishes a GitHub release. It then adds the release to the Sparkle feed at `https://adamjhc.github.io/hem/appcast.xml`, which lives on the `gh-pages` branch.

The version is `MARKETING_VERSION` from the project plus the commit count on `main`, for example `1.0.42`. Change `MARKETING_VERSION` to bump the major or minor version. Release notes are the commit subjects since the previous tag.

The workflow needs these repository secrets:

| Secret | What it is |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | Developer ID Application certificate and private key, exported as `.p12`, base64 encoded |
| `DEVELOPER_ID_P12_PASSWORD` | Password for that `.p12` |
| `NOTARY_API_KEY` | Contents of an App Store Connect API key `.p8` file |
| `NOTARY_KEY_ID` | That key's ID |
| `NOTARY_ISSUER_ID` | The App Store Connect issuer ID |
| `SPARKLE_ED_PRIVATE_KEY` | Sparkle EdDSA private key. Export it with `generate_keys --account com.adamcox.hem -x <file>` |

The matching Sparkle public key is `SUPublicEDKey` in `Hem/Info.plist`. Do not lose the private key. Without it, installed copies cannot verify new updates.

## Data

Tasks live in `~/Library/Application Support/Hem/state.json`.

```json
{ "items": [ { "id": "uuid", "text": "buy milk" } ] }
```

## Credit

Inspired by [Hotlist](https://pqina.nl/hotlist) by PQINA. The original web and Tauri sources are MIT.
