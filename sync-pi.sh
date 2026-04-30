#!/bin/bash
# Sync ~/.pi/agent/ dotfiles to this repository.
# Same direction as sync-opencode.sh: HOME -> repo (snapshot).
#
# auth.json / sessions/ / bin/ / node_modules はリポジトリに含めない。
# ~/.pi/agent/skills/ は pi-subagents パッケージ由来の design スキル
# (adapt, animate, ...) と混在しているため、自分の workflow スキルだけを
# allowlist で抽出して同期する。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$HOME/.pi/agent"
DEST="$SCRIPT_DIR/pi"

# Interactive mode flag (default: on)
INTERACTIVE=1

# Global variable for interactive prompt result
PROMPT_ACTION=""

# Track temp files so they're cleaned up even on Ctrl+C / abnormal exit
TMP_FILES=()
cleanup_tmp() {
  local f
  for f in "${TMP_FILES[@]:-}"; do
    [[ -n "$f" && -f "$f" ]] && rm -f "$f"
  done
}
trap cleanup_tmp EXIT INT TERM

# Usage function
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Sync ~/.pi/agent/ dotfiles to this repository.
Default mode: interactive (show diffs and prompt before syncing).

Options:
  -n, --non-interactive  Auto-copy without prompting
  -h, --help             Show this help message and exit
EOF
  exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--non-interactive)
      INTERACTIVE=0
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Error: Unknown option '$1'" >&2
      usage
      ;;
  esac
done

# Show diff between two files
# Sets: DIFF_RESULT (0=same, 1=different, 2=error)
show_diff() {
  local src="$1"
  local dst="$2"
  
  DIFF_RESULT=0
  
  # Check if both files exist
  if [[ ! -f "$src" ]]; then
    echo "  Source file not found: $src"
    DIFF_RESULT=2
    return 2
  fi
  
  if [[ ! -f "$dst" ]]; then
    echo "  Destination file not found: $dst"
    DIFF_RESULT=2
    return 2
  fi
  
  # Check if files are identical
  if cmp -s "$src" "$dst"; then
    echo "  Files are identical"
    DIFF_RESULT=0
    return 0
  fi
  
  # Show diff with colordiff if available, otherwise use diff
  echo "--- $dst (repo)"
  echo "+++ $src (home)"
  if command -v colordiff &>/dev/null; then
    diff -u "$dst" "$src" | colordiff || true
  else
    diff -u "$dst" "$src" || true
  fi
  
  DIFF_RESULT=1
  return 1
}

# Interactive prompt for file sync decision
# Sets: PROMPT_ACTION (a=accept, k=keep, s=skip, e=edit, q=quit)
interactive_prompt() {
  local rel_path="$1"
  
  PROMPT_ACTION=""
  
  while [[ -z "$PROMPT_ACTION" ]]; do
    echo ""
    echo "File: $rel_path"
    echo "Actions:"
    echo "  (a)ccept HOME  - Copy HOME version to repo"
    echo "  (k)eep repo    - Keep current repo version, skip this file"
    echo "  (s)how diff    - Show diff again"
    echo "  (e)dit         - Open editor for manual merge"
    echo "  (q)uit         - Stop sync process"
    echo ""
    read -rp "Choose action [a/k/s/e/q]: " choice
    
    case "$choice" in
      a|A)
        echo "  → Accepting HOME version"
        PROMPT_ACTION="a"
        ;;
      k|K)
        echo "  → Keeping repo version"
        PROMPT_ACTION="k"
        ;;
      s|S)
        echo "  → Showing diff again"
        PROMPT_ACTION="s"
        ;;
      e|E)
        echo "  → Opening editor for manual merge"
        PROMPT_ACTION="e"
        ;;
      q|Q)
        echo "  → Quitting sync"
        PROMPT_ACTION="q"
        ;;
      *)
        echo "  Invalid choice. Please enter a, k, s, e, or q."
        ;;
    esac
  done
}

# Manual merge: when both files exist and the editor is vim/nvim, use diff mode
# (true 3-way feel — user edits the repo side directly while seeing HOME on the
# right). Otherwise, fall back to editing a tmp copy of HOME and saving it to
# the repo if the user made changes.
manual_merge() {
  local src="$1"
  local dst="$2"

  local editor="${VISUAL:-${EDITOR:-vim}}"
  local editor_basename
  editor_basename="$(basename "$editor")"

  if [[ -f "$dst" ]] && [[ "$editor_basename" =~ ^(vim|nvim)$ ]]; then
    echo "Opening $editor in diff mode"
    echo "  Left:  $dst (repo — edit this side)"
    echo "  Right: $src (home — reference)"
    echo ""
    "$editor" -d "$dst" "$src"
    echo "  → Saved repo version"
    return 0
  fi

  local tmp_file
  tmp_file=$(mktemp)
  TMP_FILES+=("$tmp_file")

  cp "$src" "$tmp_file"

  echo "Opening editor: $editor"
  echo "  Source (HOME):      $src"
  echo "  Destination (repo): $dst"
  echo "  Working copy:       $tmp_file"
  echo ""

  "$editor" "$tmp_file"

  # Save when dst doesn't exist yet, or when the user made edits
  if [[ ! -f "$dst" ]] || ! cmp -s "$tmp_file" "$src"; then
    echo "  → Saving edited version to repo"
    mkdir -p "$(dirname "$dst")"
    cp "$tmp_file" "$dst"
  else
    echo "  → No changes made, keeping repo version"
  fi

  rm -f "$tmp_file"
}

