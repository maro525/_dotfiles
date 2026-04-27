#!/bin/bash
# Sync ~/.config/opencode dotfiles to this repository

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$HOME/.config/opencode"
DEST="$SCRIPT_DIR/opencode"

# top-level files
cp -v "$SOURCE/AGENTS.md"       "$DEST/AGENTS.md"
cp -v "$SOURCE/opencode.jsonc"  "$DEST/opencode.jsonc"
cp -v "$SOURCE/config.toml"     "$DEST/config.toml"

# agents
mkdir -p "$DEST/agents"
cp -v "$SOURCE/agents/"*.md "$DEST/agents/"

# commands
mkdir -p "$DEST/commands"
cp -v "$SOURCE/commands/"*.md "$DEST/commands/"

# skills (recursive — includes nested SKILL.md and assets)
mkdir -p "$DEST/skills"
rsync -av --delete \
  --exclude='node_modules' \
  --exclude='*.lock' \
  "$SOURCE/skills/" "$DEST/skills/"

echo "Done."
