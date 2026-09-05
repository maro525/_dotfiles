---
name: team-implement
description: Implementation phase — read design, implement code, return an implementation payload. The caller writes TASK_FILE and posts to Linear. Called by /orchestrate with tier, task-file, linear-id.
context: fork
agent: general-purpose
model: best
color: blue
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Agent, Skill, AskUserQuestion, SendMessage, TodoWrite, mcp__linear-server__get_issue
---

# team-implement

実装フェーズを担当。コード（実装・テスト）の読み書きと git 操作は自分で行う。

**TASK_FILE への書き込みと Linear への投稿は行わない。**
実装結果は OUTPUT フォーマットで呼び出し元（`/orchestrate` STEP 4）に返し、
TASK_FILE の更新・Linear コメント投稿・ステータス変更は呼び出し元が行う。
TASK_FILE は Read のみ（`Brief` / `Design` / `Decision Log` の参照用）。

Don't-Ask 等の共通ルールは CLAUDE.md 参照。

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
4. orchestrator から渡された実装タスクリスト（startproject の `PLAN`）

---

## IMPLEMENTATION

**tier によってチーム構成を切り替える。**

### tier=S
Claude Lead が直接実装する。

- feature ブランチを作成して作業
- テストを書いてから実装（TDD）
- 完了後に OUTPUT の `IMPLEMENTATION_NOTES` にまとめる

### tier=M
Claude Lead が直接実装 or 1-2 サブエージェントに委譲。

- feature ブランチを作成して作業
- モジュールが独立している場合はサブエージェントに並列実装させる
- 各サブエージェントの成果を Claude Lead がレビュー・統合
- 完了後に OUTPUT の `IMPLEMENTATION_NOTES` にまとめる

### tier=L
フルチームでモジュール単位のオーナーシップ制。

- feature ブランチを作成して作業
- Claude Lead がモジュールを分割し、各サブエージェントにアサイン
- 各サブエージェントは担当モジュールの実装・テストまで完結させる
- サブエージェント間の依存は Claude Lead が調整
- 完了後に OUTPUT の `IMPLEMENTATION_NOTES` にまとめる

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
- [ ] OUTPUT の `IMPLEMENTATION_NOTES` が記入済み

---

## OUTPUT

**TASK_FILE には書き込まない。Linear にも投稿しない。**
以下のフォーマットを最終レスポンスとしてそのまま返す。
呼び出し元（`/orchestrate` STEP 4-3 / 4-4）が TASK_FILE と Linear へ反映する。

```markdown
### IMPLEMENTATION_NOTES

#### 実装サマリー
- 実装したモジュール・ファイル一覧
- 主要な実装判断とその理由

#### 変更ファイル
- path/to/file.ts — 変更内容の概要
- ...

#### テスト
- テストファイルの場所
- カバレッジの概要

#### 残課題・注意点
- レビュアーへの申し送り事項

### DECISION_LOG
- [team-implement] POST: ...

### LINEAR_COMMENT
（Linear に投稿する実装完了コメント本文）

### BRANCH
feature/{feature-name}
```

| OUTPUT セクション | 呼び出し元での反映先 |
|---|---|
| `IMPLEMENTATION_NOTES` | TASK_FILE の `Implementation Notes` セクション |
| `DECISION_LOG` | TASK_FILE の `Decision Log` に追記 |
| `LINEAR_COMMENT` | Linear に投稿 |
| `BRANCH` | STEP 5 / STEP 6 へ引き渡し |

---

## DONT-ASK MODE

| 通常の確認 | DONT-ASK 時の動作 |
|---|---|
| 設計上の判断 | TASK_FILE の Design セクションから推定して続行 |
| エスカレーション承認 | 自動で tier を引き上げて続行 |
| 実装完了確認 | 完了条件を満たしたら自動で呼び出し元へ制御を返す |
