#!/bin/bash
# Sync ~/.config/zellij dotfiles to this repository.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$HOME/.config/zellij"
DEST="$SCRIPT_DIR/zellij"

# shellcheck source=lib/sync-common.sh
source "$SCRIPT_DIR/lib/sync-common.sh"

sync_common::parse_args "$(basename "$0")" "Sync ~/.config/zellij dotfiles to this repository." "$@"
sync_common::show_header "$(basename "$0")"

# top-level config
sync_common::sync_file "$SOURCE/config.kdl" "$DEST/config.kdl" "config.kdl" || true

echo ""
echo "Done."
