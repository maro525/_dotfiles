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

# Cloudflare plugin skills are vendor content — see SYNC_COMMON_CLOUDFLARE_SKILLS.
SKILL_EXCLUDES=("${SYNC_COMMON_CLOUDFLARE_SKILLS[@]}")

# Files that external workflow repositories place in ~/.config/opencode (the
# phase agents and the /orchestrate commands). dotfiles does not own them, so
# they are excluded by name. Keep these lists in step with the external side
# (it lists the same names from its own side).
EXTERNAL_PHASES=(startproject.md team-implement.md team-review.md deploy.md)
EXTERNAL_COMMANDS=(orchestrate.md "${EXTERNAL_PHASES[@]}")

# top-level files
# AGENTS.md is OpenCode-specific (per-CLI split — pi has its own pi/AGENTS.md).
sync_common::sync_file "$SOURCE/AGENTS.md"      "$DEST/AGENTS.md"           "opencode/AGENTS.md" || true
sync_common::sync_file "$SOURCE/opencode.jsonc" "$DEST/opencode.jsonc"      "opencode.jsonc" || true

# agents
sync_common::sync_directory "$SOURCE/agents" "$DEST/agents" "*.md" "${EXTERNAL_PHASES[@]}" || true

# commands
sync_common::sync_directory "$SOURCE/commands" "$DEST/commands" "*.md" "${EXTERNAL_COMMANDS[@]}" || true

# skills (recursive — includes nested SKILL.md and assets)
sync_common::sync_directory "$SOURCE/skills" "$DEST/skills" "*" "${SKILL_EXCLUDES[@]}" || true

echo ""
echo "Done."
