---
name: orchestrate
description: Project orchestrator — classify tier, create task file, run startproject → team-implement → team-review → deploy in sequence.
model: opus[1m]
color: green
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Agent, Skill, AskUserQuestion, TodoWrite, mcp__linear-server__get_issue, mcp__linear-server__save_issue, mcp__linear-server__save_comment, mcp__linear-server__list_issue_statuses
---

# orchestrate

プロジェクト全体のフローを管理する。各 command の実行・Gate 判定・状態管理を担当し、タスクの実行自体は各 command に委譲する。

## Input

```
$ARGUMENTS の形式: "{task description}"
例: "PROJ-573をやりたいです"
例: "カート機能にクーポン適用を追加する"
```

## 実行原則

**$ARGUMENTS を受け取ったら即 STEP 0 から開始し、追加の指示がない限り STEP 7 まで完走する。**

- 全 STEP を自律的に順番に実行する。報告・通知はするが応答を待たずに次へ進む
- 質問が必要なら質問し、回答を受け取ったら止まらず続行する
- **[MUST]** の付いたステップは、どの tier でもスキップしない
- Linear への投稿・ステータス変更に失敗したら、黙って飛ばさずユーザーに報告する
- orchestrate はメインのセッションで動き、各 command は fork（バックグラウンド）で動く。command を起動したら**完了通知で返却を受け取るまで次の手順に進まない**
- 各 command は TASK_FILE への書き込みと Linear への投稿をしない（startproject は Write / Edit を持たない）。OUTPUT フォーマットで返却するので、**書き込みと Linear 投稿は orchestrator が行う**。返却が OUTPUT フォーマットに従っていなければ、command に整形し直させてから書き込む
- git は `$HOME/.claude/rules/tool-routing.md` の「Git Operations」に従う

**原則として止まるのは以下の Gate のみ。** ただし各 command が途中でユーザーに確認を求めた場合（startproject の要件ヒアリングなど）は、それに従う。

| Gate | タイミング | 動作 |
|---|---|---|
| Gate 1 | startproject が計画提示時に自己判断で発動 | startproject 内でユーザー承認を待つ。orchestrate は返却を待つだけ |
| Gate 2 | team-review の FAIL 時 | ユーザーに報告し判断を待つ |

## STEP 0: CLASSIFY

`$HOME/.claude/rules/adaptive-execution.md` の基準で tier を判定し、結果と根拠をユーザーに報告する。上書き指示がない限り即 STEP 1 へ進む。

**tier=XS の場合:** 直接実装を提案してここで終了する（STEP 1 以降は S / M / L のみ）。

## STEP 1: LINEAR タスク確認

$ARGUMENTS から Linear ID（例: `PROJ-573`）を検出する。

- **検出できた場合:** LINEAR_ID として使用（確認不要）。`mcp__linear-server__get_issue` でタスク詳細を取得してタスク説明を補完し、即 STEP 2 へ
- **検出できなかった場合:** ユーザーに Linear タスク ID または URL を質問する。既存タスクがあれば ID を取得、なければ `mcp__linear-server__save_issue` で新規作成し、即 STEP 2 へ

```
LINEAR_ID = "XXX-123"
```

## STEP 2: タスクファイル作成

以下のパスにタスクファイルを作成して即 STEP 3 へ進む。feature は LINEAR_ID のタスク内容から短いスネークケースで命名する。

```
TASK_FILE = .claude/docs/decisions/task-{LINEAR_ID}-{feature}.md
```

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

## STEP 3: startproject を実行

```
/startproject "{task description} --tier={tier} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
```

startproject は `agent: Plan` の読み取り専用コマンド。`BRIEF` / `DESIGN` / `PLAN` / `LINEAR_COMMENT` / `GATE1` を返してくる。途中の質問にはユーザーが回答し、計画完成後に返却される。

**[MUST]** 返却内容を TASK_FILE に書き込む:

| OUTPUT セクション | 書き込み先 |
|---|---|
| `BRIEF` | `## startproject` > `### Brief` |
| `DESIGN` | `## startproject` > `### Design` |
| `PLAN` | `## startproject` > `### Plan` |

**[MUST]** `LINEAR_COMMENT` の本文を `mcp__linear-server__save_comment` で LINEAR_ID に投稿する。

