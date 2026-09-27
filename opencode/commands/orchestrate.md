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
- **[MUST]** の付いたステップは、どの tier でもスキップしない
- Linear への投稿・ステータス変更に失敗したら、黙って飛ばさずユーザーに報告する

**原則として止まるのは以下の Gate のみ。** ただし各フェーズが途中でユーザーに確認を求めた場合（startproject の要件ヒアリングなど）は、それに従う。

| Gate | タイミング | 動作 |
|------|-----------|------|
| Gate 1 | startproject の計画提示後 | ユーザー承認を待つ |
| Gate 2 | team-review の FAIL 時 | ユーザーに報告し判断を待つ |

## Git ルール

`AGENTS.md` の「GIT RULES」に従う。

---

## STEP 0: CLASSIFY

`AGENTS.md` の「ADAPTIVE EXECUTION」の基準で tier を判定する。

判定結果と根拠をユーザーに日本語で報告。上書き指示がない限り即 STEP 1 へ。

**tier=XS の場合:** 直接実装を提案してここで終了する（STEP 1 以降は S / M / L のみ）。

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
- branch:
- base:

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

subagent を呼び出して計画フェーズを委譲する:

```
@startproject "{task description} --tier={tier} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
```

startproject 内で質問が発生した場合はユーザーが回答。回答後は startproject が続行。

**Gate 1:** startproject が自己判断で発動し、ユーザーの承認（または修正）が済んでから返ってくる（詳細は `agents/startproject.md`）。
返却後は `GATE1` の値に関わらず即 STEP 4 へ進む。`GATE1`（`auto-approved` / `approved` / `revised`）は STEP 7 の完了報告に含める。

---

## STEP 4: team-implement を実行

**完了次第即 STEP 5 へ。**

開始時に TASK_FILE の `status` を `implementing` に、Linear のステータスを "In Progress" に変更する。

```
@team-implement "{task description} --tier={tier} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
```

team-implement は TASK_FILE の `## team-implement` に `### {n}回目` として追記し、`## Meta` の `branch:` / `base:` に作業ブランチとその分岐元を記入する。変更はコミットしない（deploy がコミットする）。

### 4-1. エスカレーション

team-implement が `ESCALATION: {新しい tier}: {理由}` を返した場合（tier の引き上げで中断した）:

1. ユーザーに新しい tier と理由を報告する
2. `tier` 変数と `## Meta` の `tier:` を更新する（`status` は `implementing` のまま。`planning` に戻すと kanban が「status が古い」と警告するため）
3. 新しい tier で STEP 3 からやり直す。startproject は `## startproject` を上書きする。作業ブランチ上の変更はそのまま引き継ぐ

### 4-2. 完了確認

`ESCALATION` がなく、TASK_FILE の `## team-implement` の最新回と `branch:` / `base:` が記入されていることを確認してから STEP 5 へ進む。

---

## STEP 5: team-review を実行

```
@team-review "{task description} --tier={tier} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
```

team-review は TASK_FILE の `## team-review` に `### {n}回目` として追記する（FAIL の場合も必ず書き込む）。Gate 2 で STEP 4 に戻ったら、次の実装・レビューは n+1 回目として追記する（上書きしない）。

**Gate 2:**
- PASS → 即 STEP 6
- FAIL → ユーザーに報告し判断を待つ（STEP 4 に戻る場合は `status` を `implementing` に戻す）

---

## STEP 6: deploy を実行

**完了次第即 STEP 7 へ。**

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
- startproject: ...（Gate 1: {GATE1}）
- team-implement: ...
- team-review: ...
- deploy: ...
```

---

## 状態管理

以下を変数として保持し、全フェーズに引数で渡す:

| 変数 | 設定タイミング |
|------|---------------|
| `tier` | STEP 0 |
| `LINEAR_ID` | STEP 1 |
| `TASK_FILE` | STEP 2 |

作業ブランチとその分岐元は、引数ではなく TASK_FILE の `## Meta` の `branch:` / `base:` で受け渡す（STEP 4 で team-implement が記入）。

### TASK_FILE の `status`

各 STEP の開始時に orchestrator が `## Meta` の `status` を更新する（フェーズ agent は更新しない）。`done` には orchestrator はしない。PR がマージされた後に人間が変更する。

| タイミング | status |
|------|--------|
| STEP 2（作成時） | `planning` |
| STEP 4 開始（Gate 2 で戻った場合も） | `implementing` |
| STEP 5 開始 | `reviewing` |
| STEP 6 開始 | `deploying` |
| STEP 7 | `in-review`（PR を出してマージ待ち） |

---

$ARGUMENTS
