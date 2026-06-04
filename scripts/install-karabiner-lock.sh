#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${AME_BIN_DEST:-}" ]]; then
  AME_PATH="$AME_BIN_DEST"
elif command -v ame >/dev/null 2>&1; then
  AME_PATH="$(command -v ame)"
elif command -v brew >/dev/null 2>&1 && [[ -x "$(brew --prefix)/bin/ame" ]]; then
  AME_PATH="$(brew --prefix)/bin/ame"
elif [[ -x "$HOME/.local/bin/ame" ]]; then
  AME_PATH="$HOME/.local/bin/ame"
else
  echo "Error: ame binary not found."
  echo "Run scripts/install.sh first, or set AME_BIN_DEST to the installed ame path."
  exit 1
fi

if [[ ! -x "$AME_PATH" ]]; then
  echo "Error: ame is not executable at $AME_PATH"
  exit 1
fi

KARABINER_DIR="$HOME/.config/karabiner/assets/complex_modifications"
RULE_PATH="$KARABINER_DIR/ame-lock-screen.json"

mkdir -p "$KARABINER_DIR"

cat > "$RULE_PATH" <<JSON
{
  "title": "Ame",
  "rules": [
    {
      "description": "Ctrl-Command-Q starts Ame screen saver",
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
              "shell_command": "nohup '${AME_PATH}' >/tmp/ame-karabiner.log 2>&1 &"
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
  echo "Install it first if you want Ctrl-Command-Q to trigger Ame."
  echo ""
fi
echo "Enable it in Karabiner-Elements:"
echo "  Complex Modifications -> Add predefined rule -> Ame -> Enable"
echo ""
echo "For lock-on-screen-saver behavior, set macOS to require password immediately after the screen saver begins."
echo "Karabiner command log: /tmp/ame-karabiner.log"
