# OpenCode Agent Instructions

OpenCode CLI で開発を加速するためのエージェント仕様（外部リサーチは firecrawl MCP を併用）。

## DOCUMENTATION STRUCTURE

| Path | Purpose |
|------|---------|
| `.opencode/commands/` | orchestrate / startproject / team-implement / team-review / deploy |
| `.opencode/agents/` | 各フェーズ用 subagent 定義 |
| `.claude/docs/decisions/task-{LINEAR_ID}-{feature}.md` | 統合タスクファイル (SSoT) — 全 CLI で共有 |
| `.claude/docs/libraries/` | ライブラリ制約 |
| `.claude/logs/` | CLI 入出力ログ |

`.claude/docs/` ツリーは全 CLI で共有する（同じタスクファイルを参照）。

## LANGUAGE PROTOCOL

思考・コード: 英語 / ユーザー対話: 日本語

## ADAPTIVE EXECUTION

tier は以下で判定する（`tier = max(file_tier, complexity_tier, risk_tier)`）:

| Tier | Files | Complexity | Risk |
|------|-------|-----------|------|
| XS   | 1 | ロジック変更なし | なし |
| S    | 1-3 | 単一パターン | 低 |
| M    | 4-10 | 複数パターン | 中 |
| L    | 10+ | アーキテクチャ変更 | 高 |

**Hard Triggers（自動 L）:** 認証・DB migration・支払い・公開API変更・新規コア依存追加。

各フェーズの tier 別の体制は各 agent（`startproject` / `team-implement` / `team-review`）に定義する。XS は `/orchestrate` を使わず直接実装する。

**エスカレーション（上方向のみ）:** 計画後・実装 30-40% 時点・レビュー前に tier を再評価する。
ファイル数が閾値を超えた／未解決の設計問題が積み上がった／新依存を追加した／リスク次元が変わった（例: 想定外に認証コードに触れた）場合は tier を引き上げる。
`/orchestrate` 内では team-implement が中断して `ESCALATION` を返し、orchestrate が tier を更新して startproject（計画）からやり直す。完了済みの作業はやり直さず、それまでのコード変更は作業ブランチに残して続きから進める。

## ROUTING NOTES

- Linear MCP は各フェーズ内で直接実行
- 外部リサーチは firecrawl MCP（`firecrawl_search` → 詳細は `firecrawl_scrape`）
- 記事（URL 1 本）は `webfetch` tool。読めないページは `firecrawl_scrape`
- PDF（URL）・複数ページは firecrawl MCP（`firecrawl_parse` / `firecrawl_scrape`）
- 音声・動画は委託先なし。ユーザーに扱い方を確認する
- GitHub 操作は `gh` CLI のみ（GitHub MCP は不安定なため使わない）
- 設計相談・Second Opinion は `task` tool（subagent、別コンテキスト）。失敗時の扱いは「OpenCode 仕様メモ」

## GIT RULES

- **書き込み系**（add / commit / push / pull / merge / rebase / cherry-pick / tag 作成 / stash push・pop・apply / reset / revert / branch 作成 / checkout / switch）は `/deploy`（`--task-file` なし = Ad-hoc Git モード）経由で実行する。フェーズ agent（`team-implement` / `team-review` / `deploy`）の内部では直接実行してよい
- **読み取り系**（status / log / diff / show / blame / branch 一覧 / fetch / stash list・show / rev-parse / config --get）は直接実行してよい
- **保護ブランチ `release` / `staging` / `main`（master 含む）への直接コミット・push は、ユーザーの明示的な許可がない限り禁止**。反映は必ず PR / MR 経由。保護ブランチ上で書き込み操作が必要になったら feature ブランチを作成してから実行する（tier=XS も同様）
- ホスティング CLI: `origin` のリモート URL で判定し、GitLab（セルフホスト含む）は `glab`、GitHub は `gh` を使う。GitHub MCP は不安定なため使わない
- **`/orchestrate` で作った PR への追加変更**: `/orchestrate` が PR / MR を出したブランチへのコードの追加変更は、必ず `/orchestrate` の追加修正モード（`commands/orchestrate.md`「STEP 3F: 追加修正モード」）で行い、team-implement → team-review → deploy を通す
  - 判定基準: 対象ブランチが TASK_FILE（`.claude/docs/decisions/task-*.md`）の `## Meta` `branch:` に一致し、その `## deploy` に PR / MR URL がある
  - 禁止: orchestrator やメインセッションがファイルを直接編集して `/deploy`（Ad-hoc Git モード）で commit / push すること。レビューを通らない変更が PR に載る
  - 呼び出し形: `/orchestrate "{追加の依頼} --task-file={TASK_FILE}"`（または `/orchestrate "{LINEAR_ID} {追加の依頼}"`）
  - `/deploy` の Ad-hoc Git モードは対象ブランチを検出したら実行せず、追加修正モードを案内して確認する（`agents/deploy.md`「/orchestrate 由来の PR ブランチへのガード」）
  - 例外（追加修正モードを通さなくてよい）: コードを変えない操作 — PR / MR の本文・タイトル修正、ラベル・レビュアー設定、読み取り系 git、マージ済み PR のブランチ削除。ユーザーが承知のうえで Ad-hoc 実行を明示した場合も実行するが、レビューを通っていない旨を報告する

## OpenCode 仕様メモ

- 配置先: `~/.config/opencode/` 配下（`AGENTS.md` / `agents/` / `commands/` / `skills/`）
- **自動スキル提案なし**: UserPromptSubmit hook 相当が無いため、`/orchestrate` などスキルは明示呼び出し必須
- **スキル間連鎖**: `@agent-name` mention で起動。コマンド同士の直接呼び出しは不可
- **サブエージェント起動**: `task` tool を使用。**`task` は同期**（返却を受け取るまで呼び出し側は進まない）なので、完了通知・timeout・プロセス監視は不要
- **subagent が失敗したとき**（Second Opinion・設計相談など補助的な起動がエラー・空返却で終わった）: 再試行もモデル差し替えもせず飛ばして続け、成果物に「Second Opinion 不可: {理由}」（startproject は「設計相談不可: {理由}」）と書く。フェーズ agent（`@startproject` など）自体の失敗は orchestrate がユーザーに報告する
- **ユーザーへの質問**: `question` tool。subagent 内からユーザーに届くかは実機未検証
- **URL の取得**: `webfetch` tool（Claude Code 版との対応は `README.md` の Portability Notes）
- **`context: fork` 代替**: `mode: subagent` + `subtask: true`（親子間のトークン共有挙動は若干異なる）
