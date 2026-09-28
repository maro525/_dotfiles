# Tool Routing Rules

**どの操作をどのツール・エージェントに委譲するかを定める。**
外部リサーチは firecrawl MCP + OpenCode の二系統、設計相談は OpenCode に振り分ける。使うかどうか自体は tier で決まる（`$HOME/.claude/rules/adaptive-execution.md` の「External Research」「OpenCode Design Consultation」）。本ファイルは「使う」となった場合の委譲先を定める。

## Skill Routing hook への応答

`agent-router.py`（UserPromptSubmit hook）が `[Skill Routing]` / `[Agent Routing]` を additionalContext に出す。ソフトな推奨として扱う。

- **従う**: プロンプトの意図と一致し、ユーザーの明示指示と矛盾しないとき。従う旨を一言伝えて起動する（`[Skill Routing]` は Skill ツール、`[Agent Routing]` は提案されたサブエージェント / OpenCode）
- **従わなくてよい**: ユーザーが別のことを明示している／提案スキルに対してタスクが小さすぎる（XS など）／進行中ワークフロー内の追加質問
- 提案がずれていると思ったら、理由を伝えてユーザーに確認する

## Routing Table

| Operation | Delegate To | Method |
|-----------|-------------|--------|
| External research | **firecrawl MCP + OpenCode** | 二系統を並列実行し Claude が統合（下記） |
| 記事 (URL 1 本) | **WebFetch** | 読めないページは firecrawl（`firecrawl_scrape`） |
| PDF (URL) / 複数ページ | **firecrawl MCP** | `firecrawl_parse` / `firecrawl_scrape` |
| 音声・動画 | **未対応** | 委託先なし。ユーザーに扱い方を確認する |
| Library research | **firecrawl MCP + OpenCode** | `firecrawl_search` で一次情報 + OpenCode で実装知見 |
| Design decisions | **OpenCode** | Subagent（`timeout -k 1m 20m opencode run --agent plan -m github-copilot/gpt-5.6-sol`） |
| git（書き込み系） | **`/deploy` skill** | Ad-hoc Git モード。読み取り系は Claude が直接 |
| `/orchestrate` で作った PR への追加変更 | **`/orchestrate` 追加修正モード** | `/orchestrate "{追加の依頼} --task-file={TASK_FILE}"`。直接編集して Ad-hoc push しない（下記「Git Operations」） |
| フェーズを別 AI で実行（別案・別視点レビューなど） | **`/orchestrate` フェーズ指定モード** | `/orchestrate "--task-file={TASK_FILE} --phase={phase} --ai={pi\|cline\|opencode\|codex}[:{model}]"`。外部 CLI に `~/.agents/skills/{phase}/SKILL.md` を読ませる（下記「外部 CLI のフェーズ実行」） |
| docker/ruff/uv (in `context: fork` skills) | **Direct** | スキル内で直接実行 |
| docker/ruff/uv (ad-hoc) | **Subagent** | サブエージェント内で実行 |
| Linear MCP | **Direct or Subagent** | スキル内は直接、アドホックはサブエージェント |
| GitHub 操作 | **`gh` CLI** | GitHub MCP は不安定なため使わない |

## External Research via firecrawl MCP + OpenCode

二系統を **並列実行**し、Claude が突き合わせて統合する。

| 系統 | ツール | 得意分野 |
|------|-------|---------|
| **一次情報** | firecrawl MCP | 公式ドキュメント・リリースノートの実文面。出典 URL が取れるが解釈はしない |
| **実装知見** | OpenCode CLI | 設計上の勘所・落とし穴・比較。解釈は出せるが出典を持たない |

食い違ったら **firecrawl の一次情報を優先**し、相違点と採用した方を成果物に記録する（`/startproject` では OUTPUT の `DESIGN`）。

### OpenCode リサーチの実行

**これが唯一動く呼び出し形。他のファイルはこの節を参照する。**

```bash
timeout -k 1m 20m opencode run --agent plan -m github-copilot/gpt-5.6-sol "{research question}" < /dev/null
```

