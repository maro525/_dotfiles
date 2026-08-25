#!/bin/bash
# Sync tmux dotfiles to this repository.
#
# tmux 3.2+ loads BOTH files, in this order:
#   1. ~/.tmux.conf                 -> repo: tmux/.tmux.conf
#   2. ~/.config/tmux/tmux.conf     -> repo: tmux/tmux.conf   (loaded last, wins on conflicts)
# So both are kept here; neither shadows the other.
#
# Helper scripts invoked from the config live alongside them:
#   ~/.local/bin/tmux-pane-fzf      -> repo: tmux/bin/tmux-pane-fzf
#   ~/.local/bin/tmux-cc-jump       -> repo: tmux/bin/tmux-cc-jump
#
# The @cc pane option those scripts read is published by a Claude Code hook,
# which sync-claude.sh carries: claude/hooks/tmux-cc-status.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST="$SCRIPT_DIR/tmux"

# shellcheck source=lib/sync-common.sh
source "$SCRIPT_DIR/lib/sync-common.sh"

sync_common::parse_args "$(basename "$0")" "Sync tmux dotfiles to this repository." "$@"
sync_common::show_header "$(basename "$0")"

# legacy HOME-root config (loaded first)
sync_common::sync_file "$HOME/.tmux.conf" "$DEST/.tmux.conf" ".tmux.conf" || true

# XDG config (loaded second)
sync_common::sync_file "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf" "$DEST/tmux.conf" "tmux.conf" || true

# helper scripts bound from the config (prefix + C-p picker, prefix + C-w jump)
sync_common::sync_file "$HOME/.local/bin/tmux-pane-fzf" "$DEST/bin/tmux-pane-fzf" "bin/tmux-pane-fzf" || true
sync_common::sync_file "$HOME/.local/bin/tmux-cc-jump"  "$DEST/bin/tmux-cc-jump"  "bin/tmux-cc-jump"  || true

# cp does not restore the exec bit onto a pre-existing file, so re-assert it
# on whichever side now exists.
for script in "$DEST/bin/tmux-pane-fzf"  "$HOME/.local/bin/tmux-pane-fzf" \
              "$DEST/bin/tmux-cc-jump"   "$HOME/.local/bin/tmux-cc-jump"; do
  [[ -f "$script" ]] && chmod +x "$script" || true
done

echo ""
echo "Done."
