#!/bin/bash
# Sync ~/.claude dotfiles to this repository

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$HOME/.claude"
DEST="$SCRIPT_DIR/claude"

# commands
mkdir -p "$DEST/commands"
cp -v "$SOURCE/commands/"*.md "$DEST/commands/"

# settings.json
cp -v "$SOURCE/settings.json" "$DEST/settings.json"

echo "Done."
