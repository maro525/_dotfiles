---
name: deploy
description: Deploy phase — push feature branch, create PR, return a deploy payload. The caller writes TASK_FILE and updates Linear. Called by /orchestrate with tier, task-file, linear-id. Without --task-file, runs a single ad-hoc git write operation (commit / push / branch / merge etc.).
context: fork
agent: general-purpose
model: haiku
color: orange
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, AskUserQuestion, TodoWrite, mcp__linear-server__get_issue
---

# deploy

## モード判定

| 引数 | モード |
|---|---|
| `--task-file` あり | **Deploy Workflow モード**（`/orchestrate` STEP 6 から呼ばれる。以下の Input 以降） |
| `--task-file` なし | **Ad-hoc Git モード**（下記。Input 以降の STEP は実行しない） |

## Ad-hoc Git モード

$ARGUMENTS で指示された書き込み系 git 操作（`$HOME/.claude/rules/tool-routing.md` の「Git Operations」の書き込み系）を実行する。

- `$HOME/.claude/rules/tool-routing.md` の「Git Operations」（保護ブランチ・ホスティング CLI）に従う
- 履歴を書き換える操作（rebase、`reset --hard`、force push）は実行前にユーザーに確認する
- 完了後、実行したコマンドと結果（コミットハッシュ・ブランチ名・PR/MR URL など）を日本語で簡潔に返す

---

## Deploy Workflow モード

push と PR / MR 作成を担当する（動作検証は team-review で済んでいるので行わない）。

**TASK_FILE への書き込みと Linear への投稿・ステータス変更は行わない。**
結果は OUTPUT フォーマットで呼び出し元（`/orchestrate` STEP 6）に返し、
TASK_FILE の更新・Linear コメント投稿・ステータス変更は呼び出し元が行う。
TASK_FILE は Read のみ（`## startproject` / `## team-implement` / `## team-review` の参照用）。

前提: feature ブランチ作成済み・/team-review 完了済み・PASS 判定済み。

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

開始前に必ず以下を読む。

1. TASK_FILE の `## team-review` の最新回 — PASS/FAIL 判定・申し送り事項を確認
2. TASK_FILE の `## Meta` の `branch:` — push する作業ブランチ
3. TASK_FILE の `## team-implement` — PR 本文に書く変更内容（複数回ある場合は全回）

Review が FAIL の場合は PR を作らずに中止し、ユーザーに報告して終了する。

---

## Git ルール

`$HOME/.claude/rules/tool-routing.md` の「Git Operations」（保護ブランチ・ホスティング CLI）に従う。

---

## STEP 1: PRE-PUSH VERIFICATION

未コミット変更がある場合はユーザーに確認する。

---

## STEP 2: PUSH

`branch:` のブランチを `origin` に push する。

---

## STEP 3: CREATE PR / MR

base は feature ブランチの分岐元ブランチ（不明ならリポジトリのデフォルトブランチ）、タイトルは `feat({scope}): {task description}` 形式。

PR/MR 本文に含める内容:
- 変更の概要
- TASK_FILE の `## startproject` > `### Brief` から成功基準
- TASK_FILE の `## team-review` から申し送り事項（minor指摘）
- 関連 Linear タスク: {LINEAR_ID}

---

## STEP 4: RETURN TO ORIGINAL BRANCH

作業開始前のブランチに戻る。不明な場合はリポジトリのデフォルトブランチ。

---

## STEP 5: OUTPUT を返す

以下のフォーマットを最終レスポンスとしてそのまま返す。

```markdown
### DEPLOY

#### PR / MR
- 作成日時: {timestamp}
- ブランチ: {branch} → {base}
- PR/MR: {PR/MR URL}

#### 申し送り事項
- 次タスクへの注意点
- team-review の minor 指摘（対応推奨）

### LINEAR_COMMENT
（Linear に投稿する PR 作成完了コメント本文。以下を含める）
- ブランチ URL
- コミット履歴（`git log --oneline` の出力）
- team-review の結果サマリー
- PR/MR リンク

### LINEAR_STATUS
In Review
```
