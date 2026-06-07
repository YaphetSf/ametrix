# Ametrix

<p align="center">
  <img src="assets/ametrix-icon-256.png" alt="Ametrix" width="160">
</p>

A native macOS Matrix-style digital rain screen saver and lock-screen trigger.

Ametrix installs as a real macOS `.saver` bundle and includes a live desktop
wallpaper. The renderer is native AppKit/CoreText code: no terminal emulator,
PTY, shell animation process, or external Matrix-rain dependency is required.

macOS still handles the actual authentication layer: password, Touch ID, Apple
Watch unlock, and screen-saver password policy.

## Features

- Native macOS screen saver bundle
- Built-in global `Control-Command-Z` lock shortcut
- Menu bar controller for wallpaper and preferences
- Optional live wallpaper mode
- Manual full-screen overlay mode
- Multi-display support
- Configurable color presets, density, speed, trails, font, and glyph palette
- Latin, katakana, number, and symbol glyphs by default
- No network access or telemetry

## Requirements

- macOS 13 or newer
- Swift 5.9 or newer and Xcode when building from source

## Quick Start

Download `Ametrix.dmg` from the latest GitHub release, open it, and drag
`Ametrix.app` to Applications.

Launch Ametrix once from Applications. Onboarding installs the bundled screen
saver and guides you through selecting it. The menu bar icon lets you:

- Start or stop the live wallpaper
- Open **Preferences…** to tune colors, density, motion, and glyphs with a
  live preview — changes save to the TOML config and refresh a running wallpaper
  immediately
- Quit Ametrix

After onboarding:

1. Select **Ametrix** once in **System Settings -> Screen Saver**.
2. In **System Settings -> Lock Screen**, set password requirement to
   immediately after the screen saver begins.

Press `Control-Command-Z` while Ametrix is running to start the screen saver and
enter the normal macOS lock flow.

To build a local drag-and-drop app bundle:

```bash
scripts/release/package-app.sh
```

This creates `dist/Ametrix.app`. The app runs as a menu bar controller and includes
`Ametrix.saver` plus the default config template in its bundle resources.

## Usage

Start the selected macOS screen saver:

```bash
ametrix
```

Run Ametrix directly as an overlay:

```bash
ametrix --overlay
```

Run Ametrix as a desktop-level live wallpaper:

```bash
ametrix --wallpaper
```

Run Ametrix as a menu bar controller:

```bash
ametrix --menubar
```

Start menu bar mode with wallpaper already enabled:

```bash
ametrix --menubar --wallpaper
```

Open the preferences window on its own (also available as the menu bar
**Preferences…** item):

```bash
ametrix --preferences
```

Inspect the resolved config:

```bash
ametrix --print-config
```

Screen saver mode is controlled by macOS. Wake, unlock, password, Touch ID, and Apple Watch unlock behavior are handled by the system.

Overlay mode opens one borderless window per display. Press `Esc` or `Cmd-Q` to quit.

Wallpaper mode runs behind normal desktop windows, joins all Spaces, and ignores
mouse events. It is a normal app window, not a native item in macOS Wallpaper
settings.

Menu bar mode adds an Ametrix icon to the macOS menu bar. Wallpaper state is
remembered across launches.

## Lock Shortcut

Ametrix does not draw over the macOS lock screen. The built-in global
`Control-Command-Z` shortcut starts Ametrix through macOS ScreenSaverEngine.
With macOS configured to require a password immediately after the screen saver
starts, authentication remains fully owned by the system.

## Configuration

Edit the canonical TOML config:

```bash
~/Library/Application Support/Ametrix/config.toml
```

Example:

```toml
frameRate = 60
preset = "classic"
density = 1.0

fontName = "Menlo"
fontSize = 16

# Explicit colors override preset colors.
# backgroundColor = "#000000"
# headColor = "#d9ffd9"
# tailColor = "#00ff41"

minimumTailAlpha = 0.08
characters = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzアイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲン@#$%&*+-=<>"

[speed]
min = 18
max = 38

[trail]
min = 14
max = 48
rowMultiplier = 0.75
```

