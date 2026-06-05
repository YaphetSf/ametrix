#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${AMETRIX_BIN_DEST:-}" ]]; then
  AMETRIX_PATH="$AMETRIX_BIN_DEST"
elif command -v ametrix >/dev/null 2>&1; then
  AMETRIX_PATH="$(command -v ametrix)"
elif command -v brew >/dev/null 2>&1 && [[ -x "$(brew --prefix)/bin/ametrix" ]]; then
  AMETRIX_PATH="$(brew --prefix)/bin/ametrix"
elif [[ -x "$HOME/.local/bin/ametrix" ]]; then
  AMETRIX_PATH="$HOME/.local/bin/ametrix"
else
  echo "Error: ametrix binary not found."
  echo "Run scripts/install.sh first, or set AMETRIX_BIN_DEST to the installed ametrix path."
  exit 1
fi

if [[ ! -x "$AMETRIX_PATH" ]]; then
  echo "Error: ametrix is not executable at $AMETRIX_PATH"
  exit 1
fi

KARABINER_DIR="$HOME/.config/karabiner/assets/complex_modifications"
RULE_PATH="$KARABINER_DIR/ametrix-lock-screen.json"

mkdir -p "$KARABINER_DIR"

cat > "$RULE_PATH" <<JSON
{
  "title": "Ametrix",
  "rules": [
    {
      "description": "Ctrl-Command-Q starts Ametrix screen saver",
      "manipulators": [
        {
          "type": "basic",
          "from": {
            "key_code": "q",
            "modifiers": {
              "mandatory": ["control", "command"],
              "optional": ["caps_lock", "fn"]
            }
          },
          "to": [
            {
              "shell_command": "nohup '${AMETRIX_PATH}' >/tmp/ametrix-karabiner.log 2>&1 &"
            }
          ]
        }
      ]
    }
  ]
}
JSON

echo "Installed Karabiner rule to $RULE_PATH"
echo ""
if [[ ! -d "/Applications/Karabiner-Elements.app" ]]; then
  echo "Karabiner-Elements was not found in /Applications."
  echo "Install it first if you want Ctrl-Command-Q to trigger Ametrix."
  echo ""
fi
echo "Enable it in Karabiner-Elements:"
echo "  Complex Modifications -> Add predefined rule -> Ametrix -> Enable"
echo ""
echo "For lock-on-screen-saver behavior, set macOS to require password immediately after the screen saver begins."
echo "Karabiner command log: /tmp/ametrix-karabiner.log"
