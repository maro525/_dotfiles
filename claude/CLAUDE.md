Claude Code + OpenCode CLI で並列開発を加速する。外部リサーチは firecrawl MCP と OpenCode リサーチ（`openai/gpt-5.6-sol-pro`）を並行実行し、Claude が統合する。

DOCUMENTATION STRUCTURE
  .claude/commands/ — orchestrate / startproject / team-implement / team-review / deploy
  .claude/rules/   — コーディング・セキュリティ・ツールルール・エージェント委譲ルール
  .claude/hooks/   — agent-router.py (UserPromptSubmit)
  .claude/docs/decisions/task-{LINEAR_ID}-{feature}.md — 統合タスクファイル (SSoT)
  .claude/docs/libraries/ — ライブラリ制約
  .claude/logs/    — CLI 入出力ログ

WORKFLOW COMMON RULES

  記録ステップ (MUST):
    MUST マーク付きステップは全 tier・全モードでスキップ不可。

LANGUAGE PROTOCOL
  思考・コード: 英語 / ユーザー対話: 日本語
