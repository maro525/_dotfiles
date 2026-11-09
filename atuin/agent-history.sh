#!/usr/bin/env bash
# エージェント (claude-code / pi など) が実行したコマンド履歴を検索する。
#
# atuin 本体の検索は history.db を全行スキャンするため、エージェント行は
# atuin/prune-agent-history.sh で archive/agent-history.db に退避している。
# このスクリプトはその退避先を引くためのもの。atuin の検索には一切影響しない。
#
# 例:
#   bash atuin/agent-history.sh --grep "pnpm test"          # 直近 50 件
#   bash atuin/agent-history.sh --author claude-code -n 20 --since "2026-10-01"
#   bash atuin/agent-history.sh --cwd ~/src/foo --count     # 件数だけ
#   bash atuin/agent-history.sh --grep migrate --json | jq .
set -euo pipefail

DATA_DIR="${ATUIN_DATA_DIR:-$HOME/.local/share/atuin}"
ARCHIVE_DB="${AGENT_ARCHIVE_DB:-$DATA_DIR/archive/agent-history.db}"

usage() {
  sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

grep_pattern=""
author=""
cwd=""
since=""
limit=50
count_only=0
json=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -g|--grep) grep_pattern="${2:-}"; shift 2 ;;
    -a|--author) author="${2:-}"; shift 2 ;;
    -d|--cwd) cwd="${2:-}"; shift 2 ;;
    -s|--since) since="${2:-}"; shift 2 ;;
    -n|--limit) limit="${2:-}"; shift 2 ;;
    --count) count_only=1; shift ;;
    --json) json=1; shift ;;
    -h|--help) usage 0 ;;
    -*) echo "unknown option: $1" >&2; usage 1 ;;
    *) grep_pattern="$1"; shift ;;
  esac
done

if [[ ! -f "$ARCHIVE_DB" ]]; then
  echo "アーカイブがありません: $ARCHIVE_DB" >&2
  echo "エージェント行はまだ移送されていない可能性があります (atuin/prune-agent-history.sh を参照)" >&2
  exit 1
fi

SQLITE3="${SQLITE3:-$(command -v sqlite3 || true)}"
if [ -z "$SQLITE3" ]; then
  for candidate in /home/linuxbrew/.linuxbrew/bin/sqlite3 /usr/bin/sqlite3; do
    if [ -x "$candidate" ]; then SQLITE3="$candidate"; break; fi
  done
fi
[[ -n "$SQLITE3" ]] || { echo "sqlite3 が見つかりません" >&2; exit 1; }

# SQL リテラル用にシングルクォートをエスケープ
esc() { printf '%s' "$1" | sed "s/'/''/g"; }

where="1=1"
[[ -n "$grep_pattern" ]] && where="$where and command like '%$(esc "$grep_pattern")%'"
[[ -n "$author" ]] && where="$where and author = '$(esc "$author")'"
[[ -n "$cwd" ]] && where="$where and cwd like '$(esc "${cwd/#\~/$HOME}")%'"
if [[ -n "$since" ]]; then
  epoch=$(date -d "$since" +%s 2>/dev/null) || { echo "日付を解釈できません: $since" >&2; exit 1; }
  where="$where and timestamp >= ${epoch}000000000"
fi

if [[ "$count_only" -eq 1 ]]; then
  "$SQLITE3" "$ARCHIVE_DB" "select count(*) from history where $where;"
  exit 0
fi

if [[ "$json" -eq 1 ]]; then
  exec "$SQLITE3" -json "$ARCHIVE_DB" "select
      strftime('%Y-%m-%d %H:%M:%S', timestamp/1000000000, 'unixepoch', 'localtime') as at,
      author, cwd, exit, command
    from history where $where order by timestamp desc limit $limit;"
fi

exec "$SQLITE3" -separator $'\t' "$ARCHIVE_DB" "select
    strftime('%Y-%m-%d %H:%M', timestamp/1000000000, 'unixepoch', 'localtime'),
    coalesce(author, '-'), cwd, command
  from history where $where order by timestamp desc limit $limit;"
