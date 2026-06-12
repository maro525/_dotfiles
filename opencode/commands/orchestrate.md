---
description: Project orchestrator — classify tier, create task file, run startproject → team-implement → team-review → deploy in sequence.
agent: build
---

# orchestrate

プロジェクト全体のフローを管理する。各フェーズは subagent へ委譲し、Gate 判定・状態管理を担当する。

## Input

```
$ARGUMENTS の形式: "{task description}"
例: "NSKETCH-573をやりたいです"
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

## Git 共通ルール（全 STEP）

- ホスティングに応じて CLI を使い分ける: GitLab → `glab` / GitHub → `gh`（`git remote get-url origin` で判定）
- **保護ブランチ `release` / `staging` / `main`（master 含む）への直接コミット・push は、ユーザーの明示的な許可がない限り禁止**。反映は必ず PR / MR 経由
- 保護ブランチ上で作業を始める場合は feature ブランチを作成してから実装する（tier=XS も同様）

---

## STEP 0: CLASSIFY

`@AGENTS.md` のアダプティブ実行表に従って tier を判定する:

```
tier = max(file_tier, complexity_tier, risk_tier)
```

**Hard Triggers（認証・DB migration・支払い・公開API変更・新規コア依存追加）は自動 L。**

| tier | 判定基準 |
|------|---------|
| XS   | 1ファイル・ロジック変更なし・リスクなし |
| S    | 1-3ファイル・単一パターン・低リスク |
| M    | 4-10ファイル・複数パターン・中リスク |
| L    | 10+ファイル・アーキテクチャ変更・高リスク |

判定結果と根拠をユーザーに日本語で報告。上書き指示がない限り即 STEP 1 へ。

**tier=XS の場合:** 直接実装を提案してここで終了。

---

## STEP 1: LINEAR タスク確認

`$ARGUMENTS` から Linear ID パターンを検出する（正規表現: `[A-Z]+-[0-9]+`）。

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

## Brief
<!-- startproject が記入 -->

## Decision Log
<!-- 各フェーズが追記 -->

## Design
<!-- startproject (tier=M,L) が記入 -->

## Implementation Notes
<!-- team-implement が記入 -->

## Review
<!-- team-review が記入 -->

## Deploy
<!-- deploy が記入 -->
```

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

| tier | 動作 |
|------|------|
| XS   | 直接実装。ただし保護ブランチ（release/staging/main）上にいる場合は feature ブランチを作成 |
| S    | feature ブランチ。直接実装 |
| M    | feature ブランチ。直接 or 1-2 subagent |
| L    | feature ブランチ。フルチーム（モジュール単位） |

**Gate 2 (内部):** TASK_FILE の `Implementation Notes` 記入を確認してから STEP 5。

---

## STEP 5: team-review を実行

**tier=XS はスキップして即 STEP 6 へ。**

```
@team-review "{task description} --tier={tier} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
```

| tier | レビュー方式 |
|------|------------|
| S    | `--mode=self-review` |
| M    | 2レビュアー（Quality + Security） |
| L    | 4レビュアー（Quality / Logic / Security / Simplify） |

**Gate 3:**
- PASS → 即 STEP 6
- FAIL → ユーザーに報告し判断を待つ
- DONT-ASK MODE: 自動で team-implement に戻り1回リトライ

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

TASK_FILE の `status` を `done` に更新。

---

## 状態管理

以下を変数として保持し、全フェーズに渡す:

| 変数 | 設定タイミング |
|------|---------------|
| `tier` | STEP 0 |
| `LINEAR_ID` | STEP 1 |
| `TASK_FILE` | STEP 2 |

---

## DONT-ASK MODE

| 通常の確認 | DONT-ASK 時の動作 |
|-----------|------------------|
| tier 上書き確認 | 判定結果をそのまま使用 |
| Gate 1 承認 | 自動承認 |
| Gate 3 FAIL 時 | 自動で team-implement に戻り1回リトライ |

---

$ARGUMENTS