# Sync a single file with optional interactive mode
# Returns: 0 on success, 1 on skip/quit
sync_file() {
  local src="$1"
  local dst="$2"
  local rel_path="${3:-$(basename "$src")}"
  
  # Handle missing source
  if [[ ! -f "$src" ]]; then
    echo "Warning: $src not found in HOME — run sync-pi.sh after deploying first." >&2
    return 1
  fi
  
  if [[ $INTERACTIVE -eq 1 ]]; then
    # Check if destination exists and differs
    local is_new=0
    if [[ -f "$dst" ]]; then
      show_diff "$src" "$dst" || true
    else
      echo "  → New file in repo: $rel_path"
      is_new=1
    fi
    
    # Get user decision
    while true; do
      interactive_prompt "$rel_path"
      
      case "$PROMPT_ACTION" in
        a)
          mkdir -p "$(dirname "$dst")"
          cp -v "$src" "$dst"
          return 0
          ;;
        k)
          if [[ $is_new -eq 1 ]]; then
            echo "  → Skipping new file"
          else
            echo "  → Keeping repo version"
          fi
          return 0
          ;;
        s)
          # Show diff again and loop
          if [[ $is_new -eq 0 ]]; then
            show_diff "$src" "$dst" || true
          else
            echo "  → New file in repo: $rel_path"
          fi
          continue
          ;;
        e)
          manual_merge "$src" "$dst"
          return 0
          ;;
        q)
          echo "Sync interrupted by user"
          exit 130
          ;;
      esac
    done
  else
    # Non-interactive mode: just copy
    mkdir -p "$(dirname "$dst")"
    cp -v "$src" "$dst"
  fi
  
  return 0
}

# Sync a directory with optional interactive mode
sync_directory() {
  local src_dir="$1"
  local dst_dir="$2"
  local pattern="${3:-*.md}"
  
  if [[ ! -d "$src_dir" ]]; then
    echo "Warning: $src_dir not found in HOME — run sync-pi.sh after deploying first." >&2
    return 1
  fi
  
  mkdir -p "$dst_dir"

  # NUL-separated to handle filenames with spaces/newlines safely
  while IFS= read -r -d '' src_file; do
    local rel_path="${src_file#$src_dir/}"
    local dst_file="$dst_dir/$rel_path"
    sync_file "$src_file" "$dst_file" "$rel_path" || true
  done < <(find "$src_dir" -maxdepth 1 -name "$pattern" -type f -print0 2>/dev/null)
}

# Main sync logic

echo "=== sync-pi.sh ==="
if [[ $INTERACTIVE -eq 1 ]]; then
  echo "Mode: Interactive (diff/merge)"
else
  echo "Mode: Non-interactive (auto-copy)"
fi
echo ""

# Shared global instructions (root AGENTS.md, used by all CLIs).
sync_file "$SOURCE/AGENTS.md" "$SCRIPT_DIR/AGENTS.md" "AGENTS.md" || true

# Top-level pi config
sync_file "$SOURCE/settings.json" "$DEST/settings.json" "settings.json" || true

# Extensions
#   permissions/    : directory extension -> repo に flat な permissions.ts として保存
#                     (Atuin history tracking is integrated into permissions.ts)
mkdir -p "$DEST/extensions"
if [[ -f "$SOURCE/extensions/permissions/index.ts" ]]; then
  sync_file "$SOURCE/extensions/permissions/index.ts" "$DEST/extensions/permissions.ts" "extensions/permissions.ts" || true
else
  echo "Warning: $SOURCE/extensions/permissions/index.ts not found in HOME — run sync-pi.sh after deploying first." >&2
fi

# Workflow skills (allowlist — design スキルは除外)
WORKFLOW_SKILLS=(orchestrate startproject team-implement team-review deploy)
mkdir -p "$DEST/skills"
for skill in "${WORKFLOW_SKILLS[@]}"; do
  src="$SOURCE/skills/$skill"
  if [[ -d "$src" ]]; then
    mkdir -p "$DEST/skills/$skill"
    if [[ $INTERACTIVE -eq 1 ]]; then
      # Interactive mode: show dry-run, then prompt. Loop on 's' so the user
      # can re-show the diff without accepting or skipping.
      echo ""
      echo "=== Skills: $skill ==="

      skill_done=0
      while [[ $skill_done -eq 0 ]]; do
        rsync -av --dry-run --delete \
          --exclude='node_modules' \
          --exclude='*.lock' \
          "$src/" "$DEST/skills/$skill/" || true

        interactive_prompt "skills/$skill"

        case "$PROMPT_ACTION" in
          a)
            rsync -av --delete \
              --exclude='node_modules' \
              --exclude='*.lock' \
              "$src/" "$DEST/skills/$skill/"
            skill_done=1
            ;;
          k)
            echo "  → Skipping skills/$skill"
            skill_done=1
            ;;
          s)
            # Loop and re-show the dry-run output
            ;;
          e)
            # For directories, open the main file in editor
            if [[ -f "$src/index.md" ]]; then
              manual_merge "$src/index.md" "$DEST/skills/$skill/index.md"
            fi
            skill_done=1
            ;;
          q)
            echo "Sync interrupted by user"
            exit 130
            ;;
        esac
      done
    else
      rsync -av --delete \
        --exclude='node_modules' \
        --exclude='*.lock' \
        "$src/" "$DEST/skills/$skill/"
    fi
  else
    echo "Warning: $src not found in HOME — run sync-pi.sh after deploying first." >&2
  fi
done

# Subagent definitions
sync_directory "$SOURCE/agents" "$DEST/agents" "*.md" || true

# Workflow prompt templates
sync_directory "$SOURCE/prompts" "$DEST/prompts" "*.md" || true

echo ""
echo "Done."
