# Ame

A native macOS Matrix-style digital rain screen saver.

Ame can run as a real macOS `.saver` bundle, or as a direct full-screen overlay for quick manual use. The renderer is native AppKit/CoreText code: no terminal emulator, PTY, shell animation process, or external Matrix-rain dependency is required.

## Features

- Native macOS screen saver bundle
- Manual full-screen overlay mode
- Multi-display support
- Configurable color presets, density, speed, trails, font, and glyph palette
- Latin, katakana, number, and symbol glyphs by default
- No network access or telemetry

## Requirements

- macOS 13 or newer
- Swift 5.9 or newer
- Xcode for building the `.saver` bundle

## Install

```bash
scripts/install.sh
```

The installer:

- Builds the release CLI with SwiftPM
- Installs `ame` to `AME_BIN_DEST` when set
- Otherwise installs to `$(brew --prefix)/bin/ame` when Homebrew is available
- Falls back to `~/.local/bin/ame`
- Installs `Ame.saver` to `~/Library/Screen Savers/Ame.saver`
- Creates a default config when needed
- Syncs the config into the macOS screen saver container

After installing, select **Ame** once in **System Settings -> Screen Saver**.

## Usage

Start the selected macOS screen saver:

```bash
ame
```

Run Ame directly as an overlay:

```bash
ame --overlay
```

Inspect the resolved config:

```bash
ame --print-config
```

Screen saver mode is controlled by macOS. Wake, unlock, password, Touch ID, and Apple Watch unlock behavior are handled by the system.

Overlay mode opens one borderless window per display. Press `Esc` or `Cmd-Q` to quit.

## Raycast

A Raycast Script Command is included at:

```bash
scripts/raycast-ame.sh
```

## Karabiner

Install a Karabiner-Elements complex modification that remaps `Ctrl-Cmd-Q`
to start the selected macOS screen saver with Ame:

```bash
scripts/install-karabiner-lock.sh
```

Then enable **Ame -> Ctrl-Command-Q starts Ame screen saver** in
Karabiner-Elements under **Complex Modifications -> Add predefined rule**.

For lock behavior, configure macOS to require a password immediately after the
screen saver begins. Ame starts the system screen saver; macOS still handles
authentication, Touch ID, Apple Watch unlock, and password policy.

## Configuration

Edit the canonical TOML config:

```bash
~/Library/Application Support/Ame/config.toml
```

Create it manually when needed:

```bash
scripts/install-config.sh
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

`~/.config/ame/config.toml` is still read as a fallback for older installs. The older `config.json` format is only used when no TOML config exists.

## Screen Saver Container

Modern macOS runs `.saver` bundles inside:

```bash
~/Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data
```

That container has its own home directory, so a screen saver process cannot reliably read the normal user config path. `ame` and `scripts/install.sh` sync the canonical TOML config into the container before starting the screen saver.

## Development

Build the CLI:

```bash
swift build -c release
```

Build and install everything:

```bash
scripts/install.sh
```

Build only the screen saver bundle:

```bash
scripts/install-screensaver.sh
```

Useful environment variables:

| Variable | Purpose |
|---|---|
| `AME_BIN_DEST` | Override CLI install path |
| `AME_CONFIG_DIR` | Override canonical config directory |
| `AME_SAVER_DEST_DIR` | Override `.saver` install directory |
| `AME_OPEN_SETTINGS=0` | Skip opening System Settings after saver install |
| `DEVELOPER_DIR` | Select a specific Xcode toolchain; otherwise `/Applications/Xcode.app` is used when present |

## Architecture

```text
Sources/ame/main.swift
  CLI entry point, overlay app lifecycle, screen saver launch

Sources/ame/AmeConfiguration.swift
  TOML/JSON config loading, presets, screen saver container paths

Sources/ame/MatrixRainView.swift
  Native CoreText renderer

Sources/AmeScreenSaver/AmeScreenSaverView.swift
  ScreenSaverView wrapper around MatrixRainView
```

## Privacy

Ame does not collect telemetry, call network services, or shell out to third-party animation tools. It reads local configuration files and writes the installed CLI and screen saver bundle during installation.

## License

MIT. See [LICENSE](LICENSE).
