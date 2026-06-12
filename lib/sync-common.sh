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

# Terminal-aware UI width shared by the file header and diff box.
# Echoes a width clamped to [40, 100].
sync_common::ui_width() {
  local width
  width=$(tput cols 2>/dev/null || echo 80)
  if [[ $width -gt 100 ]]; then
    width=100
  elif [[ $width -lt 40 ]]; then
    width=40
  fi
  echo "$width"
}

# Print a diff between two files inside a visual box.
# Sign convention is FIXED regardless of which side is missing:
#   '-' (red)   = repo side
#   '+' (green) = HOME side
# A missing side is diffed against /dev/null, so a file that exists only in
# HOME renders as all '+', and one that exists only in repo as all '-'.
# Renders via delta when available (syntax highlighting, line numbers),
# falling back to colordiff, then plain diff.
# Args: src (HOME path), dst (repo path), [max_lines (default: 40)].
sync_common::print_diff_box() {
  local src="$1"
  local dst="$2"
  local max_lines="${3:-40}"

  local width
  width=$(sync_common::ui_width)

  # Build dash line efficiently — no seq, no multibyte issues
  local dashes
  printf -v dashes '%*s' $((width - 2)) ''
  dashes=${dashes// /─}

  # Fixed orientation: repo is always the '-' side, HOME always the '+' side.
  local repo_side="$dst"
  local home_side="$src"
  [[ -f "$repo_side" ]] || repo_side=/dev/null
  [[ -f "$home_side" ]] || home_side=/dev/null

  # Keep the real filename in the labels so delta can pick the syntax
  # highlighting language from the extension.
  local name
  name=$(basename "${dst:-$src}")
  local repo_label="repo/$name"
  local home_label="HOME/$name"

  echo ""
  echo "┌${dashes}┐"
  printf '│ Diff: \e[31m− repo\e[0m / \e[32m+ HOME\e[0m\n'
  echo "├${dashes}┤"

  local diff_output
  if command -v delta &>/dev/null; then
    diff_output=$(diff -u --label "$repo_label" --label "$home_label" "$repo_side" "$home_side" 2>/dev/null \
      | delta --paging=never --keep-plus-minus-markers --file-style=omit \
              --hunk-header-style='line-number' --hunk-header-decoration-style=omit \
              --width=$((width - 2))) || true
  elif command -v colordiff &>/dev/null; then
    diff_output=$(diff -u --label "$repo_label" --label "$home_label" "$repo_side" "$home_side" 2>/dev/null | colordiff) || true
  else
    diff_output=$(diff -u --label "$repo_label" --label "$home_label" "$repo_side" "$home_side" 2>/dev/null) || true
  fi

  # delta emits a leading blank line — drop it so the box stays tight.
  diff_output="${diff_output#$'\n'}"

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

# Print a prominent header line for the file currently being prompted.
# Bold filename between two ═ separator lines, sized to terminal width.
# Args: rel_path.
sync_common::print_file_header() {
  local rel_path="$1"

  local width
  width=$(sync_common::ui_width)

  local equals
  printf -v equals '%*s' "$width" ''
  equals=${equals// /═}

  echo ""
  echo "$equals"
  printf '  \e[1mFile: %s\e[0m\n' "$rel_path"
  echo "$equals"
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
    sync_common::print_file_header "$rel_path"

    # Show diff/preview box.
    if [[ -n "$src" && -n "$dst" ]]; then
      if [[ ! -f "$src" && -f "$dst" ]]; then
        echo "  (only in repo — not yet in HOME)"
        sync_common::print_diff_box "$src" "$dst"
      elif [[ ! -f "$dst" && -f "$src" ]]; then
        echo "  (new file — not yet in repo)"
        sync_common::print_diff_box "$src" "$dst"
      elif [[ -f "$src" && -f "$dst" ]]; then
        if ! cmp -s "$src" "$dst"; then
          sync_common::print_diff_box "$src" "$dst"
        else
          echo "  (identical — no changes to sync)"
        fi
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

  if [[ ! -f "$src" && ! -f "$dst" ]]; then
    return 0
  fi

  if [[ $INTERACTIVE -eq 1 ]]; then
    local only_in_home=0
    local only_in_repo=0
    if [[ ! -f "$dst" ]]; then
      only_in_home=1
    elif [[ ! -f "$src" ]]; then
      only_in_repo=1
    else
      sync_common::show_diff "$src" "$dst" || true
    fi

    while true; do
      sync_common::interactive_prompt "$rel_path" "$src" "$dst"

      case "$PROMPT_ACTION" in
        a)
          if [[ $only_in_repo -eq 1 ]]; then
            echo "  → Cannot copy HOME → repo: HOME version doesn't exist"
            continue
          fi
          mkdir -p "$(dirname "$dst")"
          cp -v "$src" "$dst"
          return 0
          ;;
        p)
          if [[ $only_in_home -eq 1 ]]; then
            echo "  → Cannot push to HOME: repo version doesn't exist yet"
            continue
          fi
          mkdir -p "$(dirname "$src")"
          cp -v "$dst" "$src"
          return 0
          ;;
        s)
          if [[ $only_in_home -eq 1 ]]; then
            echo "  → Skipping — new file left as-is in repo"
          elif [[ $only_in_repo -eq 1 ]]; then
            echo "  → Skipping — repo file not copied to HOME"
          else
            echo "  → Skipping — keeping both HOME and repo versions unchanged"
          fi
          return 0
          ;;
        d)
          # interactive_prompt's next iteration re-renders the header and box.
          continue
          ;;
        q)
          echo "Sync interrupted by user"
          exit 130
          ;;
      esac
    done
  else
    if [[ -f "$src" ]]; then
      mkdir -p "$(dirname "$dst")"
      cp -v "$src" "$dst"
    fi
  fi

  return 0
}

# Sync files matching a glob pattern in a directory tree (recursive).
# Args: src_dir, dst_dir, [pattern (default: *.md)].
# Each matching file is prompted individually via sync_file.
# Excludes: node_modules/ trees and *.lock files.
sync_common::sync_directory() {
  local src_dir="$1"
  local dst_dir="$2"
  local pattern="${3:-*.md}"

  if [[ ! -d "$src_dir" && ! -d "$dst_dir" ]]; then
    echo "Warning: neither $src_dir nor $dst_dir exists — run the sync script after deploying first." >&2
    return 1
  fi

  mkdir -p "$dst_dir"

  # Walk both sides and take the union of relative paths, so files that
  # exist only in repo (or only in HOME) are both surfaced for sync.
  local -a rel_paths=()
  if [[ -d "$src_dir" ]]; then
    while IFS= read -r -d '' src_file; do
      rel_paths+=("${src_file#$src_dir/}")
    done < <(find "$src_dir" \
      -name 'node_modules' -prune -o \
      -type f -name "$pattern" ! -name '*.lock' -print0 \
      2>/dev/null)
  fi
  if [[ -d "$dst_dir" ]]; then
    while IFS= read -r -d '' dst_file; do
      rel_paths+=("${dst_file#$dst_dir/}")
    done < <(find "$dst_dir" \
      -name 'node_modules' -prune -o \
      -type f -name "$pattern" ! -name '*.lock' -print0 \
      2>/dev/null)
  fi

  if [[ ${#rel_paths[@]} -eq 0 ]]; then
    return 0
  fi

  while IFS= read -r rel_path; do
    [[ -z "$rel_path" ]] && continue
    sync_common::sync_file "$src_dir/$rel_path" "$dst_dir/$rel_path" "$rel_path" || true
  done < <(printf '%s\n' "${rel_paths[@]}" | sort -u)
}
