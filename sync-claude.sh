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

# Skills installed from the Cloudflare plugin bundle — vendor content, not
# personal config, so it stays out of the repo (cloudflare/ alone is 300+
# files of reference docs).
SKILL_EXCLUDES=(
  agents-sdk
  cloudflare
  cloudflare-email-service
  cloudflare-one
  cloudflare-one-migrations
  durable-objects
  sandbox-sdk
  turnstile-spin
  workers-best-practices
  wrangler
  web-perf
)

# Top-level config files
sync_common::sync_file "$SOURCE/CLAUDE.md"     "$DEST/CLAUDE.md"     "CLAUDE.md" || true
sync_common::sync_file "$SOURCE/settings.json" "$DEST/settings.json" "settings.json" || true

# Subdirectories — sync every file (bidirectional discovery surfaces files
# that exist only in repo or only in HOME).
sync_common::sync_directory "$SOURCE/commands" "$DEST/commands" "*" || true
sync_common::sync_directory "$SOURCE/hooks"    "$DEST/hooks"    "*" || true
sync_common::sync_directory "$SOURCE/rules"    "$DEST/rules"    "*" || true
sync_common::sync_directory "$SOURCE/skills"   "$DEST/skills"   "*" "${SKILL_EXCLUDES[@]}" || true

echo ""
echo "Done."
