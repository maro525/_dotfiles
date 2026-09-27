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
ファイル数が閾値を超えた／未解決の設計問題が積み上がった／新依存を追加した／リスク次元が変わった（例: 想定外に認証コードに触れた）場合は tier を引き上げる。完了済みの作業はやり直さない。
`/orchestrate` 内では team-implement が中断して `ESCALATION` を返し、orchestrate が tier を更新して startproject（計画）からやり直す。それまでのコード変更は作業ブランチに残し、やり直さずに続きから進める。

## ROUTING NOTES

- Linear MCP は各フェーズ内で直接実行
- 外部リサーチは firecrawl MCP（`firecrawl_search` → 詳細は `firecrawl_scrape`）
- 設計相談は OpenCode 自身で対応するか、`task` tool（subagent）で並列起動

## GIT RULES

- **書き込み系**（add / commit / push / pull / merge / rebase / cherry-pick / tag 作成 / stash push・pop・apply / reset / revert / branch 作成 / checkout / switch）は `/deploy`（`--task-file` なし = Ad-hoc Git モード）経由で実行する。フェーズ agent（`team-implement` / `team-review` / `deploy`）の内部では直接実行してよい
- **読み取り系**（status / log / diff / show / blame / branch 一覧 / fetch / stash list・show / rev-parse / config --get）は直接実行してよい
- **保護ブランチ `release` / `staging` / `main`（master 含む）への直接コミット・push は、ユーザーの明示的な許可がない限り禁止**。反映は必ず PR / MR 経由。保護ブランチ上で書き込み操作が必要になったら feature ブランチを作成してから実行する（tier=XS も同様）
- ホスティング CLI: `origin` のリモート URL で判定し、GitLab（セルフホスト含む）は `glab`、GitHub は `gh` を使う。GitHub MCP は不安定なため使わない

## OpenCode 仕様メモ

- 配置先: `~/.config/opencode/` 配下（`AGENTS.md` / `agents/` / `commands/` / `skills/`）
- **自動スキル提案なし**: UserPromptSubmit hook 相当が無いため、`/orchestrate` などスキルは明示呼び出し必須
- **スキル間連鎖**: `@agent-name` mention で起動。コマンド同士の直接呼び出しは不可
- **サブエージェント起動**: `task` tool を使用
- **`context: fork` 代替**: `mode: subagent` + `subtask: true`（親子間のトークン共有挙動は若干異なる）
