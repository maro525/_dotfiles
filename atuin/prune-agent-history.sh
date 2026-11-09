#!/usr/bin/env bash
# atuin 履歴の定期剪定 (週次 cron 想定)。
#
# やること:
#   1. エージェント (claude-code / pi …) が記録した行を history.db から
#      archive/agent-history.db へ「移送」する (削除ではなく退避)
#   2. 自分の履歴の重複 (同一 command + cwd + hostname) を最新 1 件だけ残して削除
#   3. 削除で空いた領域を VACUUM で返す
#
# なぜ消すのか (atuin 18.15 実測):
#   atuin の fuzzy 検索は `where command like '%g%i%t%'` = 全行スキャンで、
#   TUI が付ける author フィルタ ($all-user) は同じクエリ内で評価されるだけ。
#   つまりエージェント行が history.db にある限り 1 検索 350ms かかる。
#   行を別 DB に移すと 16ms になる (192,725 行 / 531MB → 2,989 行 / 1.2MB)。
#
# 移送先の検索は atuin/agent-history.sh を使う (atuin 本体は触らない)。
#
# 実行:
#   bash atuin/prune-agent-history.sh                 # エージェント行は全件移送
#   KEEP_AGENT_DAYS=7 bash atuin/prune-agent-history.sh  # 直近 7 日は history.db に残す
set -euo pipefail

DATA_DIR="${ATUIN_DATA_DIR:-$HOME/.local/share/atuin}"
DB="$DATA_DIR/history.db"
ARCHIVE_DB="${AGENT_ARCHIVE_DB:-$DATA_DIR/archive/agent-history.db}"
KEEP_AGENT_DAYS="${KEEP_AGENT_DAYS:-0}"

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
mkdir -p "$(dirname "$ARCHIVE_DB")"

# 1. エージェント行を archive 側へ移送 (同一トランザクション)
CUTOFF="(strftime('%s', 'now') - $KEEP_AGENT_DAYS * 86400) * 1000000000"
"$SQLITE3" "$DB" <<SQL >/dev/null
attach database '$ARCHIVE_DB' as archive;
create table if not exists archive.history (
  id text primary key,
  timestamp integer not null,
  duration integer not null,
  exit integer not null,
  command text not null,
  cwd text not null,
  session text not null,
  hostname text not null,
  deleted_at integer,
  author text,
  intent text
);
create index if not exists archive.idx_archive_timestamp on history(timestamp);
create index if not exists archive.idx_archive_author on history(author);

begin;
insert or ignore into archive.history
  (id, timestamp, duration, exit, command, cwd, session, hostname, deleted_at, author, intent)
select id, timestamp, duration, exit, command, cwd, session, hostname, deleted_at, author, intent
  from main.history
 where author in ($AGENTS)
   and timestamp < $CUTOFF;
delete from main.history
 where author in ($AGENTS)
   and timestamp < $CUTOFF;
commit;

pragma main.wal_checkpoint(truncate);
detach database archive;
SQL

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
archived=$("$SQLITE3" "$ARCHIVE_DB" "select count(*) from history;")
size=$(du -h "$DB" | cut -f1)
archsize=$(du -h "$ARCHIVE_DB" | cut -f1)
printf '%s history prune: %s -> %s rows (%s), archive: %s rows (%s)\n' \
  "$(TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S %Z')" "$before" "$after" "$size" "$archived" "$archsize"
