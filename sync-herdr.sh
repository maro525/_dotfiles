#!/bin/bash
# Sync ~/.config/herdr/config.toml to this repository.
#
# Only config.toml is carried: the rest of ~/.config/herdr is runtime state
# (sockets, logs, session.json, session-snapshots) and must stay out of git.
#
# Currently bound agent keys:
#   alt+h  -> previous_agent
#   alt+l  -> next_agent

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="${XDG_CONFIG_HOME:-$HOME/.config}/herdr"
DEST="$SCRIPT_DIR/herdr"

# shellcheck source=lib/sync-common.sh
source "$SCRIPT_DIR/lib/sync-common.sh"

sync_common::parse_args "$(basename "$0")" "Sync ~/.config/herdr/config.toml to this repository." "$@"
sync_common::show_header "$(basename "$0")"

sync_common::sync_file "$SOURCE/config.toml" "$DEST/config.toml" "config.toml" || true

echo ""
echo "Done."
