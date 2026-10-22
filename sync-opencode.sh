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

# The /orchestrate workflow lives in its own repository (maro525/harness) and
# is synced by its sync-opencode.sh. Keep these lists in step with
# HARNESS_FILES there.
HARNESS_PHASES=(startproject.md team-implement.md team-review.md deploy.md)
HARNESS_COMMANDS=(orchestrate.md "${HARNESS_PHASES[@]}")

# top-level files
# AGENTS.md is OpenCode-specific (per-CLI split — pi has its own pi/AGENTS.md).
sync_common::sync_file "$SOURCE/AGENTS.md"      "$DEST/AGENTS.md"           "opencode/AGENTS.md" || true
sync_common::sync_file "$SOURCE/opencode.jsonc" "$DEST/opencode.jsonc"      "opencode.jsonc" || true

# agents
sync_common::sync_directory "$SOURCE/agents" "$DEST/agents" "*.md" "${HARNESS_PHASES[@]}" || true

# commands
sync_common::sync_directory "$SOURCE/commands" "$DEST/commands" "*.md" "${HARNESS_COMMANDS[@]}" || true

# skills (recursive — includes nested SKILL.md and assets)
sync_common::sync_directory "$SOURCE/skills" "$DEST/skills" "*" "${SKILL_EXCLUDES[@]}" || true

# Cross-repo 参照チェック（harness 側の checks/crossrefs.sh の「契約」を参照）。
# harness/opencode と opencode/AGENTS.md の相互参照（節名・ファイル名）が壊れて
# いないかを確認する。失敗しても同期は成功扱い（警告のみ）。
HARNESS_DIR="${HARNESS:-$HOME/src/harness}"
if [[ -f "$HARNESS_DIR/checks/crossrefs.sh" ]]; then
  bash "$HARNESS_DIR/checks/crossrefs.sh" "$SCRIPT_DIR" ||
    echo "Warning: cross-repo 参照チェックに失敗（上記 NG を確認）" >&2
fi

echo ""
echo "Done."