| 要素 | 外すと壊れる理由 |
|------|-----------------|
| `--agent plan` **必須** | 既定の `build` は非対話実行だとパーミッション確認で**無言ハング**する。stderr にも何も出ない |
| `< /dev/null` **必須** | stdin が**開いたパイプ**だと永久にハングする。`run_in_background: true` がまさにその状態（フォアグラウンドには自動で付くがバックグラウンドには付かない）。**バックグラウンド実行と必ずセット** |
| `2>/dev/null` を**付けない** | エラーを stderr に出しつつ **exit code 0** で終わる。潰すと「成功したのに出力が空」に見える |
| モデルは `github-copilot/gpt-5.6-sol` | `openai/gpt-5.6-sol` は残高切れ（`insufficient_quota`）で**必ず失敗する**。課金が復活したら第一候補に戻す |
| **バックグラウンド実行必須** | 込み入った質問は 10 分超。Bash ツールの既定 10 分で kill されると出力ゼロになり、ハングと見分けがつかない |
| `timeout -k 1m 20m` **必須** | 失敗後にプロセスが終わらないことがある（429 の後に MCP の認証待ちで止まり、完了通知が来ないまま待ち続けた）。`-k 1m` は SIGTERM で終わらないとき 1 分後に SIGKILL する。exit code 124（SIGTERM）/ 137（SIGKILL）はどちらも「OpenCode 不可: タイムアウト」として扱う |
| cwd は **git リポジトリ** | 非 git ディレクトリ（`/tmp` 等）だと起動時の `service=vcs` 初期化で無言ハングする |

- **完了はバックグラウンドタスクの完了通知で待つ。** `pgrep` / `tail --pid` で自前監視しない（`pgrep -f` は監視コマンド自身にマッチし、タイムアウトまで待ち続ける）
- **モデルは上記で固定。** 失敗しても差し替えない
- **呼べないときは諦めて先に進む。** quota / 429 / 認証エラー / タイムアウトなどで失敗したら、再試行もモデル変更もせず OpenCode なしで続け、成果物（Design・レビュー結果など）に「OpenCode 不可: {理由}」と書く
- 長文プロンプトはファイルに落として `"$(cat prompt.txt)"` で渡す
- ツール呼び出しで止まらせたくなければ、プロンプト冒頭に `DO NOT USE ANY TOOLS`
- 空出力を quota と決めつけず、ログ（`~/.local/share/opencode/log/`、1 セッション 1 ファイル）で確認する。正常なら `service=session` → `POST /session` → `service=snapshot` → `resolveTools` → `service=llm … stream` と進む。**`service=vcs … initialized` で止まっていれば stdin 詰まり**（`< /dev/null` 忘れ）で、非 git cwd と同じ見た目になる
- 疎通確認: `opencode run --agent plan -m <model> "Reply with exactly: PONG"`（数十秒で返る）
- `context: fork` の command 内と `/startproject` は直接実行。それ以外はサブエージェント経由でメインコンテキストを汚さない
- OpenCode はコードを読まずに答えることがある。結論は採用してよいが**根拠は必ず自分で検証する**

### Scope

ライブラリ・フレームワークの最新仕様と公式ドキュメント／リリースノート・変更履歴・非推奨情報／既知の不具合・脆弱性・回避策／実装事例・ベンチマーク・比較記事

### Tools（firecrawl 系統）

| Tool | 用途 |
|------|------|
| `firecrawl_search` | Web 検索（本文抽出込み）。まずこれを使う |
| `firecrawl_scrape` | URL が判明しているページを Markdown で取得 |
| `firecrawl_map` | サイト内の URL 一覧を取得（ドキュメントサイトの探索） |
| `firecrawl_extract` | 複数ページから構造化データを抽出 |
| `firecrawl_parse` | PDF など URL 上のドキュメントをパース |

### How to Route

Agent ツールで 2 つのサブエージェント（`subagent_type: general-purpose`、`run_in_background: true`）を**同時に起動**する（片方の結果を待たない）。

