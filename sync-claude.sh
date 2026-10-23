#!/bin/bash
# Sync ~/.claude dotfiles to this repository.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$HOME/.claude"
DEST="$SCRIPT_DIR/claude"

# shellcheck source=lib/sync-common.sh
source "$SCRIPT_DIR/lib/sync-common.sh"

sync_common::parse_args "$(basename "$0")" "Sync ~/.claude dotfiles to this repository." "$@"
sync_common::show_header "$(basename "$0")"

# Cloudflare plugin skills are vendor content — see SYNC_COMMON_CLOUDFLARE_SKILLS.
# skills/synced/ is managed by Claude Code itself (Anthropic-provided skills
# synced from the claude.ai account, re-created on every launch), so it is not
# personal config either.
SKILL_EXCLUDES=("${SYNC_COMMON_CLOUDFLARE_SKILLS[@]}" synced)

# Files that external workflow repositories place in ~/.claude (the /orchestrate
# commands, its rules and its hook). dotfiles does not own them, so they are
# excluded by name. Keep these lists in step with the external side (it lists the
# same names from its own side) — a file that appears here by accident would be
# committed to this repo.
EXTERNAL_COMMANDS=(orchestrate.md startproject.md team-implement.md team-review.md deploy.md)
EXTERNAL_RULES=(adaptive-execution.md tool-routing.md)
EXTERNAL_HOOKS=(agent-router.py)

# Top-level config files
sync_common::sync_file "$SOURCE/CLAUDE.md"     "$DEST/CLAUDE.md"     "CLAUDE.md" || true
sync_common::sync_file "$SOURCE/settings.json" "$DEST/settings.json" "settings.json" || true

# Subdirectories — sync every file (bidirectional discovery surfaces files
# that exist only in repo or only in HOME).
sync_common::sync_directory "$SOURCE/commands" "$DEST/commands" "*" "${EXTERNAL_COMMANDS[@]}" || true
sync_common::sync_directory "$SOURCE/hooks"    "$DEST/hooks"    "*" "${EXTERNAL_HOOKS[@]}" __pycache__ || true
sync_common::sync_directory "$SOURCE/rules"    "$DEST/rules"    "*" "${EXTERNAL_RULES[@]}" || true
sync_common::sync_directory "$SOURCE/skills"   "$DEST/skills"   "*" "${SKILL_EXCLUDES[@]}" || true

echo ""
echo "Done."
