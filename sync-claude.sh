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

# settings.json
sync_common::sync_file "$SOURCE/settings.json" "$DEST/settings.json" "settings.json" || true

# commands
sync_common::sync_directory "$SOURCE/commands" "$DEST/commands" "*.md" || true

echo ""
echo "Done."
