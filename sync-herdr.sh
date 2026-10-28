#!/bin/bash
# Sync ~/.config/herdr/ files to this repository.
#
# Carried: config.toml and sort-spaces.py (the on-demand Spaces sorter bound to
# prefix+shift+s, which calls workspace.move_block over the socket API).
# Everything else in ~/.config/herdr is runtime state (sockets, logs,
# session.json, session-snapshots) and stays out of git.
#
# Currently bound agent keys:
#   alt+h  -> previous_agent
#   alt+l  -> next_agent
#   prefix+shift+s -> custom shell command: sort spaces A-Z

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="${XDG_CONFIG_HOME:-$HOME/.config}/herdr"
DEST="$SCRIPT_DIR/herdr"

# shellcheck source=lib/sync-common.sh
source "$SCRIPT_DIR/lib/sync-common.sh"

sync_common::parse_args "$(basename "$0")" "Sync ~/.config/herdr/{config.toml,sort-spaces.py} to this repository." "$@"
sync_common::show_header "$(basename "$0")"

sync_common::sync_file "$SOURCE/config.toml" "$DEST/config.toml" "config.toml" || true
sync_common::sync_file "$SOURCE/sort-spaces.py" "$DEST/sort-spaces.py" "sort-spaces.py" || true

echo ""
echo "Done."
