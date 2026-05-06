#!/bin/bash
# Shared sync helpers for sync-pi.sh / sync-claude.sh / sync-opencode.sh.
#
# Provides:
#   - Interactive diff + a/p/s/d/q prompt for syncing HOME <-> repo
#   - Optional non-interactive (auto-copy HOME -> repo) mode via -n
#   - File / directory / rsync-based sync helpers
#
# Source this file from each sync script:
#   source "$SCRIPT_DIR/lib/sync-common.sh"
#   sync_common::parse_args "$(basename "$0")" "Sync ... description ..." "$@"
#   sync_common::show_header "$(basename "$0")"
#
# Public globals (set by helpers, read by callers):
#   INTERACTIVE     1 = interactive (default), 0 = non-interactive
#   PROMPT_ACTION   last interactive_prompt result (a/p/s/d/q)
#   DIFF_RESULT     last show_diff result (0=same, 1=different, 2=error)

# Guard against double-sourcing.
if [[ "${SYNC_COMMON_SOURCED:-0}" == "1" ]]; then
  return 0
fi
SYNC_COMMON_SOURCED=1

# Default to interactive; parse_args may flip this.
INTERACTIVE=1
PROMPT_ACTION=""
DIFF_RESULT=0

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

# Print a diff between two files inside a visual box.
# Args: src, dst, [max_lines (default: 40)].
sync_common::print_diff_box() {
  local src="$1"
  local dst="$2"
  local max_lines="${3:-40}"

  local src_label="HOME"
  local dst_label="repo"

  # Dynamic terminal width (default 62 if tput unavailable)
  local width
  width=$(tput cols 2>/dev/null || echo 80)
  if [[ $width -gt 62 ]]; then
    width=62
  elif [[ $width -lt 40 ]]; then
    width=40
  fi

  # Build dash line efficiently — no seq, no multibyte issues
  local dashes
  printf -v dashes '%*s' $((width - 2)) ''
  dashes=${dashes// /─}

  echo ""
  echo "┌${dashes}┐"
  echo "│ Diff: $dst_label → $src_label"
  echo "├${dashes}┤"

  local diff_output
  if command -v colordiff &>/dev/null; then
    diff_output=$(diff -u "$dst" "$src" 2>/dev/null | colordiff) || true
  else
    diff_output=$(diff -u "$dst" "$src" 2>/dev/null) || true
  fi

  # P2: defensive check for empty diff_output
  if [[ -n "$diff_output" ]]; then
    local count=0
    while IFS= read -r line; do
      if [[ $count -ge $max_lines ]]; then
        echo "│   ... (truncated at $max_lines lines)"
        break
      fi
      echo "│ $line"
      count=$((count + 1))
    done <<< "$diff_output"
  else
    echo "│ (no differences)"
  fi

  echo "└${dashes}┘"
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
    DIFF_RESULT=0
    return 0
  fi

  DIFF_RESULT=1
  return 1
}

# Interactive prompt for sync decision.
# Args: rel_path, [src], [dst].
# Sets: PROMPT_ACTION (a=accept HOME→repo, p=push repo→HOME, s=skip, d=diff, q=quit).
sync_common::interactive_prompt() {
  local rel_path="$1"
  local src="${2:-}"
  local dst="${3:-}"

  PROMPT_ACTION=""

  while [[ -z "$PROMPT_ACTION" ]]; do
    echo ""
    echo "File: $rel_path"

    # Show diff with border if both files exist and differ
    if [[ -n "$src" && -n "$dst" && -f "$src" && -f "$dst" ]]; then
      if ! cmp -s "$src" "$dst"; then
        sync_common::print_diff_box "$src" "$dst"
      else
        echo "  (identical — no changes to sync)"
      fi
    fi

    echo ""
    echo "Actions:"
    echo "  (a)ccept HOME   - Copy HOME → repo"
    echo "  (p)ush to HOME  - Copy repo → HOME"
    echo "  (s)kip          - Keep both versions unchanged"
    echo "  (d)iff          - Show diff again"
    echo "  (q)uit          - Stop sync process"
    echo ""
    read -rp "Choose action [a/p/s/d/q]: " choice < /dev/tty || choice=""

    # Trim leading/trailing whitespace
    choice="$(echo "$choice" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    case "$choice" in
      a|A)
        echo "  → Accepted: a (copy HOME → repo)"
        PROMPT_ACTION="a"
        ;;
      p|P)
        echo "  → Accepted: p (copy repo → HOME)"
        PROMPT_ACTION="p"
        ;;
      s|S)
        echo "  → Accepted: s (skip)"
        PROMPT_ACTION="s"
        ;;
      d|D)
        echo "  → Showing diff again"
        PROMPT_ACTION="d"
        ;;
      q|Q)
        echo "  → Accepted: q (quit)"
        PROMPT_ACTION="q"
        ;;
      "")
        echo "  → No input available. Quitting sync."
        PROMPT_ACTION="q"
        ;;
      *)
        echo "  Invalid choice. Please enter a, p, s, d, or q."
        ;;
    esac
  done
}

# Sync a single file (HOME <-> repo, direction chosen interactively).
# Args: src, dst, [rel_path].
# Returns 0 on accept/push/skip, exits 130 on quit.
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
      sync_common::interactive_prompt "$rel_path" "$src" "$dst"

      case "$PROMPT_ACTION" in
        a)
          mkdir -p "$(dirname "$dst")"
          cp -v "$src" "$dst"
          return 0
          ;;
        p)
          if [[ $is_new -eq 1 ]]; then
            echo "  → Cannot push to HOME: repo version doesn't exist yet"
            continue
          fi
          mkdir -p "$(dirname "$src")"
          cp -v "$dst" "$src"
          return 0
          ;;
        s)
          if [[ $is_new -eq 1 ]]; then
            echo "  → Skipping — new file left as-is in repo"
          else
            echo "  → Skipping — keeping both HOME and repo versions unchanged"
          fi
          return 0
          ;;
        d)
          # Re-show the diff in the box format
          if [[ $is_new -eq 0 ]]; then
            sync_common::print_diff_box "$src" "$dst"
          else
            echo "  → New file in repo: $rel_path"
          fi
          continue
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
# Honors INTERACTIVE: shows rsync --dry-run output and prompts a/p/s/d/q.
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
        p)
          # Reverse direction: repo → HOME.
          rsync -av --delete \
            --exclude='node_modules' \
            --exclude='*.lock' \
            "$dst_dir/" "$src_dir/"
          done=1
          ;;
        s)
          echo "  → Skipping $label"
          done=1
          ;;
        d)
          # Loop and re-show the dry-run output.
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
