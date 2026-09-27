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
TASK_FILE は Read のみ（`## startproject` の参照用）。

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

1. TASK_FILE の `## startproject` > `### Brief` — プロジェクト概要・スコープ・成功基準
2. TASK_FILE の `## startproject` > `### Design` — 設計方針とその理由
3. TASK_FILE の `## startproject` > `### Plan` — 実装タスクリスト

---

## IMPLEMENTATION

feature ブランチで作業し、テストを先に書く（TDD）。tier によって体制を切り替える。

| tier | 体制 |
|---|---|
| S | 自分で実装する |
| M | 自分で実装するか、独立したモジュールを 1-2 サブエージェントに並列で任せて統合する |
| L | モジュール単位で分割してサブエージェントに割り当てる（実装・テストまで担当モジュール内で完結）。依存の調整と統合は自分が行う |

---

## 実装中のエスカレーション確認

`$HOME/.claude/rules/adaptive-execution.md` の Escalation に従って tier を再評価する。
エスカレーションが必要な場合はユーザーに報告し、承認を得てから続行する。

---

## 完了条件

Plan のタスクがすべて完了し、テストがすべて通過したら OUTPUT を返す。

---

## OUTPUT

以下のフォーマットを最終レスポンスとしてそのまま返す。

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

### LINEAR_COMMENT
（Linear に投稿する実装完了コメント本文）

### BRANCH
feature/{feature-name}
```
