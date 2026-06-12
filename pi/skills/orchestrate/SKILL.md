---
name: orchestrate
description: Main project orchestrator. Classifies task tier, creates task file, runs startproject → team-implement → team-review → deploy in sequence. Use when the user wants to start a full project workflow, mentions Linear task IDs, or says orchestrate.
user-invocable: true
argument-hint: "<task description or Linear ID>"
---

# orchestrate

プロジェクト全体のフローを管理する。各フェーズの実行・Gate 判定・状態管理を担当。タスクの実行自体は各サブエージェントに委譲する。

## Input

```
$ARGUMENTS: "{task description}"
例: "NSKETCH-573をやりたいです"
例: "カート機能にクーポン適用を追加する"
```

## 実行原則

- 全フェーズを自律的に順番に実行する
- 報告・通知はするが、応答を待たずに次のフェーズへ進む
- 追加の指示がない限り STEP 7 まで完走する

**止まるのは以下の Gate のみ:**
| Gate | タイミング | 動作 |
|---|---|---|
| Gate 1 | startproject の計画提示後 | ユーザー承認を待つ |
| Gate 3 | team-review の FAIL 時 | ユーザーに報告し判断を待つ |

## Git 共通ルール（全フェーズ）

- ホスティングに応じて CLI を使い分ける: GitLab → `glab` / GitHub → `gh`（`git remote get-url origin` で判定）
- **保護ブランチ `release` / `staging` / `main`（master 含む）への直接コミット・push は、ユーザーの明示的な許可がない限り禁止**。反映は必ず PR / MR 経由
- 保護ブランチ上で作業を始める場合は feature ブランチを作成してから実装する（tier=XS も同様）

---

## STEP 0: CLASSIFY

タスクの規模・複雑さ・リスクから tier を判定する。

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

## STEP 1: Linear タスク確認

$ARGUMENTS から Linear ID パターン `[A-Z]+-[0-9]+` を検出する。

**ID が検出できた場合:** LINEAR_ID として使用。即 STEP 2 へ。

**ID が検出できなかった場合:** ユーザーに Linear タスク ID またはタスク内容を質問する。

---

## STEP 2: タスクファイル作成

```
TASK_FILE = .claude/docs/decisions/task-{LINEAR_ID}-{feature}.md
```

feature は LINEAR_ID のタスク内容から短いスネークケースで命名する。

テンプレート:

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

**tier=S,M,L のみ実行。**

startproject スキルを呼び出す:
```
{task description} --tier={tier} --task-file={TASK_FILE} --linear-id={LINEAR_ID}
```

startproject 内で質問が発生した場合はユーザーが回答する。

**Gate 1:** startproject が自己判断して発動。
- 自動承認 → 即 STEP 4
- Gate 1 発動 → ユーザーに承認を求め、承認後 STEP 4
- 差し戻し → フィードバックをもとに計画修正

---

## STEP 4: team-implement を実行

**全 tier で実行。** team-implement スキルを呼び出す:
```
{task description} --tier={tier} --task-file={TASK_FILE} --linear-id={LINEAR_ID}
```

| tier | 動作 |
|---|---|
| XS | 直接実装。ただし保護ブランチ（release/staging/main）上にいる場合は feature ブランチを作成 |
| S | feature ブランチ。直接実装 |
| M | feature ブランチ。1-2 subagent で並列実装 |
| L | feature ブランチ。フルチーム（モジュール単位オーナーシップ） |

完了後、TASK_FILE の `Implementation Notes` が埋まっていることを確認して STEP 5 へ。

---

## STEP 5: team-review を実行

**tier=XS はスキップして即 STEP 6 へ。**

team-review スキルを呼び出す:
```
{task description} --tier={tier} --task-file={TASK_FILE} --linear-id={LINEAR_ID}
```

| tier | レビュー方式 |
|---|---|
| XS | スキップ |
| S | self-review（単独レビュー） |
| M | 2レビュアー |
| L | 4レビュアー（Quality / Logic / Security / Simplify） |

**Gate 3:**
- PASS → 即 STEP 6
- FAIL → ユーザーに報告し判断を待つ

---

## STEP 6: deploy を実行

deploy スキルを呼び出す:
```
{task description} --tier={tier} --task-file={TASK_FILE} --linear-id={LINEAR_ID}
```

---

## STEP 7: 完了報告

ユーザーに日本語で最終サマリーを報告:

```markdown
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

TASK_FILE の `Meta.status` を `completed` に更新する。

---

## 状態管理

orchestrator は以下を変数として保持し、全フェーズに渡す:

| 変数 | 設定タイミング |
|---|---|
| `tier` | STEP 0 |
| `LINEAR_ID` | STEP 1 |
| `TASK_FILE` | STEP 2 |
