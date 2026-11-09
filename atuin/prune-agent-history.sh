#!/usr/bin/env bash
# atuin 履歴の定期剪定 (週次 cron 想定)。
#
# やること:
#   1. エージェント (claude-code / pi …) が記録した行を KEEP_AGENT_DAYS 日より古い分だけ削除
#   2. 自分の履歴の重複 (同一 command + cwd + hostname) を最新 1 件だけ残して削除
#   3. 削除で空いた領域を VACUUM で返す
#
# きっかけ: claude-code の atuin hook が 7 か月で 18 万行 (530MB) を積み、
# atuin の fuzzy 検索が全行ロードになって 1 回 350ms かかっていた。
# atuin は TUI でエージェント行を非表示にするが、読み込み自体は全行なので
# DB から物理的に消すのが効く (実測 356ms → 16ms)。
#
# 実行: bash atuin/prune-agent-history.sh        (KEEP_AGENT_DAYS=30 で期間変更)
set -euo pipefail

DATA_DIR="${ATUIN_DATA_DIR:-$HOME/.local/share/atuin}"
DB="$DATA_DIR/history.db"
KEEP_AGENT_DAYS="${KEEP_AGENT_DAYS:-7}"

# atuin が記録するエージェント名 (atuin-client の KNOWN_AGENTS に合わせる)
AGENTS="'claude-code','codex','copilot','pi','grok','kiro','opencode'"
# timestamp 列はナノ秒 (atuin 18)

[[ -f "$DB" ]] || exit 0

# cron の PATH には linuxbrew が入らないので sqlite3 を明示的に解決する
SQLITE3="${SQLITE3:-$(command -v sqlite3 || true)}"
if [ -z "$SQLITE3" ]; then
  for candidate in /home/linuxbrew/.linuxbrew/bin/sqlite3 /usr/bin/sqlite3; do
    if [ -x "$candidate" ]; then
      SQLITE3="$candidate"
      break
    fi
  done
fi
if [ -z "$SQLITE3" ]; then
  echo "prune-agent-history: sqlite3 が見つかりません" >&2
  exit 0
fi

# 実行中に VACUUM がロック待ちで詰まらないよう、まず待機時間を設定する
"$SQLITE3" "$DB" "pragma busy_timeout = 30000;" >/dev/null

before=$("$SQLITE3" "$DB" "select count(*) from history;")

# 1. 古いエージェント行を削除 (直近分は `atuin search --author \$all-agent` 用に残す)
"$SQLITE3" "$DB" "delete from history
  where author in ($AGENTS)
    and timestamp < (strftime('%s', 'now') - $KEEP_AGENT_DAYS * 86400) * 1000000000;"

# 2. 自分の履歴の重複を最新 1 件に畳む (atuin history dedup --dupkeep 1 と同等)
"$SQLITE3" "$DB" "delete from history where rowid not in (
  select rowid from (
    select rowid,
           row_number() over (partition by command, cwd, hostname order by timestamp desc) rn
    from history
  ) where rn <= 1);"

# 3. 空きページが十分あるときだけ VACUUM (毎回やるほどではない)
freelist=$("$SQLITE3" "$DB" "pragma freelist_count;")
if [ "$freelist" -gt 100 ]; then
  "$SQLITE3" "$DB" "vacuum;"
  "$SQLITE3" "$DB" "pragma wal_checkpoint(truncate);"
fi

after=$("$SQLITE3" "$DB" "select count(*) from history;")
size=$(du -h "$DB" | cut -f1)
printf '%s history prune: %s -> %s rows, %s\n' \
  "$(TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S %Z')" "$before" "$after" "$size"
