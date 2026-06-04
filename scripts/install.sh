#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -n "${AME_BIN_DEST:-}" ]]; then
  BIN_DEST="$AME_BIN_DEST"
elif command -v brew >/dev/null 2>&1; then
  BIN_DEST="$(brew --prefix)/bin/ame"
else
  BIN_DEST="$HOME/.local/bin/ame"
fi

cd "$ROOT_DIR"

swift build --disable-sandbox -c release
mkdir -p "$(dirname "$BIN_DEST")"
cp "$ROOT_DIR/.build/release/ame" "$BIN_DEST"

"$ROOT_DIR/scripts/install-config.sh"
AME_OPEN_SETTINGS="${AME_OPEN_SETTINGS:-1}" "$ROOT_DIR/scripts/install-screensaver.sh"

if [[ "${AME_INSTALL_KARABINER:-1}" == "1" ]]; then
  AME_BIN_DEST="$BIN_DEST" "$ROOT_DIR/scripts/install-karabiner-lock.sh"
fi

if [[ "${AME_INSTALL_WALLPAPER:-0}" == "1" ]]; then
  AME_BIN_DEST="$BIN_DEST" "$ROOT_DIR/scripts/install-wallpaper-agent.sh"
fi

echo ""
echo "Installed CLI to $BIN_DEST"
echo ""
echo "Next steps:"
echo "  1. Select Ame once in System Settings > Screen Saver."
echo "  2. Set macOS to require password immediately after the screen saver begins."
if [[ "${AME_INSTALL_KARABINER:-1}" == "1" ]]; then
  echo "  3. In Karabiner-Elements, enable: Ame -> Ctrl-Command-Q starts Ame screen saver."
fi
if [[ "${AME_INSTALL_WALLPAPER:-0}" == "1" ]]; then
  echo "  4. Ame wallpaper mode is installed as a login item LaunchAgent."
fi
echo ""
echo "Try it now: ame"
