# Ametrix

<p align="center">
  <img src="assets/ametrix-icon-256.png" alt="Ametrix" width="160">
</p>

A native macOS Matrix-style digital rain screen saver and lock-screen trigger.

Ametrix installs as a real macOS `.saver` bundle. It can also be launched manually
from the command line, Raycast, or Karabiner-Elements. The renderer is native
AppKit/CoreText code: no terminal emulator, PTY, shell animation process, or
external Matrix-rain dependency is required.

The practical daily workflow is:

```text
Ctrl-Cmd-Q -> Karabiner -> ametrix -> macOS screen saver -> macOS unlock/auth
```

macOS still handles the actual authentication layer: password, Touch ID, Apple
Watch unlock, and screen-saver password policy.

## Features

- Native macOS screen saver bundle
- Optional `Ctrl-Cmd-Q` trigger through Karabiner-Elements
- Optional menu bar controller for wallpaper and lock-screen actions
- Optional live wallpaper mode
- Manual full-screen overlay mode
- Multi-display support
- Configurable color presets, density, speed, trails, font, and glyph palette
- Latin, katakana, number, and symbol glyphs by default
- No network access or telemetry

## Requirements

- macOS 13 or newer
- Swift 5.9 or newer
- Xcode for building the `.saver` bundle
- Karabiner-Elements, optional, for the `Ctrl-Cmd-Q` trigger

## Quick Start

Download `Ametrix.dmg` from the latest GitHub release, open it, and drag
`Ametrix.app` to Applications.

Launch Ametrix once from Applications. The menu bar icon lets you:

- Install or reinstall the bundled `Ametrix.saver`
- Start or stop the live wallpaper
- Start the selected macOS screen saver for lock-screen use
- Open **Preferences…** (⌘,) to tune colors, density, motion, and glyphs with a
  live preview — changes save to the TOML config and refresh a running wallpaper
  immediately
- Quit Ametrix

After installing the screen saver from the menu:

1. Select **Ametrix** once in **System Settings -> Screen Saver**.
2. In **System Settings -> Lock Screen**, set password requirement to
   immediately after the screen saver begins.

For an optional keyboard lock shortcut, install the Karabiner rule with
`scripts/install/karabiner-lock.sh`, then enable
**Ametrix -> Ctrl-Command-Q starts Ametrix screen saver** in Karabiner-Elements.

If you already cloned the repo:

```bash
scripts/install.sh
```

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

Menu bar mode adds an Ametrix icon to the macOS menu bar. Use it to start or stop
the live wallpaper, start the selected macOS screen saver for lock-screen use,
install the bundled screen saver, or quit Ametrix. Wallpaper state is remembered
across menu bar launches.

Install menu bar mode as a login item:

```bash
scripts/install/menubar-agent.sh
```

Remove the menu bar login item:

```bash
scripts/install/menubar-agent.sh --uninstall
```

Install everything and enable menu bar mode immediately:

```bash
curl -fsSL https://raw.githubusercontent.com/YaphetSf/ametrix/main/scripts/bootstrap.sh | AMETRIX_INSTALL_MENUBAR=1 bash
```

## Lock Shortcut

Ametrix does not try to draw over the macOS lock screen. That boundary is owned by
macOS. Instead, the Karabiner rule remaps `Ctrl-Cmd-Q` to start the Ametrix screen
saver. With macOS configured to require a password immediately after the screen
saver starts, the result behaves like a lock shortcut while keeping the system
authentication flow intact.

Install or refresh the Karabiner rule manually:

```bash
scripts/install/karabiner-lock.sh
```

Karabiner command output is written to:

```bash
/tmp/ametrix-karabiner.log
```

## Raycast

A Raycast Script Command is included at:

```bash
scripts/integrations/raycast-ametrix.sh
```

## Configuration

Edit the canonical TOML config:

```bash
~/Library/Application Support/Ametrix/config.toml
```

Create it manually when needed:

```bash
scripts/install/config.sh
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

That container has its own home directory, so a screen saver process cannot reliably read the normal user config path. `ametrix` and `scripts/install.sh` sync the canonical TOML config into the container before starting the screen saver.

## Development

Script layout:

```text
scripts/
  bootstrap.sh              Remote curl installer
  install.sh                Local one-command installer
  install/                  Install helpers used by install.sh
  release/                  Packaging, signing, notarization, and release helpers
  integrations/             Optional third-party launcher scripts
```

Build the CLI:

```bash
swift build -c release
```

Build and install everything:

```bash
scripts/install.sh
```

Build a local `.app` bundle:

```bash
scripts/release/package-app.sh
```

Build, sign, notarize, and package a release DMG:

```bash
AMETRIX_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
AMETRIX_NOTARY_PROFILE="ametrix-notary" \
scripts/release/sign-notarize-dmg.sh
```

Create the notarytool keychain profile once:

```bash
xcrun notarytool store-credentials ametrix-notary \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"
```

For a signed-only local DMG without notarization:

```bash
AMETRIX_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
AMETRIX_SKIP_NOTARIZE=1 \
scripts/release/sign-notarize-dmg.sh
```

Test the remote bootstrap installer locally:

```bash
scripts/bootstrap.sh
```

Build only the screen saver bundle:

```bash
scripts/install/screensaver.sh
```

Useful environment variables:

| Variable | Purpose |
|---|---|
| `AMETRIX_BIN_DEST` | Override CLI install path |
| `AMETRIX_CONFIG_DIR` | Override canonical config directory |
| `AMETRIX_INSTALL_DIR` | Override where `scripts/bootstrap.sh` clones the repo |
| `AMETRIX_SAVER_DEST_DIR` | Override `.saver` install directory |
| `AMETRIX_INSTALL_KARABINER=0` | Skip installing the Karabiner complex modification |
| `AMETRIX_INSTALL_MENUBAR=1` | Install and start menu bar mode as a LaunchAgent |
| `AMETRIX_SIGN_IDENTITY` | Developer ID Application identity for DMG signing |
| `AMETRIX_NOTARY_PROFILE` | `notarytool` keychain profile for notarization |
| `AMETRIX_SKIP_NOTARIZE=1` | Build a signed local DMG without Apple notarization |
| `AMETRIX_REPO_URL` | Override the git URL used by `scripts/bootstrap.sh` |
| `AMETRIX_OPEN_SETTINGS=0` | Skip opening System Settings after saver install |
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

Ametrix does not collect telemetry, call network services, or shell out to third-party animation tools. It reads local configuration files and writes the installed CLI and screen saver bundle during installation.

## License

MIT. See [LICENSE](LICENSE).
