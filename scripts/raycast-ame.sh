#!/usr/bin/env bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Ame
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🌧️
# @raycast.packageName Ame

set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"

if ! command -v ame >/dev/null 2>&1; then
    echo "ame is not installed. Run scripts/install.sh from the Ame repo first."
    exit 1
fi

ame