Supported fields:

| Field | Purpose |
|---|---|
| `frameRate` | Animation frame rate, 15-120 |
| `preset` | Color preset: `classic`, `amber`, `cyan`, `white`, `violet` |
| `density` | Rain-column density, 0.2-3.0 |
| `fontName` / `fontSize` | Glyph font |
| `backgroundColor` | Hex background color |
| `headColor` | Hex rain-head color |
| `tailColor` | Hex trail color |
| `minimumTailAlpha` | Faintest tail opacity |
| `speed.min` / `speed.max` | Falling speed range |
| `trail.min` / `trail.max` | Trail length range |
| `trail.rowMultiplier` | Trail cap relative to screen rows |
| `characters` | Glyph palette |

Preset colors are applied first. Explicit color fields override preset colors.

`~/.config/ametrix/config.toml` is still read as a fallback for older installs. The older `config.json` format is only used when no TOML config exists.

## Screen Saver Container

Modern macOS runs `.saver` bundles inside:

```bash
~/Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data
```

That container has its own home directory, so a screen saver process cannot
reliably read the normal user config path. Ametrix syncs the canonical TOML
config into the container before starting the screen saver.

## Development

Script layout:

```text
scripts/
  branding/                 Reproducible app icon renderer
  dev/                      Local development and testing helpers
  release/                  Screen saver build, app packaging, signing, notarization
```

Clean-slate test as a first-time user (resets prefs, installed saver, and config,
then repackages and relaunches so the onboarding guide appears):

```bash
scripts/dev/retest.sh             # full reset, repackage, launch
scripts/dev/retest.sh --keep      # keep installed saver + config, only reset prefs
scripts/dev/retest.sh --no-build  # skip repackaging, reuse dist/Ametrix.app
```

Build the CLI:

```bash
swift build -c release
```

Build a local `.app` bundle:

```bash
scripts/release/package-app.sh
```

Build, sign, notarize, and package a release DMG:

```bash
scripts/release/sign-notarize-dmg.sh
```

The script automatically uses the only installed Developer ID Application
certificate and the `ametrix-notary` Keychain profile. Create that profile once:

```bash
xcrun notarytool store-credentials ametrix-notary
```

Follow the prompts to use an App Store Connect API key or Apple ID credentials.
The resulting profile is stored in the macOS Keychain, not in this repository.

For a signed-only local DMG without notarization:

```bash
AMETRIX_SKIP_NOTARIZE=1 \
scripts/release/sign-notarize-dmg.sh
```

Build only the screen saver bundle:

```bash
scripts/release/build-screensaver.sh
```

Useful environment variables:

| Variable | Purpose |
|---|---|
| `AMETRIX_SAVER_DEST_DIR` | Override `.saver` build output directory |
| `AMETRIX_SIGN_IDENTITY` | Override the auto-detected Developer ID Application identity |
| `AMETRIX_NOTARY_PROFILE` | Override the default `ametrix-notary` Keychain profile |
| `AMETRIX_SKIP_NOTARIZE=1` | Build a signed local DMG without Apple notarization |
| `DEVELOPER_DIR` | Select a specific Xcode toolchain; otherwise `/Applications/Xcode.app` is used when present |

## Architecture

```text
Sources/ametrix/main.swift
  CLI entry point, overlay app lifecycle, menu bar controller, screen saver launch

Sources/ametrix/AmetrixConfiguration.swift
  TOML/JSON config loading, presets, screen saver container paths

Sources/ametrix/MatrixRainView.swift
  Native CoreText renderer

Sources/AmetrixScreenSaver/AmetrixScreenSaverView.swift
  ScreenSaverView wrapper around MatrixRainView
```

## Privacy

Ametrix does not collect telemetry, call network services, or shell out to
third-party animation tools. It reads local configuration files and installs its
bundled screen saver during onboarding.

## License

MIT. See [LICENSE](LICENSE).
