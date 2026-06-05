#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -n "${AMETRIX_BIN_DEST:-}" ]]; then
  BIN_DEST="$AMETRIX_BIN_DEST"
elif command -v brew >/dev/null 2>&1; then
  BIN_DEST="$(brew --prefix)/bin/ametrix"
else
  BIN_DEST="$HOME/.local/bin/ametrix"
fi

cd "$ROOT_DIR"

swift build --disable-sandbox -c release
mkdir -p "$(dirname "$BIN_DEST")"
cp "$ROOT_DIR/.build/release/ametrix" "$BIN_DEST"

"$ROOT_DIR/scripts/install-config.sh"
AMETRIX_OPEN_SETTINGS="${AMETRIX_OPEN_SETTINGS:-1}" "$ROOT_DIR/scripts/install-screensaver.sh"

if [[ "${AMETRIX_INSTALL_KARABINER:-1}" == "1" ]]; then
  AMETRIX_BIN_DEST="$BIN_DEST" "$ROOT_DIR/scripts/install-karabiner-lock.sh"
fi

if [[ "${AMETRIX_INSTALL_MENUBAR:-0}" == "1" ]]; then
  AMETRIX_BIN_DEST="$BIN_DEST" "$ROOT_DIR/scripts/install-menubar-agent.sh"
fi

echo ""
echo "Installed CLI to $BIN_DEST"
echo ""
echo "Next steps:"
echo "  1. Select Ametrix once in System Settings > Screen Saver."
echo "  2. Set macOS to require password immediately after the screen saver begins."
if [[ "${AMETRIX_INSTALL_KARABINER:-1}" == "1" ]]; then
  echo "  3. In Karabiner-Elements, enable: Ametrix -> Ctrl-Command-Q starts Ametrix screen saver."
fi
if [[ "${AMETRIX_INSTALL_MENUBAR:-0}" == "1" ]]; then
  echo "  4. Ametrix menu bar controller is installed as a login item LaunchAgent."
fi
echo ""
echo "Try it now: ametrix"
