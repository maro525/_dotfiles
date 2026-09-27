---
name: orchestrate
description: Project orchestrator — classify tier, create task file, run startproject → team-implement → team-review → deploy in sequence.
context: fork
model: opus[1m]
color: green
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Agent, Skill, AskUserQuestion, TodoWrite, mcp__linear-server__get_issue, mcp__linear-server__save_issue, mcp__linear-server__save_comment, mcp__linear-server__list_issue_statuses
---

# orchestrate

プロジェクト全体のフローを管理する。
各 command の実行・Gate 判定・状態管理を担当。
タスクの実行自体は各 command に委譲する。

## Input

```
$ARGUMENTS の形式: "{task description}"
例: "PROJ-573をやりたいです"
例: "カート機能にクーポン適用を追加する"
```

## 実行原則

**$ARGUMENTS を受け取ったら即 STEP 0 から開始する。**

- 全 STEP を自律的に順番に実行する
- 報告・通知はするが、応答を待たずに次の STEP へ進む
- 質問が必要な場合は質問する。回答を受け取ったら止まらず続行する
- 追加の指示がない限り STEP 7 まで完走する
- **[MUST]** の付いたステップは、どの tier でもスキップしない
- Linear への投稿・ステータス変更に失敗したら、黙って飛ばさずユーザーに報告する

**原則として止まるのは以下の Gate のみ。** ただし各 command が途中でユーザーに確認を求めた場合（startproject の要件ヒアリングなど）は、それに従う。

| Gate | タイミング | 動作 |
|---|---|---|
| Gate 1 | startproject の計画提示後 | ユーザー承認を待つ |
| Gate 2 | team-review の FAIL 時 | ユーザーに報告し判断を待つ |

## Git ルール

`$HOME/.claude/rules/tool-routing.md` の「Git Operations」に従う。

---

## STEP 0: CLASSIFY

`$HOME/.claude/rules/adaptive-execution.md` の基準で tier を判定する。

判定結果と根拠をユーザーに報告する。上書き指示がない限り即 STEP 1 へ進む。

**tier=XS の場合:** 直接実装を提案してここで終了する（STEP 1 以降は S / M / L のみ）。

---

## STEP 1: LINEAR タスク確認

$ARGUMENTS から Linear ID（例: `PROJ-573`）を検出する。

**ID が検出できた場合:**
- LINEAR_ID として使用。確認不要
- `mcp__linear-server__get_issue` でタスク詳細を取得してタスク説明を補完
- 即 STEP 2 へ進む

**ID が検出できなかった場合:**
- ユーザーに Linear タスク ID または URL を質問する
- 既存タスクがあれば ID を取得、なければ `mcp__linear-server__save_issue` で新規作成
- 回答を受け取ったら即 STEP 2 へ進む

```
LINEAR_ID = "XXX-123"
```

---

## STEP 2: タスクファイル作成

以下のパスにタスクファイルを作成して即 STEP 3 へ進む。

```
TASK_FILE = .claude/docs/decisions/task-{LINEAR_ID}-{feature}.md
```

feature は LINEAR_ID のタスク内容から短いスネークケースで命名する。

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
<!-- orchestrator が startproject の返却 BRIEF から記入 -->

### Design
<!-- orchestrator が startproject の返却 DESIGN から記入 -->

### Plan
<!-- orchestrator が startproject の返却 PLAN から記入 -->

## team-implement
<!-- orchestrator が team-implement の返却 IMPLEMENTATION_NOTES から記入 -->

## team-review
<!-- orchestrator が team-review の返却 REVIEW から記入 -->

## deploy
<!-- orchestrator が deploy の返却 DEPLOY から記入 -->
```

`##` 見出しはプロセス名で固定する（kanban がこの見出しでフェーズを判定する）。

---

## STEP 3: startproject を実行

### 3-1. 実行

```
/startproject "{task description} --tier={tier} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
```

startproject は `agent: Plan` の**読み取り専用**コマンドで、自分ではファイルを書かず Linear にも投稿しない。
計画一式を OUTPUT フォーマット（`BRIEF` / `DESIGN` / `PLAN` / `LINEAR_COMMENT` / `GATE1`）で返してくる。

startproject 内で質問が発生した場合はユーザーが回答する。
回答後は startproject が続行し、計画が完成したら返却される。

### 3-2. **[MUST]** 返却内容を書き込む

**orchestrator が実行する。startproject は Write / Edit を持たないため実行できない。**

| OUTPUT セクション | 書き込み先 |
|---|---|
| `BRIEF` | TASK_FILE の `## startproject` > `### Brief` |
| `DESIGN` | TASK_FILE の `## startproject` > `### Design` |
| `PLAN` | TASK_FILE の `## startproject` > `### Plan` |

返却が OUTPUT フォーマットに従っていない場合は、startproject に整形し直させてから書き込む。

### 3-3. **[MUST]** Linear にコメントを投稿する

`mcp__linear-server__save_comment` で LINEAR_ID に `LINEAR_COMMENT` の本文を投稿する。

### 3-4. Gate 1