**Gate 1:** startproject が自己判断で発動し、ユーザーの承認（または修正）が済んでから返却してくる（詳細は startproject.md）。`GATE1`（`auto-approved` / `approved` / `revised`）の値に関わらず即 STEP 4 へ進み、値は STEP 7 の完了報告に含める。

## STEP 4: team-implement を実行

開始時に「状態管理」に従い TASK_FILE の `status` と Linear のステータスを更新する。**完了次第即 STEP 5 へ進む。**

```
/team-implement "{task description} --tier={tier} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
```

team-implement はコードと git 操作のみ行い、`IMPLEMENTATION_NOTES` / `LINEAR_COMMENT` / `BRANCH` / `BASE` / `ESCALATION` を返してくる。

**[MUST]** 返却内容を TASK_FILE に書き込む:

| OUTPUT セクション | 書き込み先 |
|---|---|
| `IMPLEMENTATION_NOTES` | `## team-implement` に `### {n}回目` として追記 |
| `BRANCH` | `## Meta` の `branch:` |
| `BASE` | `## Meta` の `base:` |

**[MUST]** `LINEAR_COMMENT` の本文を `mcp__linear-server__save_comment` で LINEAR_ID に投稿する。

**エスカレーション:** 返却に `ESCALATION` がある場合（team-implement が tier の引き上げで中断した）:

1. ユーザーに新しい tier と理由を報告する
2. `tier` 変数と `## Meta` の `tier:` を更新する（`status` は `implementing` のまま。`planning` に戻すと kanban が「status が古い」と警告する）
3. 新しい tier で STEP 3 からやり直し、startproject の返却で `## startproject` を上書きする。作業ブランチ上の変更はそのまま引き継ぐ

**完了確認:** `ESCALATION` がなく、`## team-implement` が埋まっていることを確認してから STEP 5 へ進む。

## STEP 5: team-review を実行

```
/team-review "{task description} --tier={tier} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
```

team-review は `VERDICT` / `REVIEW` / `LINEAR_COMMENT` を返してくる。

**[MUST]** 返却内容を TASK_FILE に書き込む:

| OUTPUT セクション | 書き込み先 |
|---|---|
| `REVIEW` | `## team-review` に `### {n}回目` として追記 |

**FAIL の場合も必ず書き込む**（差し戻し履歴を残すため）。Gate 2 で STEP 4 に戻ったら、次の実装・レビューは n+1 回目として追記する（上書きしない）。

**[MUST]** `LINEAR_COMMENT` の本文を `mcp__linear-server__save_comment` で LINEAR_ID に投稿する。

**Gate 2:** `VERDICT` が `PASS` なら即 STEP 6 へ。`FAIL` ならユーザーに報告し判断を待ち、team-implement に戻るか確認する。

## STEP 6: deploy を実行

**完了次第即 STEP 7 へ進む。**

```
/deploy "{task description} --tier={tier} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
```

deploy はコミット・push・PR / MR 作成のみ行い、`DEPLOY` / `LINEAR_COMMENT` を返してくる。

**[MUST]** 返却内容を TASK_FILE に書き込む:

| OUTPUT セクション | 書き込み先 |
|---|---|
| `DEPLOY` | `## deploy` |

**[MUST]** `LINEAR_COMMENT` を投稿し、Linear のステータスを「状態管理」に従って変更する。

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

## 状態管理

orchestrator は以下を変数として保持し、全 command に引数で渡す。

| 変数 | 設定タイミング |
|---|---|
| `tier` | STEP 0 |
| `LINEAR_ID` | STEP 1 |
| `TASK_FILE` | STEP 2 |

作業ブランチとその分岐元は、引数ではなく TASK_FILE の `## Meta` の `branch:` / `base:` で受け渡す（STEP 4 で記入）。

### TASK_FILE の `status` と Linear ステータス

各 STEP の開始時に `## Meta` の `status` を更新する（Gate 2 で STEP 4 に戻った場合も `implementing` に戻す）。`done` には orchestrator はしない。PR がマージされた後に人間が変更する。

| タイミング | TASK_FILE `status` | Linear ステータス |
|---|---|---|
| STEP 2（作成時） | `planning` | — |
| STEP 4 開始 | `implementing` | "In Progress" |
| STEP 5 開始 | `reviewing` | — |
| STEP 6 開始 | `deploying` | — |
| STEP 6（deploy 返却後） | — | "In Review" |
| STEP 7 | `in-review`（PR を出してマージ待ち） | — |