```
# 系統 1: 一次情報
Research the following using the firecrawl MCP tools: {topic}
Start with firecrawl_search, then firecrawl_scrape the authoritative sources
(official docs / release notes). Cite the source URL for every claim.
Save full output to: .claude/docs/research/{topic}-sources.md
Return CONCISE summary.

# 系統 2: 実装知見
Run OpenCode research on: {topic}
timeout -k 1m 20m opencode run --agent plan -m github-copilot/gpt-5.6-sol "{research question}" < /dev/null
Keep `--agent plan` and `< /dev/null`, do NOT append 2>/dev/null — see
"OpenCode リサーチの実行" in $HOME/.claude/rules/tool-routing.md. Expect over 10 minutes.
Save full output to: .claude/docs/research/{topic}-opencode.md
Return CONCISE summary, and flag anything you are NOT confident about
so it can be checked against the firecrawl sources.
```

両者の結果を Claude が統合する（食い違いは firecrawl 優先）。

### Triggers

| User Input | Action |
|------------|--------|
| 「調べて」「リサーチして」「最新バージョンは」「使い方を調べて」 | firecrawl + OpenCode を並列実行 |
| 「公式ドキュメントを見て」「仕様を確認して」 | firecrawl 主体（OpenCode は任意） |
| 「既知の不具合はある?」「脆弱性を確認して」 | firecrawl + OpenCode を並列実行 |

バージョン番号など「現在の事実」は firecrawl の結果を正とする。

### Exceptions (Claude handles directly)

- URL が 1 本だけ分かっていて要約するだけ（WebFetch で足りる）

## 外部 CLI のフェーズ実行

`/orchestrate` のフェーズ指定モード（orchestrate.md「STEP 3P」）が、既存 TASK_FILE の 1 フェーズを外部 CLI に実行させるときの呼び出し表。対象 CLI は **pi / cline / opencode / codex**（Claude の別モデルは対象外。`context: fork` の command は frontmatter の `model` が優先され `--model` で変えられない）。読ませる定義は一般向けフェーズ定義 `~/.agents/skills/{phase}/SKILL.md`（dotfiles の `agents/skills/`、配布は `sync-agents.sh`）。

**CLI の起動オプションはこの表が唯一の定義。** `agents/README.md` は起動例を持たず、この表を参照する。

### 呼び出し表

**全フェーズ同じ起動オプションで動かす（読み取り専用にしない）。** startproject / team-review も team-implement / deploy と同じく、確認なしで編集・コマンド実行を許す指定で起動する（Gate 1 / Gate 2 でユーザー了承済み。理由は下の「権限」）。`{prompt}` は orchestrate が作ったプロンプトファイルの中身（`"$(cat {prompt_file})"`）、`{repo}` は対象リポジトリの絶対パス、`{last}` は `{log_file}` と同じ場所の `.last.md`。

| ai | 起動（全フェーズ共通） | モデル指定（`--ai={ai}:{model}`） |
|---|---|---|
| `pi` | `pi -p --no-session "{prompt}"` | `--model {model}`（`provider/id` 形式可） |
| `cline` | `cline --json --auto-approve true -t 1800 "{prompt}"` | `-m {model}`（provider は cline の設定値。変えるなら `-P {provider}` を併記） |
| `opencode` | `opencode run --agent build --dangerously-skip-permissions "{prompt}"` | `-m {provider/model}` |
| `codex` | `codex exec -s workspace-write -c 'sandbox_workspace_write.writable_roots=["{repo}/.git"]' -o {last} "{prompt}"`。deploy は push のため `-c 'sandbox_workspace_write.network_access=true'` を加える | `-m {model}` |

- モデル名は**変換せずそのまま**渡す（各 CLI で通る名前をユーザーが指定する）
- **codex に `-s danger-full-access` は使わない。** `workspace-write` は writable root 配下の `.git` を読み取り専用にするため、`git checkout -b` / `git commit` が失敗する。`.git` を `writable_roots` に足せば足り、deploy の push は `network_access=true` で通る（キー名は codex の config reference `sandbox_workspace_write.writable_roots` / `.network_access`）。codex を更新したら `codex exec --help` と config reference でキー名が生きているか確認する
- codex の最終メッセージは `-o {last}`（`--output-last-message`）でファイルに取る。stdout のイベントログから拾わない
- cline の `--json` は 1 行 1 JSON のストリーム（`text` はエスケープ済み）。最終メッセージは `"type":"run_result"` 行の `text`（下記「最終メッセージの取り出し」）
- どのフェーズも CLI が TASK_FILE に直接書く（`written: yes`）。サンドボックス等で書けなかったとき（`written: no`）だけ orchestrate が `### SECTION` から代筆する（STEP 3P P4）。startproject / team-review では起動前後で作業ツリー・HEAD・ref・stash を比べ、TASK_FILE 以外に変化があれば報告する（P5）
- codex 0.80.0 は ChatGPT アカウントで使えるモデルが無く全モデル失敗する（2026-09-28 実測）。`npm i -g @openai/codex@latest` で更新してから使う（`agents/README.md`）
- opencode は quota 切れ（429）だと無出力に見える。ログの 429 を先に確認する（「OpenCode リサーチの実行」）

