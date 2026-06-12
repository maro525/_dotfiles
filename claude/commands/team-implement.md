---
name: team-implement
description: Implementation phase — read design, implement code, write to task file. Called by /orchestrate with tier, task-file, linear-id.
context: fork
agent: Plan
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Agent, Skill, AskUserQuestion, SendMessage, TodoWrite, mcp__linear-server__save_comment, mcp__linear-server__get_issue
---

# team-implement

実装フェーズを担当。
タスクファイル・Decision Log・Linear・Don't-Ask の共通ルールは CLAUDE.md 参照。

## Input

```
$ARGUMENTS の形式: "{task description} --tier={S|M|L} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
```

| 引数 | 説明 |
|---|---|
| `--tier` | orchestrator が判定済み |
| `--task-file` | orchestrator が作成済みのタスクファイルパス |
| `--linear-id` | orchestrator が確認済みの Linear タスク ID |

---

## 事前準備

実装開始前に必ず以下を読む。

1. TASK_FILE の `Brief` セクション — プロジェクト概要・スコープ・成功基準
2. TASK_FILE の `Design` セクション（tier=M,L）— 設計方針・アーキテクチャ決定
3. TASK_FILE の `Decision Log` — これまでの意思決定
4. `TodoWrite` のタスクリスト — startproject が作成した実装タスク

---

## IMPLEMENTATION

**tier によってチーム構成を切り替える。**

### tier=S
Claude Lead が直接実装する。

- feature ブランチを作成して作業
- テストを書いてから実装（TDD）
- 完了後に TASK_FILE の `Implementation Notes` に記録

### tier=M
Claude Lead が直接実装 or 1-2 サブエージェントに委譲。

- feature ブランチを作成して作業
- モジュールが独立している場合はサブエージェントに並列実装させる
- 各サブエージェントの成果を Claude Lead がレビュー・統合
- 完了後に TASK_FILE の `Implementation Notes` に記録

### tier=L
フルチームでモジュール単位のオーナーシップ制。

- feature ブランチを作成して作業
- Claude Lead がモジュールを分割し、各サブエージェントにアサイン
- 各サブエージェントは担当モジュールの実装・テストまで完結させる
- サブエージェント間の依存は Claude Lead が調整
- 完了後に TASK_FILE の `Implementation Notes` に記録

---

## 実装中のエスカレーション確認

以下のタイミングで tier の再評価を行う（adaptive-execution.md 参照）。

| チェックポイント | 確認内容 |
|---|---|
| 実装 30-40% 時点 | スコープが広がっていないか |
| 新依存追加時 | Hard Trigger に該当しないか |
| 設計上の未解決問題が積み上がった時 | tier 引き上げが必要か |

エスカレーションが必要な場合はユーザーに報告し、承認を得てから続行する。

---

## 完了条件

以下をすべて満たしてから次フェーズへ進む。

- [ ] TodoWrite のタスクリストがすべて完了
- [ ] テストがすべて通過
- [ ] TASK_FILE の `Implementation Notes` セクションが記入済み

---

## OUTPUT

TASK_FILE の `Implementation Notes` に以下を記入する。

```markdown
## Implementation Notes

### 実装サマリー
- 実装したモジュール・ファイル一覧
- 主要な実装判断とその理由

### 変更ファイル
- path/to/file.ts — 変更内容の概要
- ...

### テスト
- テストファイルの場所
- カバレッジの概要

### 残課題・注意点
- レビュアーへの申し送り事項
```

**[MUST]** Linear にコメントを投稿する。
- `mcp__linear-server__save_comment` で LINEAR_ID に実装完了コメントを投稿
- TASK_FILE の `Decision Log` に `[team-implement] POST` エントリを追加

---

## DONT-ASK MODE

| 通常の確認 | DONT-ASK 時の動作 |
|---|---|
| 設計上の判断 | TASK_FILE の Design セクションから推定して続行 |
| エスカレーション承認 | 自動で tier を引き上げて続行 |
| 実装完了確認 | 完了条件を満たしたら自動で呼び出し元へ制御を返す |
