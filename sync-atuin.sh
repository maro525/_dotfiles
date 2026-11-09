#!/bin/bash
# Sync ~/.config/atuin (Atuin shell-history config) with this repository.
#
# Only config.toml is synced. The data directory (~/.local/share/atuin) holds
# the history database, the encryption key and the record store — machine-local
# state that must never be committed.
#
# Why the settings in config.toml exist:
#   history_filter  drop the noise commands (sleep/ls/cd/…) that used to fill
#                   the database; matches HISTIGNORE in bash/.bashrc
#   [sync] records  sync v2 flag — kept at true, it does not affect local writes
#
# The history itself is trimmed by atuin/prune-agent-history.sh (weekly cron),
# which deletes agent-recorded rows; see the comment in that script.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

# shellcheck source=lib/sync-common.sh
source "$SCRIPT_DIR/lib/sync-common.sh"

sync_common::parse_args "$(basename "$0")" "Sync ~/.config/atuin config.toml with this repository." "$@"
sync_common::show_header "$(basename "$0")"

sync_common::sync_file "$CONFIG_HOME/atuin/config.toml" "$SCRIPT_DIR/atuin/config.toml" "atuin/config.toml" || true

echo ""
echo "Done."
