<p align="center">
  <img src="docs/icon.png" width="128" alt="SwiftCast icon">
</p>

<h1 align="center">SwiftCast</h1>

<p align="center">
  A fast, native macOS launcher: apps, quick math and clipboard history.
  <br>
  <a href="https://github.com/inhzus/swiftcast/actions/workflows/ci.yml"><img src="https://github.com/inhzus/swiftcast/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/inhzus/swiftcast/releases/latest"><img src="https://img.shields.io/github/v/release/inhzus/swiftcast" alt="Release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/inhzus/swiftcast" alt="License"></a>
</p>

Press a shortcut, type a few letters, press ↩. SwiftCast is built for latency, has no
dependencies, and needs no special permissions.

## Features

- **Apps.** Fuzzy search by prefix, initials (`vsc` → Visual Studio Code) or scattered letters.
- **Quick math.** Arithmetic, percentages, functions and unit conversions.
- **Clipboard history.** Text and images you copy, searchable; open it with ⌃⌥⇧⌘C.
- **Learns what you pick.** Results you choose often rise to the top, across all features.
- **Search history.** ↑/↓ in an empty field steps through past searches.

| Type | Result |
| --- | --- |
| `200 + 10%` | 220 |
| `1.5 GB in MB` | 1,536 MB |
| `60 mph in km/h` | 96.56 km/h |
| `72 F to C` | 22.22 °C |

## Install

Requires macOS 26 Tahoe or later, on Apple silicon or Intel.

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

SwiftCast lives in the menu bar. Open it with **⌥Space**, or pick another shortcut in
SwiftCast's Settings.

| Key | Action |
| --- | --- |
| ↩ | Open app · copy result · open clipboard history |
| ⌘↩ | Show app in Finder |
| ↑ ↓ | Move selection; in an empty field, browse past searches |
| ⌘, | Settings: shortcuts, search folders, features on/off |
| esc | Back · close |

## Development

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for building, architecture and releasing.

## License

[MIT](LICENSE)
