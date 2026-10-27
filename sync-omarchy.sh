#!/bin/bash
# Sync the Omarchy desktop overrides (~/.config/hypr, ~/.config/omarchy)
# with this repository.
#
# Only the files that carry personal settings are listed here. Omarchy ships
# defaults for everything else and `omarchy refresh <app>` restores them, so:
#
#   hypr/input.lua      -> ~/.config/hypr/input.lua       (keyboard + pointer)
#   omarchy/shell.json  -> ~/.config/omarchy/shell.json   (bar layout, clock)
#
# Deliberately NOT synced:
#   hypr/monitors.lua     machine-specific monitor names/modes
#   hypr/bindings.lua     Omarchy's stock bindings; only rebinds would matter
#   hypr/looknfeel.lua    stock appearance, restored by `omarchy refresh hyprland`
#   hypr/autostart.lua    stock autostart
#
# Both files hot-reload: Hyprland on save (validate with `hyprctl reload`
# then `hyprctl configerrors`), the Omarchy shell on save of shell.json
# (`omarchy restart shell` if it ever sticks).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

# shellcheck source=lib/sync-common.sh
source "$SCRIPT_DIR/lib/sync-common.sh"

sync_common::parse_args "$(basename "$0")" "Sync Omarchy desktop overrides (~/.config/hypr, ~/.config/omarchy) with this repository." "$@"
sync_common::show_header "$(basename "$0")"

# HOME path (relative to $CONFIG_HOME) -> repo path
SYNC_PAIRS=(
  "hypr/input.lua:hypr/input.lua"
  "omarchy/shell.json:omarchy/shell.json"
)

for pair in "${SYNC_PAIRS[@]}"; do
  home_rel="${pair%%:*}"
  repo_rel="${pair##*:}"
  sync_common::sync_file "$CONFIG_HOME/$home_rel" "$SCRIPT_DIR/$repo_rel" "$repo_rel" || true
done

echo ""
echo "Done."
