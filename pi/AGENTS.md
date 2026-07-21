# pi Agent Instructions

pi CLI + OpenCode CLI で並列開発を加速するためのエージェント仕様。OpenCode は pi のデフォルトモデルと異なる `openai/gpt-5.6-sol-pro` を使うため、設計相談で異モデルセカンドオピニオンとして機能する。

## DOCUMENTATION STRUCTURE

| Path | Purpose |
|------|---------|
| `pi/skills/` | orchestrate / startproject / team-implement / team-review / deploy |
| `pi/agents/` | 各フェーズ用 subagent 定義 |
| `.claude/docs/decisions/task-{LINEAR_ID}-{feature}.md` | 統合タスクファイル (SSoT) — 全 CLI で共有 |
| `.claude/docs/libraries/` | ライブラリ制約 |
| `.claude/logs/` | CLI 入出力ログ |

`.claude/docs/` ツリーは全 CLI で共有する（同じタスクファイルを参照）。

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

- Git 操作: `bash` ツールで直接実行
- Linear 連携: MCP または `gh` CLI で代替
- 外部リサーチは `web_search` / `web_fetch` ツール（`@ollama/pi-web-search` パッケージ）。pi は MCP 非対応のため、Claude Code 側の firecrawl MCP に相当する役割をこれが担う
- 設計相談: OpenCode CLI（`opencode run -m openai/gpt-5.6-sol-pro "..."`、失敗時は `github-copilot/gpt-5.6-sol`）または `subagent` ツール（pi の defaultModel と OpenCode のモデルは別系統なので相互補完が活きる）

## pi 仕様メモ

- サブエージェント起動: pi の `subagent` ツールを使用

### DONT-ASK MODE

環境変数 `PI_DONT_ASK_MODE=1` が設定されている場合:

| 通常の確認 | DONT-ASK 時の動作 |
|-----------|------------------|
| tier 上書き確認 | 判定結果をそのまま使用して続行 |
| Gate 1 承認 | 自動承認して続行 |
| Gate 3 FAIL 時の判断 | 自動で team-implement に戻り1回リトライ |
| 未コミット変更の確認 | 自動コミットして続行 |
| 元ブランチ不明 | main にフォールバック |
