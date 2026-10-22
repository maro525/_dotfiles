#!/bin/bash
# Sync Cline CLI dotfiles to this repository.
#
# Cline splits configuration across two roots:
#   ~/.cline/data/settings/  written by the cline binary
#   ~/Cline/                 user-authored Rules / Hooks / Workflows
#
# Files carrying credentials are deliberately never touched — not in either
# direction. See cline/README.md for the full list and the reasoning.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SETTINGS_SOURCE="$HOME/.cline/data/settings"
SKILLS_SOURCE="$HOME/.cline/skills"
USER_SOURCE="$HOME/Cline"
DEST="$SCRIPT_DIR/cline"

# shellcheck source=lib/sync-common.sh
source "$SCRIPT_DIR/lib/sync-common.sh"

sync_common::parse_args "$(basename "$0")" "Sync Cline CLI dotfiles to this repository." "$@"
sync_common::show_header "$(basename "$0")"

# Cloudflare plugin skills are vendor content — see SYNC_COMMON_CLOUDFLARE_SKILLS.
SKILL_EXCLUDES=("${SYNC_COMMON_CLOUDFLARE_SKILLS[@]}")

# Files owned by an external workflow repository (the /orchestrate phases) that
# are placed into ~/.cline/skills as symlinks to ~/.agents/skills. They are not
# dotfiles-owned, so they are excluded by name below. `find -type f` does not
# follow those symlinks today, but naming them keeps the workflow skills out of
# this repo if one is ever replaced by a real copy.
EXTERNAL_SKILLS=(startproject team-implement team-review deploy)

# CLI settings — only the credential-free files.
# secrets.json, providers.json and ~/.cline/config.json hold API keys and OAuth
# tokens, so they are excluded by omission: this script never names them.
sync_common::sync_file "$SETTINGS_SOURCE/global-settings.json"    "$DEST/global-settings.json"    "global-settings.json" || true
sync_common::sync_file "$SETTINGS_SOURCE/cline_mcp_settings.json" "$DEST/cline_mcp_settings.json" "cline_mcp_settings.json" || true

# User-authored config under ~/Cline (empty until you add your own).
sync_common::sync_directory "$USER_SOURCE/Rules"     "$DEST/Rules"     "*" || true
sync_common::sync_directory "$USER_SOURCE/Hooks"     "$DEST/Hooks"     "*" || true
sync_common::sync_directory "$USER_SOURCE/Workflows" "$DEST/Workflows" "*" || true

# skills (recursive — includes nested SKILL.md and assets)
sync_common::sync_directory "$SKILLS_SOURCE" "$DEST/skills" "*" "${SKILL_EXCLUDES[@]}" "${EXTERNAL_SKILLS[@]}" || true

echo ""
echo "Done."
