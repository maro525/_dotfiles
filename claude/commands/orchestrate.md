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
<!-- orchestrator が startproject の返却 BRIEF から記入 -->

## Decision Log
<!-- 各 command が追記 -->

## Design
<!-- orchestrator が startproject の返却 DESIGN から記入（tier=M,L）。tier=S は空欄でよい -->

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

### 3-1. 実行

```
/startproject "{task description} --tier={tier} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
```

startproject は `agent: Plan` の**読み取り専用**コマンドで、自分ではファイルを書かず Linear にも投稿しない。
計画一式を OUTPUT フォーマット（`BRIEF` / `DECISION_LOG` / `DESIGN` / `CLAUDE_MD_CURRENT_PROJECT` / `PLAN` / `LINEAR_COMMENT` / `GATE1`）で返してくる。

startproject 内で質問が発生した場合はユーザーが回答する。
回答後は startproject が続行し、計画が完成したら返却される。

### 3-2. **[MUST]** 返却内容を書き込む

**orchestrator が実行する。startproject は Write / Edit を持たないため実行できない。**

| OUTPUT セクション | 書き込み先 | tier |
|---|---|---|
| `BRIEF` | TASK_FILE の `Brief` セクション | 全 tier |
| `DECISION_LOG` | TASK_FILE の `Decision Log` に追記 | 全 tier |
| `DESIGN` | TASK_FILE の `Design` セクション | M, L（S は N/A） |
| `CLAUDE_MD_CURRENT_PROJECT` | プロジェクトの `CLAUDE.md` に Current Project セクションを追加 | 全 tier |
| `PLAN` | 変数として保持し STEP 4 へ引き渡す | 全 tier |

返却が OUTPUT フォーマットに従っていない場合は、startproject に整形し直させてから書き込む。

### 3-3. **[MUST]** Linear にコメントを投稿する

`mcp__linear-server__save_comment` で LINEAR_ID に `LINEAR_COMMENT` の本文を投稿する。
投稿できなかった場合はユーザーに報告する（無言でスキップしない）。

### 3-4. Gate 1

startproject が自己判断して発動する（詳細は startproject.md 参照）。返却の `GATE1` で判別する。

- `auto-approved` → 即 STEP 4 へ進む
- `approved` → startproject 内で承認済み。即 STEP 4 へ進む
- `revised` → 修正後の計画。内容を確認して STEP 4 へ進む

---

## STEP 4: team-implement を実行

**全 tier で実行。完了次第即 STEP 5 へ進む。**

### 4-1. Linear ステータスを "In Progress" に変更

```
1. mcp__linear-server__list_issue_statuses で利用可能なステータス一覧を取得
2. "In Progress" に該当するステータス ID を特定
3. mcp__linear-server__save_issue でステータスを更新
```

### 4-2. 実行

```
/team-implement "{task description} --tier={tier} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
```

| tier | 動作 |
|---|---|
| XS | Claude が直接実装。ただし保護ブランチ（release/staging/main）上にいる場合は feature ブランチを作成 |
| S | feature ブランチ。Claude が直接実装 |
| M | feature ブランチ。Claude 直接 or 1-2 サブエージェント |
| L | feature ブランチ。フルチーム（モジュール単位オーナーシップ） |

team-implement はコードと git 操作のみ行い、**TASK_FILE への書き込みと Linear 投稿は行わない**。
結果を OUTPUT フォーマット（`IMPLEMENTATION_NOTES` / `DECISION_LOG` / `LINEAR_COMMENT` / `BRANCH`）で返してくる。

### 4-3. **[MUST]** 返却内容を書き込む

| OUTPUT セクション | 書き込み先 |
|---|---|
| `IMPLEMENTATION_NOTES` | TASK_FILE の `Implementation Notes` セクション |
| `DECISION_LOG` | TASK_FILE の `Decision Log` に追記 |
| `BRANCH` | 変数として保持し STEP 5 / STEP 6 へ引き渡す |

### 4-4. **[MUST]** Linear にコメントを投稿する

`mcp__linear-server__save_comment` で LINEAR_ID に `LINEAR_COMMENT` の本文を投稿する。
投稿できなかった場合はユーザーに報告する（無言でスキップしない）。

### Gate 2（内部確認）

TASK_FILE の `Implementation Notes` が 4-3 で埋まっていることを確認してから STEP 5 へ進む。

---

## STEP 5: team-review を実行

**tier=XS はスキップして即 STEP 6 へ。**

### 5-1. 実行

```
/team-review "{task description} --tier={tier} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
```

| tier | レビュー方式 |
|---|---|
| XS | スキップ |
| S | `--mode=self-review`（Claude 単独レビュー） |
| M | 2レビュアー（Claude + OpenCode） |
| L | 4レビュアー（Claude / OpenCode / Security / Simplify） |

team-review は **TASK_FILE への書き込みと Linear 投稿を行わない**。
結果を OUTPUT フォーマット（`VERDICT` / `REVIEW` / `DECISION_LOG` / `LINEAR_COMMENT`）で返してくる。

### 5-2. **[MUST]** 返却内容を書き込む

| OUTPUT セクション | 書き込み先 |
|---|---|
| `REVIEW` | TASK_FILE の `Review` セクション |
| `DECISION_LOG` | TASK_FILE の `Decision Log` に追記 |

**FAIL の場合も必ず書き込む**（差し戻し履歴を残すため）。

### 5-3. **[MUST]** Linear にコメントを投稿する

`mcp__linear-server__save_comment` で LINEAR_ID に `LINEAR_COMMENT` の本文を投稿する。

### 5-4. Gate 3

返却の `VERDICT` で判別する。

- `PASS` → 即 STEP 6 へ進む
- `FAIL` → ユーザーに報告し判断を待つ。team-implement に戻るか確認する

**DONT-ASK MODE:** FAIL 時は自動で STEP 4 に戻り1回リトライする。

---

## STEP 6: deploy を実行

**全 tier で実行。完了次第即 STEP 7 へ進む。**

### 6-1. 実行

```
/deploy "{task description} --tier={tier} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
```

deploy は push / PR・MR 作成 / デプロイ後検証のみ行い、**TASK_FILE への書き込みと Linear 操作は行わない**。
結果を OUTPUT フォーマット（`DEPLOY` / `DECISION_LOG` / `LINEAR_COMMENT` / `LINEAR_STATUS`）で返してくる。

### 6-2. **[MUST]** 返却内容を書き込む

| OUTPUT セクション | 書き込み先 |
|---|---|
| `DEPLOY` | TASK_FILE の `Deploy` セクション |
| `DECISION_LOG` | TASK_FILE の `Decision Log` に追記 |

### 6-3. **[MUST]** Linear にコメント投稿 + ステータス変更

```
1. mcp__linear-server__save_comment で LINEAR_ID に LINEAR_COMMENT を投稿
2. mcp__linear-server__list_issue_statuses で LINEAR_STATUS（通常は "In Review"）の ID を特定
3. mcp__linear-server__save_issue でステータスを更新
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
| `PLAN` | STEP 3（startproject の返却） |
| `BRANCH` | STEP 4（team-implement の返却） |

---

## DONT-ASK MODE

| 通常の確認 | DONT-ASK 時の動作 |
|---|---|
| tier 上書き確認 | 判定結果をそのまま使用して続行 |
| Gate 1 承認 | 自動承認して続行 |
| Gate 3 FAIL 時の判断 | 自動で team-implement に戻り1回リトライ |
