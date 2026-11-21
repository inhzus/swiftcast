<p align="center">
  <img src="docs/icon.png" width="128" alt="SwiftCast icon">
</p>

<h1 align="center">SwiftCast</h1>

<p align="center">
  A fast, native macOS app launcher with quick math built in.
  <br>
  <a href="https://github.com/inhzus/swiftcast/actions/workflows/ci.yml"><img src="https://github.com/inhzus/swiftcast/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/inhzus/swiftcast/releases/latest"><img src="https://img.shields.io/github/v/release/inhzus/swiftcast" alt="Release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/inhzus/swiftcast" alt="License"></a>
</p>

SwiftCast is a small AppKit launcher: press a shortcut, type a few letters, press ↩. It is
built for latency, has no dependencies, and needs no special permissions.

## Features

- **Fuzzy app search.** Matches prefixes, initials (`vsc` → Visual Studio Code), word starts
  and scattered letters, and ranks the apps you open most first. ↩ opens, ⌘↩ shows the app in Finder.
- **Quick math.** Arithmetic, percentages, functions and unit conversions; ↩ copies the result.
- **Search history.** With the field empty, ↑/↓ steps through past searches. Reopen within a
  minute and your last search is still there (configurable).
- **Native look.** Liquid Glass on macOS 26, a frosted panel on macOS 14–15.
- **Settings** (⌘,): global shortcut, launch at login, extra folders to search, clear history.
- **No Accessibility permission.** The global shortcut uses the system hotkey API.

### Quick math

| Type | Result |
| --- | --- |
| `200 + 10%` | 220 |
| `sqrt(2)` | 1.41421356237 |
| `1.5 GB in MB` | 1,536 MB |
| `1 GB / 20 MB/s` | 51.2 s |
| `5 km in mi` | 3.11 mi |
| `60 mph in km/h` | 96.56 km/h |
| `2 kg in lb` | 4.41 lb |
| `72 F to C` | 22.22 °C |
| `1B + 500M` | 1,500,000,000 |

Supported: `+ - * / ^`, parentheses, `%`, `sqrt sin cos tan log ln abs round`, `pi`, `e`; data
sizes (1024-based, bits and bytes), number scales (K/M/B/T), length, area, volume, mass,
time, speed and temperature. Units combine, so `km/h` and `MB/s` work, and `in`/`to` picks
the result's unit. When a word is ambiguous, such as `B` for bytes or billion, the result
says how it was read.

Queries only count as math when they fully parse and contain an operator, percentage,
function or conversion, so searching for `1Password` or `2048` still finds apps.

## Install

Requires macOS 14 Sonoma or later, on Apple silicon or Intel.

**Homebrew**

```sh
brew install --cask inhzus/tap/swiftcast
```

**Manual:** download `SwiftCast-<version>.zip` from
[Releases](https://github.com/inhzus/swiftcast/releases/latest), unzip it, and move
`SwiftCast.app` to `/Applications`.

> [!NOTE]
> Releases are not notarized yet, so on first launch macOS says it can't check the app for
> malware. Clear the quarantine flag once:
>
> ```sh
> xattr -dr com.apple.quarantine /Applications/SwiftCast.app
> ```
>
> or open it, then choose **Open Anyway** in System Settings → Privacy & Security.
> The Homebrew cask does this for you.

## Usage

SwiftCast lives in the menu bar. The default shortcut is **⌘Space**, which Spotlight also
uses. Either turn Spotlight's off (System Settings → Keyboard → Keyboard Shortcuts… →
Spotlight) or record another shortcut in SwiftCast's Settings.

| Key | Action |
| --- | --- |
| ↩ | Open app / copy result |
| ⌘↩ | Show app in Finder |
| ↑ ↓ | Move selection; with an empty field, browse history |
| ⌘, | Settings |
| esc | Close |

Apps are found in `/Applications`, `/System/Applications` and `~/Applications` (three levels
deep), plus any folders added in Settings.

## Building from source

Needs Xcode 26 or its Command Line Tools (the macOS 26 SDK).

```sh
scripts/test.sh                  # run the tests
scripts/bundle.sh                # build a universal build/SwiftCast.app
open build/SwiftCast.app --args --show
```

`--show` opens the launcher at startup and `--settings` opens Settings. Set
`SWIFTCAST_PERF=1` to log open and keystroke latency to stderr.

The code is split into `SwiftCastCore` (search, ranking, calculator; no UI, fully tested)
and `SwiftCast` (the AppKit app). Units for quick math live in tables under
`Sources/SwiftCastCore/Calculator/Units/`.

The icon is drawn by `scripts/make-icon.swift`; run `scripts/make-icon.sh` to regenerate
`Resources/AppIcon.icns`.

## Releasing

Push a version tag:

```sh
git tag v0.2.0 && git push origin v0.2.0
```

The [release workflow](.github/workflows/release.yml) tests, builds a universal app, zips it,
and publishes a GitHub release. These repository secrets are optional and each turns on a
step:

| Secret | Turns on |
| --- | --- |
| `MACOS_CERT_P12`, `MACOS_CERT_PASSWORD` | Developer ID signing (base64 of the `.p12` export) |
| `NOTARY_KEY`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` | Notarization with an App Store Connect API key (contents of the `.p8`) |
| `TAP_DEPLOY_KEY` | Pushing the updated cask to [`inhzus/homebrew-tap`](https://github.com/inhzus/homebrew-tap) (the private half of a deploy key with write access there) |

The cask template is [`packaging/homebrew/swiftcast.rb`](packaging/homebrew/swiftcast.rb).
Once releases are notarized, drop its `postflight_steps` block and the note above.

Locally, `VERSION=0.2.0 scripts/package.sh` builds the same zip and prints its SHA-256.

## License

[MIT](LICENSE)