startproject が自己判断して発動し、ユーザーの承認（または修正）が済んでから返却してくる（詳細は startproject.md 参照）。
返却後は `GATE1` の値に関わらず即 STEP 4 へ進む。`GATE1`（`auto-approved` / `approved` / `revised`）は STEP 7 の完了報告に含める。

---

## STEP 4: team-implement を実行

**完了次第即 STEP 5 へ進む。**

開始時に TASK_FILE の `status` を `implementing` に、Linear のステータスを "In Progress" に変更する。

### 4-1. 実行

```
/team-implement "{task description} --tier={tier} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
```

team-implement はコードと git 操作のみ行い、**TASK_FILE への書き込みと Linear 投稿は行わない**。
結果を OUTPUT フォーマット（`IMPLEMENTATION_NOTES` / `LINEAR_COMMENT` / `BRANCH` / `BASE` / `ESCALATION`）で返してくる。

### 4-2. **[MUST]** 返却内容を書き込む

| OUTPUT セクション | 書き込み先 |
|---|---|
| `IMPLEMENTATION_NOTES` | TASK_FILE の `## team-implement` に `### {n}回目` として追記 |
| `BRANCH` | TASK_FILE の `## Meta` の `branch:` |
| `BASE` | TASK_FILE の `## Meta` の `base:` |

### 4-3. **[MUST]** Linear にコメントを投稿する

`mcp__linear-server__save_comment` で LINEAR_ID に `LINEAR_COMMENT` の本文を投稿する。

### 4-4. エスカレーション

返却に `ESCALATION` がある場合（team-implement が tier の引き上げで中断した）:

1. ユーザーに新しい tier と理由を報告する
2. `tier` 変数と `## Meta` の `tier:` を更新する（`status` は `implementing` のまま。`planning` に戻すと kanban が「status が古い」と警告するため）
3. 新しい tier で STEP 3 からやり直す。startproject の返却で `## startproject` を上書きする。作業ブランチ上の変更はそのまま引き継ぐ

### 4-5. 完了確認

`ESCALATION` がなく、TASK_FILE の `## team-implement` が 4-2 で埋まっていることを確認してから STEP 5 へ進む。

---

## STEP 5: team-review を実行

### 5-1. 実行

```
/team-review "{task description} --tier={tier} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
```

team-review は **TASK_FILE への書き込みと Linear 投稿を行わない**。
結果を OUTPUT フォーマット（`VERDICT` / `REVIEW` / `LINEAR_COMMENT`）で返してくる。

### 5-2. **[MUST]** 返却内容を書き込む

| OUTPUT セクション | 書き込み先 |
|---|---|
| `REVIEW` | TASK_FILE の `## team-review` に `### {n}回目` として追記 |

**FAIL の場合も必ず書き込む**（差し戻し履歴を残すため）。Gate 2 で STEP 4 に戻ったら、次の実装・レビューは n+1 回目として追記する（上書きしない）。

### 5-3. **[MUST]** Linear にコメントを投稿する

`mcp__linear-server__save_comment` で LINEAR_ID に `LINEAR_COMMENT` の本文を投稿する。

### 5-4. Gate 2

返却の `VERDICT` で判別する。

- `PASS` → 即 STEP 6 へ進む
- `FAIL` → ユーザーに報告し判断を待つ。team-implement に戻るか確認する

---

## STEP 6: deploy を実行

**完了次第即 STEP 7 へ進む。**

### 6-1. 実行

```
/deploy "{task description} --tier={tier} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
```

deploy はコミット・push・PR・MR 作成のみ行い、**TASK_FILE への書き込みと Linear 操作は行わない**。
結果を OUTPUT フォーマット（`DEPLOY` / `LINEAR_COMMENT`）で返してくる。

### 6-2. **[MUST]** 返却内容を書き込む

| OUTPUT セクション | 書き込み先 |
|---|---|
| `DEPLOY` | TASK_FILE の `## deploy` |

### 6-3. **[MUST]** Linear にコメント投稿 + ステータス変更

`LINEAR_COMMENT` を投稿し、ステータスを "In Review" に変更する。

---

## STEP 7: 完了報告

ユーザーに日本語で最終サマリーを報告する。

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

orchestrator は以下を変数として保持し、全 command に引数で渡す。

| 変数 | 設定タイミング |
|---|---|
| `tier` | STEP 0 |
| `LINEAR_ID` | STEP 1 |
| `TASK_FILE` | STEP 2 |

作業ブランチとその分岐元は、引数ではなく TASK_FILE の `## Meta` の `branch:` / `base:` で受け渡す（STEP 4 で記入）。

### TASK_FILE の `status`

各 STEP の開始時に `## Meta` の `status` を更新する（Gate 2 で STEP 4 に戻った場合も `implementing` に戻す）。`done` には orchestrator はしない。PR がマージされた後に人間が変更する。

| タイミング | status |
|---|---|
| STEP 2（作成時） | `planning` |
| STEP 4 開始 | `implementing` |
| STEP 5 開始 | `reviewing` |
| STEP 6 開始 | `deploying` |
| STEP 7 | `in-review`（PR を出してマージ待ち） |
