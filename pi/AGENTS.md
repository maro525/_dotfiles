# pi Agent Instructions

pi CLI + OpenCode CLI で並列開発を加速するためのエージェント仕様。OpenCode は pi のデフォルトモデルと異なる `openai/gpt-5.6-sol-pro` を使うため、設計相談で異モデルセカンドオピニオンとして機能する。

## DOCUMENTATION STRUCTURE

| Path | Purpose |
|------|---------|
| `pi/AGENTS.md` | pi 用グローバル指示（OpenCode の `opencode/AGENTS.md` とは独立） |
| `pi/settings.json` | pi 本体設定 (default model / provider / theme) |
| `pi/extensions/permissions.ts` | bash コマンド パーミッション (allow/deny/ask) + Atuin 履歴統合 |
| `../pi-orchestrator/` | プロジェクトオーケストレーター（skills/agents/prompts/extension/config）— 単独リポジトリ |
| `.claude/docs/decisions/task-{LINEAR_ID}-{feature}.md` | 統合タスクファイル (SSoT) — 全 CLI で共有 |
| `.claude/docs/libraries/` | ライブラリ制約 |
| `.claude/logs/` | CLI 入出力ログ |

`.claude/docs/` ツリーは全 CLI で共有する（同じタスクファイルを参照）。

オーケストレーターワークフロー（`/orchestrate`, startproject / team-implement / team-review / deploy の各フェーズ、tier 分類、gate、per-phase model routing、budget）は `pi-orchestrator` リポジトリで管理し、`~/.pi/agent/{agents,prompts,orchestrator.json,extensions/orchestrator}` としてシンボリックリンク展開する。設定・手順の変更はそちらで行うこと。

## LANGUAGE PROTOCOL

思考・コード: 英語 / ユーザー対話: 日本語

## ROUTING NOTES

- Git 操作: `bash` ツールで直接実行
- Linear 連携: MCP または `gh` CLI で代替
- 外部リサーチは `web_search` / `web_fetch` ツール（`@ollama/pi-web-search` パッケージ）。pi は MCP 非対応のため、Claude Code 側の firecrawl MCP に相当する役割をこれが担う
- 設計相談: OpenCode CLI（`opencode run -m openai/gpt-5.6-sol-pro "..."`、失敗時は `github-copilot/gpt-5.6-sol`）または `subagent` ツール（pi の defaultModel と OpenCode のモデルは別系統なので相互補完が活きる）

## pi 仕様メモ

- サブエージェント起動: pi の `subagent` ツールを使用
- パーミッション拡張: `pi/extensions/permissions.ts` が Claude Code 互換の allow/deny/ask モデルを再現し、承認済みコマンドを Atuin 履歴に記録する
