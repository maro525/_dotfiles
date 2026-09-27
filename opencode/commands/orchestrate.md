---
description: Project orchestrator — classify tier, create task file, run startproject → team-implement → team-review → deploy in sequence.
agent: build
---

# orchestrate

プロジェクト全体のフローを管理する。各フェーズは subagent へ委譲し、Gate 判定・状態管理を担当する。

## Input

```
$ARGUMENTS の形式: "{task description}"
例: "PROJ-573をやりたいです"
例: "カート機能にクーポン適用を追加する"
```

## 実行原則

**$ARGUMENTS を受け取ったら即 STEP 0 から開始する。**

- 全 STEP を自律的に順番に実行する
- 止まるのは以下の Gate のみ:

| Gate | タイミング | 動作 |
|------|-----------|------|
| Gate 1 | startproject の計画提示後 | ユーザー承認を待つ |
| Gate 3 | team-review の FAIL 時 | ユーザーに報告し判断を待つ |

## Git ルール

`AGENTS.md` の「GIT RULES」に従う。

---

## STEP 0: CLASSIFY

`AGENTS.md` の「ADAPTIVE EXECUTION」の基準で tier を判定する。

判定結果と根拠をユーザーに日本語で報告。上書き指示がない限り即 STEP 1 へ。

**tier=XS の場合:** 直接実装を提案してここで終了。

---

## STEP 1: LINEAR タスク確認

`$ARGUMENTS` から Linear ID（例: `PROJ-573`）を検出する。

**ID 検出時:**
- LINEAR_ID として使用
- Linear MCP の `get_issue` でタスク詳細を取得してタスク説明を補完
- 即 STEP 2 へ

**ID 未検出時:**
- ユーザーに Linear タスク ID または URL を質問
- 既存タスクがあれば ID を取得、なければ Linear MCP の `save_issue` で新規作成
- 回答を受け取ったら即 STEP 2 へ

---

## STEP 2: タスクファイル作成

```
TASK_FILE = .claude/docs/decisions/task-{LINEAR_ID}-{feature}.md
```

feature は LINEAR_ID のタスク内容から短いスネークケースで命名。

**初期テンプレート:**

```markdown
# Task: {LINEAR_ID} — {task description}

## Meta
- linear_id: {LINEAR_ID}
- tier: {tier}
- created: {timestamp}
- status: planning

## startproject
### Brief
<!-- startproject が記入 -->

### Design
<!-- startproject が記入 -->

### Plan
<!-- startproject が記入 -->

## team-implement
<!-- team-implement が記入 -->

## team-review
<!-- team-review が記入 -->

## deploy
<!-- deploy が記入 -->
```

`##` 見出しはプロセス名で固定する（kanban がこの見出しでフェーズを判定する）。

---

## STEP 3: startproject を実行

**tier=S,M,L のみ実行。** subagent を呼び出して計画フェーズを委譲する:

```
@startproject "{task description} --tier={tier} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
```

startproject 内で質問が発生した場合はユーザーが回答。回答後は startproject が続行。

**Gate 1:** startproject が自己判断で発動（詳細は `agents/startproject.md`）:
- 自動承認 → 即 STEP 4
- Gate 1 発動 → ユーザー承認を待つ。承認後即 STEP 4
- 差し戻し → フィードバックをもとに計画を修正して再提示

---

## STEP 4: team-implement を実行

**全 tier で実行。完了次第即 STEP 5 へ。**

```
@team-implement "{task description} --tier={tier} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
```

**Gate 2 (内部):** TASK_FILE の `## team-implement` 記入を確認してから STEP 5。

---

## STEP 5: team-review を実行

**tier=XS はスキップして即 STEP 6 へ。**

```
@team-review "{task description} --tier={tier} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
```

tier=S の場合は `--mode=self-review` を付ける。

**Gate 3:**
- PASS → 即 STEP 6
- FAIL → ユーザーに報告し判断を待つ（STEP 4 に戻る場合は `status` を `implementing` に戻す）

---

## STEP 6: deploy を実行

**全 tier で実行。完了次第即 STEP 7 へ。**

```
@deploy "{task description} --tier={tier} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
```

---

## STEP 7: 完了報告

ユーザーに日本語で最終サマリーを報告:

```
## 完了: {task description}

- Linear: {LINEAR_ID}
- Tier: {tier}
- Task File: {TASK_FILE}

### 各フェーズのサマリー
- startproject: ...
- team-implement: ...
- team-review: ...
- deploy: ...
```

---

## 状態管理

以下を変数として保持し、全フェーズに渡す:

| 変数 | 設定タイミング |
|------|---------------|
| `tier` | STEP 0 |
| `LINEAR_ID` | STEP 1 |
| `TASK_FILE` | STEP 2 |

### TASK_FILE の `status`

各 STEP の開始時に orchestrator が `## Meta` の `status` を更新する（フェーズ agent は更新しない）。

| タイミング | status |
|------|--------|
| STEP 2（作成時） | `planning` |
| STEP 4 開始（Gate 3 で戻った場合も） | `implementing` |
| STEP 5 開始 | `reviewing` |
| STEP 6 開始 | `deploying` |
| STEP 7 | `done` |

---

$ARGUMENTS
