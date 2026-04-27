# Global Agent Instructions

Claude Code + OpenCode CLI + pi CLI + Gemini CLI で並列開発を加速するための、共通エージェント仕様。

このファイルは Claude Code / OpenCode / pi の各 CLI から共通で参照される単一の SSoT。
ツール固有の差分は末尾の「ツール固有」セクションに集約する。

## DOCUMENTATION STRUCTURE

| Path | Purpose |
|------|---------|
| `.claude/commands/` / `.opencode/commands/` / `pi/commands/` | orchestrate / startproject / team-implement / team-review / deploy |
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

- Git / Linear MCP は各フェーズ内で直接実行（Claude Code 版の `context: fork` 相当）
- 外部リサーチは Gemini CLI（`gemini -p "..." 2>/dev/null`）
- 設計相談は OpenCode CLI 自身が対応するか、並列セッションを起動

---

## ツール固有

### OpenCode 固有

- `.opencode/` 配下に commands / agents / skills を配置
- 設計相談は OpenCode CLI 自身、または並列セッションを起動

### pi 固有

- Git 操作: `bash` ツールで直接実行
- Linear 連携: MCP または `gh` CLI で代替
- 設計相談: OpenCode CLI（`opencode run -m github-copilot/gpt-5.4 "..."`）またはサブエージェント
- サブエージェント起動: pi の `subagent` ツールを使用

#### DONT-ASK MODE

環境変数 `PI_DONT_ASK_MODE=1` が設定されている場合:

| 通常の確認 | DONT-ASK 時の動作 |
|-----------|------------------|
| tier 上書き確認 | 判定結果をそのまま使用して続行 |
| Gate 1 承認 | 自動承認して続行 |
| Gate 3 FAIL 時の判断 | 自動で team-implement に戻り1回リトライ |
| 未コミット変更の確認 | 自動コミットして続行 |
| 元ブランチ不明 | main にフォールバック |
