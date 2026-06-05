#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${AMETRIX_REPO_URL:-https://github.com/YaphetSf/ametrix.git}"
INSTALL_DIR="${AMETRIX_INSTALL_DIR:-$HOME/.local/share/ametrix}"

if ! command -v git >/dev/null 2>&1; then
  echo "Error: git is required to install Ametrix."
  exit 1
fi

if [[ -d "$INSTALL_DIR/.git" ]]; then
  echo "Updating Ametrix in $INSTALL_DIR"
  if [[ -n "$(git -C "$INSTALL_DIR" status --porcelain)" ]]; then
    echo "Error: $INSTALL_DIR has local changes."
    echo "Commit, stash, or remove them before running the installer again."
    exit 1
  fi
  git -C "$INSTALL_DIR" fetch --quiet origin
  git -C "$INSTALL_DIR" reset --quiet --hard origin/main
elif [[ -e "$INSTALL_DIR" ]]; then
  echo "Error: $INSTALL_DIR exists but is not a git checkout."
  echo "Set AMETRIX_INSTALL_DIR to another path, or move that directory."
  exit 1
else
  echo "Cloning Ametrix to $INSTALL_DIR"
  mkdir -p "$(dirname "$INSTALL_DIR")"
  git clone --quiet "$REPO_URL" "$INSTALL_DIR"
fi

cd "$INSTALL_DIR"
scripts/install.sh
