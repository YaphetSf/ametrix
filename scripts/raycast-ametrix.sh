#!/usr/bin/env bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Ametrix
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🌧️
# @raycast.packageName Ametrix

set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"

if ! command -v ametrix >/dev/null 2>&1; then
    echo "ametrix is not installed. Run scripts/install.sh from the Ametrix repo first."
    exit 1
fi

ametrix
