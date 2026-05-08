#!/bin/bash
# Sync ~/.config/opencode dotfiles to this repository.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$HOME/.config/opencode"
DEST="$SCRIPT_DIR/opencode"

# shellcheck source=lib/sync-common.sh
source "$SCRIPT_DIR/lib/sync-common.sh"

sync_common::parse_args "$(basename "$0")" "Sync ~/.config/opencode dotfiles to this repository." "$@"
sync_common::show_header "$(basename "$0")"

# top-level files
# AGENTS.md is OpenCode-specific (per-CLI split — pi has its own pi/AGENTS.md).
sync_common::sync_file "$SOURCE/AGENTS.md"      "$DEST/AGENTS.md"           "opencode/AGENTS.md" || true
sync_common::sync_file "$SOURCE/opencode.jsonc" "$DEST/opencode.jsonc"      "opencode.jsonc" || true
sync_common::sync_file "$SOURCE/config.toml"    "$DEST/config.toml"         "config.toml" || true

# agents
sync_common::sync_directory "$SOURCE/agents" "$DEST/agents" "*.md" || true

# commands
sync_common::sync_directory "$SOURCE/commands" "$DEST/commands" "*.md" || true

# skills (recursive — includes nested SKILL.md and assets)
sync_common::sync_directory "$SOURCE/skills" "$DEST/skills" "*" || true

echo ""
echo "Done."
