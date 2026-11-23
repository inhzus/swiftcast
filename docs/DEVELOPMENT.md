# Developing SwiftCast

## Building

Needs Xcode 26 or its Command Line Tools (the macOS 26 SDK).

```sh
scripts/test.sh                  # run the tests
scripts/bundle.sh                # build a universal build/SwiftCast.app
open build/SwiftCast.app --args --show
```

`--show` opens the launcher at startup and `--settings` opens Settings. Set
`SWIFTCAST_PERF=1` to log open and keystroke latency to stderr.

The icon is drawn by `scripts/make-icon.swift`; run `scripts/make-icon.sh` to regenerate
`Resources/AppIcon.icns`.

## Architecture

Every feature is a plugin, a SwiftPM target with a clear border:

| Target | What it is | May depend on |
| --- | --- | --- |
| `SwiftCastPluginKit` | The plugin contract (`LauncherPlugin`, `ResultItem`, `Effect`), settings descriptions, `Shortcut`, the SQLite `Database` helper, the shared `FuzzyMatcher` | system frameworks |
| `AppsPlugin` | App search: indexing, pinyin, search folders | `SwiftCastPluginKit` |
| `CalculatorPlugin` | Quick math | `SwiftCastPluginKit` |
| `ClipboardPlugin` | Clipboard history: pasteboard monitor, store, its own view | `SwiftCastPluginKit` |
| `SwiftCastCore` | Host logic without UI: the launcher view model, `PluginHost` (which plugins are on, their lifecycle), shortcut rules, search history, usage, ranking across plugins | `SwiftCastPluginKit` |
| `SwiftCast` | The AppKit app: panel (`PanelController`), hotkeys (`HotKeyController`), settings window, carrying out effects | all of the above |

Plugins return rows and their actions as values; the app draws the rows and carries out the
actions (open, reveal, copy, open the plugin's view), so plugins never touch the panel. A
plugin can't import the app or another plugin.

- **Ranking.** Each row says how well it matched (`ResultItem.match`). The app sorts every
  plugin's rows by that, then by how often and how recently the user picked them, then by
  registry order. Plugins can read their rows' usage through `PluginContext`.
- **Views.** A plugin with a `viewTitle` can show its own list with a preview
  (`Effect.openView`, `viewResults(for:)`), and declare a global shortcut that opens it
  (`defaultViewShortcut`).
- **Settings.** Each plugin gets a page with an on/off switch, plus the sections it describes
  in `settingsSections()`; the app draws them. A disabled plugin is never asked for results.
- **Data.** Each plugin keeps its data in its own SQLite file under
  `~/Library/Application Support/dev.swiftcast.app/`, and the app keeps search history and
  usage in `swiftcast.db`. App-wide settings live in `UserDefaults`.

To add a plugin, create a target that depends on `SwiftCastPluginKit`, implement
`LauncherPlugin`, and list it in `Sources/SwiftCast/PluginRegistry.swift`. Units for quick
math live in tables under `Sources/CalculatorPlugin/Units/`.

## Releasing

Bump `CFBundleShortVersionString` in `Resources/Info.plist`, merge, then push a version tag:

```sh
git tag v1.2.3 && git push origin v1.2.3
```

The [release workflow](../.github/workflows/release.yml) tests, builds a universal app, zips
it, and publishes a GitHub release. These repository secrets are optional and each turns on
a step:

| Secret | Turns on |
| --- | --- |
| `MACOS_CERT_P12`, `MACOS_CERT_PASSWORD` | Developer ID signing (base64 of the `.p12` export) |
| `NOTARY_KEY`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` | Notarization with an App Store Connect API key (contents of the `.p8`) |
| `TAP_DEPLOY_KEY` | Pushing the updated cask to [`inhzus/homebrew-tap`](https://github.com/inhzus/homebrew-tap) (the private half of a deploy key with write access there) |

The cask template is [`packaging/homebrew/swiftcast.rb`](../packaging/homebrew/swiftcast.rb).
Once releases are notarized, drop its `postflight_steps` block and the quarantine note in
the README.

Locally, `VERSION=1.2.3 scripts/package.sh` builds the same zip and prints its SHA-256.