### 権限

agents（一般向けフェーズ定義）では**全フェーズ同じ権限で動く。読み取り専用にしない**（Gate 2 のユーザー判断、2026-09-29）。理由: 読み取りフェーズだけ絞っても、各 CLI の「読み取り専用」は実態と一致しなかった（pi の `bash` は `~/.pi/agent/extensions/permissions/` の許可リストで `git push` / `python3` まで通り、opencode の許可リストにはサブエージェント起動などの抜け道が残った）うえ、絞ると `date` / `git` / テストが使えず orchestrate 側の代筆・差分渡し・検知の手順が肥大した。

- startproject / team-review が TASK_FILE 以外を変更しないのは **SKILL.md の指示**によるもので、起動オプションでは強制しない。orchestrate は起動前後の簡単な比較で TASK_FILE 以外の変化を報告する（STEP 3P P5）
- リポジトリ内の文章に仕込まれた指示に従う危険はどのフェーズにもある。信頼できないリポジトリでは使わない

### 最終メッセージの取り出し（STEP 3P P4）

**この表が唯一の定義。** orchestrate.md P4 はここを参照する。

| ai | 最終メッセージ |
|---|---|
| `pi` / `opencode` | `{log_file}` の末尾（プレーンテキスト） |
| `codex` | `{last}`（`-o` で書かせたファイル） |
| `cline` | `grep '"type":"run_result"' {log_file} \| tail -n 1 \| jq -r .text`（`jq` が無ければ `python3 -c 'import sys,json; print(json.loads(sys.stdin.readline())["text"])'`） |

取り出したテキストから `### SECTION` 以下を切り出す: `awk '/^### SECTION/{f=1;next} f'`（`### RESULT` は追記しない）。

### 共通則

| 要素 | 理由 |
|---|---|
| `< /dev/null` **必須** | stdin が開いたパイプだと pi / opencode / codex はハングする（codex はプロンプト未指定時に stdin を読む） |
| `timeout -k 1m 30m` | 実装フェーズは 10 分を超える。Bash の既定 10 分では kill されて出力ゼロになる |
| **バックグラウンド実行必須** | 同上。完了通知で待ち、`pgrep` やログ先読みで完了を推測しない |
| `2>/dev/null` を**付けない** | エラーが stderr に出て exit 0 で終わる CLI がある。`> {log} 2>&1` で両方を残す |
| cwd は対象リポジトリ | 各 CLI は cwd からリポジトリの指示ファイル・スキルを探す。非 git ディレクトリではハングする CLI がある（opencode） |
| ログは `.claude/logs/phase-{phase}-{ai}-{日時}.log` | プロンプトも同じ場所に `.prompt.txt`、codex の最終メッセージは `.last.md` で残す（`.claude/` は gitignore 済み） |

```bash
timeout -k 1m 30m {上表のコマンド} "$(cat {prompt_file})" < /dev/null > {log_file} 2>&1
```

失敗判定は orchestrate 側（exit ≠ 0 / 124・137 / 節も `### SECTION` も無い）。再試行・モデル差し替えは自動では行わず、ユーザーに報告する。

## Git Operations

**書き込み系は `/deploy`（Ad-hoc Git モード）経由、読み取り系は Claude が直接実行してよい。**

