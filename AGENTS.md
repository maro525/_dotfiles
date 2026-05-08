# Global Agent Instructions

Claude Code + OpenCode CLI + pi CLI + Gemini CLI で並列開発を加速するための、共通エージェント仕様。

このファイルは Claude Code / OpenCode が直接参照する SSoT。
pi CLI 用の追加指示は `pi/AGENTS.pi.md` にあり、デプロイ時に本ファイル末尾へ連結する:

```bash
{ cat AGENTS.md; echo; cat pi/AGENTS.pi.md; } > ~/.pi/agent/AGENTS.md
```

## DOCUMENTATION STRUCTURE

| Path | Purpose |
|------|---------|
| `.claude/commands/` / `.opencode/commands/` / `pi/skills/` | orchestrate / startproject / team-implement / team-review / deploy |
| `.claude/agents/` / `.opencode/agents/` / `pi/agents/` | 各フェーズ用 subagent 定義 |
| `.claude/docs/decisions/task-{LINEAR_ID}-{feature}.md` | 統合タスクファイル (SSoT) |
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

## ROUTING NOTES (共通)

- Git / Linear MCP は各フェーズ内で直接実行
- 外部リサーチは Gemini CLI（`gemini -p "..." 2>/dev/null`）
- 設計相談は実行中エージェント自身で対応するか、`task` tool（subagent）で並列起動

---

## ツール固有

### OpenCode 固有

- 配置先: `~/.config/opencode/` 配下（`AGENTS.md` / `agents/` / `commands/` / `skills/`）
- **自動スキル提案なし**: UserPromptSubmit hook 相当が無いため、`/orchestrate` などスキルは明示呼び出し必須
- **スキル間連鎖**: `@agent-name` mention で起動。コマンド同士の直接呼び出しは不可
- **サブエージェント起動**: `task` tool を使用
- **`context: fork` 代替**: `mode: subagent` + `subtask: true`（親子間のトークン共有挙動は若干異なる）
- 設計相談: OpenCode 自身で対応するか、`task` tool（subagent）で並列起動。モデル多様性が必要な場合は Gemini CLI を併用
