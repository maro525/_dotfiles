#!/bin/bash
# Sync ~/.pi/agent/ dotfiles to this repository.
# Same direction as sync-opencode.sh: HOME -> repo (snapshot).
#
# auth.json / sessions/ / bin/ / node_modules はリポジトリに含めない。
# 同期対象は pi 基本設定のみ (AGENTS.md / settings.json / permissions.ts)。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$HOME/.pi/agent"
DEST="$SCRIPT_DIR/pi"

# shellcheck source=lib/sync-common.sh
source "$SCRIPT_DIR/lib/sync-common.sh"

sync_common::parse_args "$(basename "$0")" "Sync ~/.pi/agent/ dotfiles to this repository." "$@"
sync_common::show_header "$(basename "$0")"

# pi global instructions (per-CLI split — OpenCode has its own opencode/AGENTS.md).
sync_common::sync_file "$SOURCE/AGENTS.md" "$DEST/AGENTS.md" "pi/AGENTS.md" || true

# Top-level pi config
sync_common::sync_file "$SOURCE/settings.json" "$DEST/settings.json" "settings.json" || true

# Extensions
#   permissions/    : directory extension -> repo に flat な permissions.ts として保存
#                     (Atuin history tracking is integrated into permissions.ts)
mkdir -p "$DEST/extensions"
if [[ -f "$SOURCE/extensions/permissions/index.ts" ]]; then
  sync_common::sync_file "$SOURCE/extensions/permissions/index.ts" "$DEST/extensions/permissions.ts" "extensions/permissions.ts" || true
else
  echo "Warning: $SOURCE/extensions/permissions/index.ts not found in HOME — run sync-pi.sh after deploying first." >&2
fi

echo ""
echo "Done."