| 分類 | コマンド | 実行者 |
|------|---------|--------|
| **書き込み** | `add`, `commit`, `push`, `pull`, `merge`, `rebase`, `cherry-pick`, `tag`（作成）, `stash`（push/pop/apply）, `reset`, `revert`, `branch`（作成）, `checkout`, `switch` | `/deploy` |
| **読み取り** | `status`, `log`, `diff`, `show`, `blame`, `branch`（一覧）, `fetch`, `stash list/show`, `rev-parse`, `config --get` | Claude が直接 |

`/team-implement` `/team-review` `/deploy` の fork 内では、書き込み系も直接実行する。

### /orchestrate で作った PR への追加変更

**`/orchestrate` が PR / MR を出したブランチへのコードの追加変更は、必ず `/orchestrate` の追加修正モード（orchestrate.md「STEP 3F: 追加修正モード」）で行い、team-implement → team-review → deploy を通す。**

- 判定基準: 対象ブランチが TASK_FILE（`.claude/docs/decisions/task-*.md`）の `## Meta` `branch:` に一致し、その `## deploy` に PR / MR URL がある
- 禁止: orchestrator やメインセッションがファイルを直接編集して `/deploy`（Ad-hoc Git モード）で commit / push すること。レビューを通らない変更が PR に載る（実例: `task-NOLINEAR-claude_config_simplify` の 2回目は後追いレビューで major が見つかり取り消しになった）
- 呼び出し形: `/orchestrate "{追加の依頼} --task-file={TASK_FILE}"`（または `/orchestrate "{LINEAR_ID} {追加の依頼}"`）
- `/deploy` の Ad-hoc Git モードは対象ブランチを検出したら実行せず、追加修正モードを案内して確認する（deploy.md「/orchestrate 由来の PR ブランチへのガード」）
- 例外（追加修正モードを通さなくてよい）: コードを変えない操作 — PR / MR の本文・タイトル修正、ラベル・レビュアー設定、読み取り系 git、マージ済み PR のブランチ削除。ユーザーが承知のうえで Ad-hoc 実行を明示した場合も実行するが、レビューを通っていない旨を報告する

### 保護ブランチ

- **`release` / `staging` / `main`（master 含む）への直接コミット・push は、ユーザーの明示的な許可がない限り禁止。** 反映は必ず PR / MR 経由
- 保護ブランチ上で書き込み操作が必要になったら、feature ブランチを作成してから実行する（tier=XS も同様）

### ホスティング CLI

`origin` のリモート URL で判定し、GitLab（セルフホスト含む）は `glab`、GitHub は `gh` を使う。GitHub MCP は不安定なため使わない。

## Linear MCP Operations

スキル外での MCP 操作はサブエージェント（Agent ツール、`general-purpose`）経由で実行する。

```
Perform the following MCP operation.
Task: {description}
Use Linear MCP tools directly.
Report results back concisely in Japanese.
```

### Linear Triggers

| User Input | Action |
|------------|--------|
| 「Linearにissue作って」「チケットを更新して」「タスクのステータスを変えて」 | サブエージェント経由で実行 |

## Operational Commands (Subagent Routing)

以下はアドホック実行時、コンテキスト分離のためサブエージェント（Agent ツール、`general-purpose`）経由で実行する。`context: fork` スキル内では直接実行する。

```
Task: {description}
Execute the commands directly and report results concisely.
```

| 操作 | コマンド例 | Triggers |
|------|-----------|----------|
| **依存管理** | `uv add/remove/sync` | 「パッケージを更新して」「依存を追加して」 |
| **Lint/Format** | `ruff check .`, `ruff format .` | 「lintして」「フォーマットして」 |
| **Docker** | `docker build/run`, `docker compose` | 「コンテナを起動して」「docker build して」 |
| **環境セットアップ** | `uv sync`, version checks | 「環境セットアップして」「バージョン確認して」 |
| **ファイル整理** | bulk rename, directory restructure | 「ファイルを整理して」「リネームして」 |
| **シェルスクリプト** | Bash script creation | 「スクリプト書いて」「自動化して」 |
| **Changelog** | `git log` → formatted notes | 「changelog作って」「リリースノート生成して」 |

### 例外（Claude が直接実行してよい操作）

- ファイル内容の編集（Edit/Write ツール）
- 新規ソースコード作成（Claude の領域）
