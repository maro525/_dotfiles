# OpenCode Global Instructions

Claude Code + OpenCode CLI + Gemini CLI で並列開発を加速する。

## DOCUMENTATION STRUCTURE

| Path | Purpose |
|------|---------|
| `.opencode/commands/` | orchestrate / startproject / team-implement / team-review / deploy |
| `.opencode/agents/`   | 各フェーズ用 subagent 定義 |
| `.claude/docs/decisions/task-{LINEAR_ID}-{feature}.md` | 統合タスクファイル (SSoT) |
| `.claude/docs/libraries/` | ライブラリ制約 |
| `.claude/logs/` | CLI 入出力ログ |

Claude Code と同じ `.claude/docs/` ツリーを共有する（両ツールで同じタスクファイルを参照）。

## WORKFLOW COMMON RULES

**記録ステップ (MUST):** MUST マーク付きステップは全 tier・全モードでスキップ不可。

## LANGUAGE PROTOCOL

思考・コード: 英語 / ユーザー対話: 日本語

## ADAPTIVE EXECUTION

タスクサイズに応じてフェーズを適応させる:

| Tier | 判定基準 | startproject | team-implement | team-review |
|------|---------|--------------|----------------|-------------|
| XS   | 1ファイル・ロジック変更なし | スキップ | 直接実装 | スキップ |
| S    | 1-3ファイル・単一パターン | 簡易計画 | 直接実装 | self-review |
| M    | 4-10ファイル・複数パターン | 設計相談あり | 1-2 subagent | 2レビュアー |
| L    | 10+ファイル・アーキ変更 | Researcher+Architect 並列 | フルチーム | 4レビュアー |

**Hard Triggers（自動 L）:** 認証・DB migration・支払い・公開API変更・新規コア依存追加。

## ROUTING NOTES

- Git / Linear MCP は各フェーズ内で直接実行（Claude Code 版の `context: fork` 相当）
- 外部リサーチは Gemini CLI（`gemini -p "..." 2>/dev/null`）
- 設計相談は OpenCode CLI 自身が対応するか、並列セッションを起動
