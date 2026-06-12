---
name: orchestrate
description: Project orchestrator — classify tier, create task file, run startproject → team-implement → team-review → deploy in sequence.
context: fork
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Agent, Skill, AskUserQuestion, TodoWrite, mcp__linear-server__get_issue, mcp__linear-server__save_issue, mcp__linear-server__save_comment, mcp__linear-server__list_issue_statuses
---

# orchestrate

プロジェクト全体のフローを管理する。
各 command の実行・Gate 判定・状態管理を担当。
タスクの実行自体は各 command に委譲する。

## Input

```
$ARGUMENTS の形式: "{task description}"
例: "NSKETCH-573をやりたいです"
例: "カート機能にクーポン適用を追加する"
```

## 実行原則

**$ARGUMENTS を受け取ったら即 STEP 0 から開始する。**

- 全 STEP を自律的に順番に実行する
- 報告・通知はするが、応答を待たずに次の STEP へ進む
- 質問が必要な場合は質問する。回答を受け取ったら止まらず続行する
- 追加の指示がない限り STEP 7 まで完走する

**止まるのは以下の Gate のみ:**

| Gate | タイミング | 動作 |
|---|---|---|
| Gate 1 | startproject の計画提示後 | ユーザー承認を待つ |
| Gate 3 | team-review の FAIL 時 | ユーザーに報告し判断を待つ |

## Git 共通ルール（全 STEP）

- ホスティングに応じて CLI を使い分ける: GitLab → `glab` / GitHub → `gh`（`git remote get-url origin` で判定）
- **保護ブランチ `release` / `staging` / `main`（master 含む）への直接コミット・push は、ユーザーの明示的な許可がない限り禁止**。反映は必ず PR / MR 経由
- 保護ブランチ上で作業を始める場合は feature ブランチを作成してから実装する（tier=XS も同様）

---

## STEP 0: CLASSIFY

Read `$HOME/.claude/rules/adaptive-execution.md` を読んで tier を判定する。

```
tier = max(file_tier, complexity_tier, risk_tier)
```

Hard Triggers（認証・DB migration・支払い・公開API変更・新規コア依存追加）は自動で L。

| tier | 判定基準 |
|---|---|
| XS | 1ファイル・ロジック変更なし・リスクなし |
| S | 1-3ファイル・単一パターン・低リスク |
| M | 4-10ファイル・複数パターン・中リスク |
| L | 10+ファイル・アーキテクチャ変更・高リスク |

判定結果と根拠をユーザーに報告する。上書き指示がない限り即 STEP 1 へ進む。

**tier=XS の場合:** 直接実装を提案してここで終了。

---

## STEP 1: LINEAR タスク確認

まず $ARGUMENTS から Linear ID パターンを検出する。

```
パターン例: NSKETCH-573、ABC-123
正規表現: [A-Z]+-[0-9]+
```

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

## Brief
<!-- startproject が記入 -->

## Decision Log
<!-- 各 command が追記 -->

## Design
<!-- startproject (tier=M,L) が記入。tier=S は空欄でよい -->

## Implementation Notes
<!-- team-implement が記入 -->

## Review
<!-- team-review が記入 -->

## Deploy
<!-- deploy が記入 -->
```

---

## STEP 3: startproject を実行

**tier=S,M,L のみ実行。**

```
/startproject "{task description} --tier={tier} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
```

startproject 内で質問が発生した場合はユーザーが回答する。
回答後は startproject が続行し、計画が完成したら Gate 1 へ。

**Gate 1:** startproject が自己判断して発動する（詳細は startproject.md 参照）。
- 自動承認の場合 → 即 STEP 4 へ進む
- Gate 1 発動の場合 → startproject がユーザーに承認を求める。承認後即 STEP 4 へ進む
- 差し戻しの場合 → startproject がフィードバックをもとに計画を修正して再提示

---

## STEP 4: team-implement を実行

**全 tier で実行。完了次第即 STEP 5 へ進む。**

```
/team-implement "{task description} --tier={tier} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
```

| tier | 動作 |
|---|---|
| XS | Claude が直接実装。ただし保護ブランチ（release/staging/main）上にいる場合は feature ブランチを作成 |
| S | feature ブランチ。Claude が直接実装 |
| M | feature ブランチ。Claude 直接 or 1-2 サブエージェント |
| L | feature ブランチ。フルチーム（モジュール単位オーナーシップ） |

**Gate 2 (内部確認):** TASK_FILE の `Implementation Notes` が埋まっていることを確認してから STEP 5 へ。

---

## STEP 5: team-review を実行

**tier=XS はスキップして即 STEP 6 へ。**

```
/team-review "{task description} --tier={tier} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
```

| tier | レビュー方式 |
|---|---|
| XS | スキップ |
| S | `--mode=self-review`（Claude 単独レビュー） |
| M | 2レビュアー（Claude + OpenCode） |
| L | 4レビュアー（Claude / OpenCode / Security / Simplify） |

**Gate 3:**
- PASS → 即 STEP 6 へ進む
- FAIL → ユーザーに報告し判断を待つ。team-implement に戻るか確認する

**DONT-ASK MODE:** FAIL 時は自動で team-implement に戻り1回リトライする。

---

## STEP 6: deploy を実行

**全 tier で実行。完了次第即 STEP 7 へ進む。**

```
/deploy "{task description} --tier={tier} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
```

---

## STEP 7: 完了報告

ユーザーに日本語で最終サマリーを報告する。

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

TASK_FILE の `status` を `done` に更新する。

---

## 状態管理

orchestrator は以下を変数として保持し、全 command に渡す。

| 変数 | 設定タイミング |
|---|---|
| `tier` | STEP 0 |
| `LINEAR_ID` | STEP 1 |
| `TASK_FILE` | STEP 2 |

---

## DONT-ASK MODE

| 通常の確認 | DONT-ASK 時の動作 |
|---|---|
| tier 上書き確認 | 判定結果をそのまま使用して続行 |
| Gate 1 承認 | 自動承認して続行 |
| Gate 3 FAIL 時の判断 | 自動で team-implement に戻り1回リトライ |
