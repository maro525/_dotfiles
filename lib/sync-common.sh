#!/bin/bash
# Shared sync helpers for sync-pi.sh / sync-claude.sh / sync-opencode.sh.
#
# Provides:
#   - Interactive diff + a/k/s/e/q prompt for syncing HOME -> repo snapshots
#   - Optional non-interactive (auto-copy) mode via -n / --non-interactive
#   - File / directory / rsync-based sync helpers
#
# Source this file from each sync script:
#   source "$SCRIPT_DIR/lib/sync-common.sh"
#   sync_common::init
#   sync_common::parse_args "$(basename "$0")" "Sync ... description ..." "$@"
#   sync_common::show_header "$(basename "$0")"
#
# Public globals (set by helpers, read by callers):
#   INTERACTIVE     1 = interactive (default), 0 = non-interactive
#   PROMPT_ACTION   last interactive_prompt result (a/k/s/e/q)
#   DIFF_RESULT     last show_diff result (0=same, 1=different, 2=error)
#   TMP_FILES       array of temp files cleaned up on exit

# Guard against double-sourcing.
if [[ "${SYNC_COMMON_SOURCED:-0}" == "1" ]]; then
  return 0
fi
SYNC_COMMON_SOURCED=1

# Default to interactive; parse_args may flip this.
INTERACTIVE=1
PROMPT_ACTION=""
DIFF_RESULT=0
TMP_FILES=()

# Initialize trap to clean up temp files on EXIT/INT/TERM.
sync_common::init() {
  trap sync_common::_cleanup_tmp EXIT INT TERM
}

sync_common::_cleanup_tmp() {
  local f
  for f in "${TMP_FILES[@]:-}"; do
    if [[ -n "$f" && -f "$f" ]]; then
      rm -f "$f"
    fi
  done
  return 0
}

# Print usage and exit. Args: script_name, description.
sync_common::usage() {
  local script_name="$1"
  local description="$2"
  cat <<EOF
Usage: $script_name [OPTIONS]

$description
Default mode: interactive (show diffs and prompt before syncing).

Options:
  -n, --non-interactive  Auto-copy without prompting
  -h, --help             Show this help message and exit
EOF
  exit 0
}

# Parse CLI args. Args: script_name, description, then "$@".
# Sets INTERACTIVE based on flags. Aborts on unknown options.
sync_common::parse_args() {
  local script_name="$1"
  local description="$2"
  shift 2

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n|--non-interactive)
        INTERACTIVE=0
        shift
        ;;
      -h|--help)
        sync_common::usage "$script_name" "$description"
        ;;
      *)
        echo "Error: Unknown option '$1'" >&2
        sync_common::usage "$script_name" "$description"
        ;;
    esac
  done
}

# Print header banner. Args: script_name.
sync_common::show_header() {
  local script_name="$1"
  echo "=== $script_name ==="
  if [[ $INTERACTIVE -eq 1 ]]; then
    echo "Mode: Interactive (diff/merge)"
  else
    echo "Mode: Non-interactive (auto-copy)"
  fi
  echo ""
}

