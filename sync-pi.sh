#!/bin/bash
# Sync ~/.pi/agent/ dotfiles to this repository.
# Same direction as sync-opencode.sh: HOME -> repo (snapshot).
#
# auth.json / sessions/ / bin/ / node_modules はリポジトリに含めない。
# ~/.pi/agent/skills/ は pi-subagents パッケージ由来の design スキル
# (adapt, animate, ...) と混在しているため、自分の workflow スキルだけを
# allowlist で抽出して同期する。

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$HOME/.pi/agent"
DEST="$SCRIPT_DIR/pi"

# Shared global instructions (root AGENTS.md, used by all CLIs).
cp -v "$SOURCE/AGENTS.md" "$SCRIPT_DIR/AGENTS.md"

# Top-level pi config
cp -v "$SOURCE/settings.json" "$DEST/settings.json"

# Extensions
#   atuin.ts        : single-file extension
#   permissions/    : directory extension -> repo に flat な permissions.ts として保存
mkdir -p "$DEST/extensions"
cp -v "$SOURCE/extensions/atuin.ts"               "$DEST/extensions/atuin.ts"
cp -v "$SOURCE/extensions/permissions/index.ts"   "$DEST/extensions/permissions.ts"

# Workflow skills (allowlist — design スキルは除外)
WORKFLOW_SKILLS=(orchestrate startproject team-implement team-review deploy)
mkdir -p "$DEST/skills"
for skill in "${WORKFLOW_SKILLS[@]}"; do
  src="$SOURCE/skills/$skill"
  if [[ -d "$src" ]]; then
    mkdir -p "$DEST/skills/$skill"
    rsync -av --delete \
      --exclude='node_modules' \
      --exclude='*.lock' \
      "$src/" "$DEST/skills/$skill/"
  else
    echo "Warning: $src not found in HOME — run sync-pi.sh after deploying first." >&2
  fi
done

# Subagent definitions
mkdir -p "$DEST/agents"
cp -v "$SOURCE/agents/"*.md "$DEST/agents/"

# Workflow prompt templates
mkdir -p "$DEST/prompts"
cp -v "$SOURCE/prompts/"*.md "$DEST/prompts/"

echo "Done."