# Show diff between two files.
# Args: src, dst.
# Sets: DIFF_RESULT (0=same, 1=different, 2=error).
sync_common::show_diff() {
  local src="$1"
  local dst="$2"

  DIFF_RESULT=0

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

  if cmp -s "$src" "$dst"; then
    echo "  Files are identical"
    DIFF_RESULT=0
    return 0
  fi

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

# Interactive prompt for sync decision.
# Args: rel_path (label shown to user).
# Sets: PROMPT_ACTION (a=accept, k=keep, s=show, e=edit, q=quit).
sync_common::interactive_prompt() {
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
# Args: src, dst.
sync_common::manual_merge() {
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

# Sync a single file (HOME -> repo).
# Args: src, dst, [rel_path].
# Returns 0 on accept/keep/edit, exits 130 on quit.
sync_common::sync_file() {
  local src="$1"
  local dst="$2"
  local rel_path="${3:-$(basename "$src")}"

  if [[ ! -f "$src" ]]; then
    echo "Warning: $src not found in HOME — run the sync script after deploying first." >&2
    return 1
  fi

  if [[ $INTERACTIVE -eq 1 ]]; then
    local is_new=0
    if [[ -f "$dst" ]]; then
      sync_common::show_diff "$src" "$dst" || true
    else
      echo "  → New file in repo: $rel_path"
      is_new=1
    fi

    while true; do
      sync_common::interactive_prompt "$rel_path"

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
          if [[ $is_new -eq 0 ]]; then
            sync_common::show_diff "$src" "$dst" || true
          else
            echo "  → New file in repo: $rel_path"
          fi
          continue
          ;;
        e)
          sync_common::manual_merge "$src" "$dst"
          return 0
          ;;
        q)
          echo "Sync interrupted by user"
          exit 130
          ;;
      esac
    done
  else
    mkdir -p "$(dirname "$dst")"
    cp -v "$src" "$dst"
  fi

  return 0
}

# Sync files matching a glob pattern in a single directory (non-recursive).
# Args: src_dir, dst_dir, [pattern (default: *.md)].
sync_common::sync_directory() {
  local src_dir="$1"
  local dst_dir="$2"
  local pattern="${3:-*.md}"

  if [[ ! -d "$src_dir" ]]; then
    echo "Warning: $src_dir not found in HOME — run the sync script after deploying first." >&2
    return 1
  fi

  mkdir -p "$dst_dir"

  # NUL-separated to handle filenames with spaces/newlines safely.
  while IFS= read -r -d '' src_file; do
    local rel_path="${src_file#$src_dir/}"
    local dst_file="$dst_dir/$rel_path"
    sync_common::sync_file "$src_file" "$dst_file" "$rel_path" || true
  done < <(find "$src_dir" -maxdepth 1 -name "$pattern" -type f -print0 2>/dev/null)
}

# Sync a directory tree using rsync, with interactive dry-run preview.
# Args: src_dir, dst_dir, [label (default: basename of dst_dir)].
# Honors INTERACTIVE: shows rsync --dry-run output and prompts a/k/s/e/q.
# 'e' opens manual_merge on src_dir/index.md or SKILL.md if present, then accepts.
sync_common::sync_rsync_dir() {
  local src_dir="$1"
  local dst_dir="$2"
  local label="${3:-$(basename "$dst_dir")}"

  if [[ ! -d "$src_dir" ]]; then
    echo "Warning: $src_dir not found in HOME — run the sync script after deploying first." >&2
    return 1
  fi

  mkdir -p "$dst_dir"

  if [[ $INTERACTIVE -eq 1 ]]; then
    echo ""
    echo "=== Directory: $label ==="

    local done=0
    while [[ $done -eq 0 ]]; do
      rsync -av --dry-run --delete \
        --exclude='node_modules' \
        --exclude='*.lock' \
        "$src_dir/" "$dst_dir/" || true

      sync_common::interactive_prompt "$label"

      case "$PROMPT_ACTION" in
        a)
          rsync -av --delete \
            --exclude='node_modules' \
            --exclude='*.lock' \
            "$src_dir/" "$dst_dir/"
          done=1
          ;;
        k)
          echo "  → Skipping $label"
          done=1
          ;;
        s)
          # Loop and re-show the dry-run output.
          ;;
        e)
          # Best-effort manual merge of the primary doc file in the directory.
          local primary=""
          if [[ -f "$src_dir/index.md" ]]; then
            primary="index.md"
          elif [[ -f "$src_dir/SKILL.md" ]]; then
            primary="SKILL.md"
          fi
          if [[ -n "$primary" ]]; then
            sync_common::manual_merge "$src_dir/$primary" "$dst_dir/$primary"
          else
            echo "  → No index.md/SKILL.md found; falling back to accept"
            rsync -av --delete \
              --exclude='node_modules' \
              --exclude='*.lock' \
              "$src_dir/" "$dst_dir/"
          fi
          done=1
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
      "$src_dir/" "$dst_dir/"
  fi
}
