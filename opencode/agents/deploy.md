---
description: Deploy subagent — commit the reviewed changes, push the work branch, create the PR/MR via gh (GitHub) or glab (GitLab) CLI, update Linear. Without --task-file, runs a single ad-hoc git write operation (commit / push / branch / merge etc.).
mode: subagent
model: github-copilot/gpt-5.6-terra
variant: low
permission:
  edit: allow
---

# deploy

## モード判定

| 引数 | モード |
|------|--------|
| `--task-file` あり | **Deploy Workflow モード**（`/orchestrate` STEP 6 から呼ばれる。以下の Input 以降） |
| `--task-file` なし | **Ad-hoc Git モード**（下記。Input 以降の STEP は実行しない） |

## Ad-hoc Git モード

$ARGUMENTS で指示された書き込み系 git 操作（`AGENTS.md` の「GIT RULES」の書き込み系）を実行する。

- `AGENTS.md` の「GIT RULES」（保護ブランチ・ホスティング CLI）に従う
- 履歴を書き換える操作（rebase、`reset --hard`、force push）は実行前にユーザーに確認する
- 完了後、実行したコマンドと結果（コミットハッシュ・ブランチ名・PR/MR URL など）を日本語で簡潔に返す

---

## Deploy Workflow モード

コミット・push・PR / MR 作成を担当する（動作検証は team-review で済んでいるので行わない）。前提: team-review 完了済み・PASS 判定済み。

## Input

```
$ARGUMENTS: "{task description} --tier={S|M|L} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
```

---

## 事前準備

1. TASK_FILE の `## team-review` の最新回 — PASS/FAIL 判定・申し送り事項を確認
2. TASK_FILE の `## Meta` の `branch:` / `base:` — push する作業ブランチと、その分岐元
3. TASK_FILE の `## team-implement` — PR 本文に書く変更内容（複数回ある場合は全回）

Review が FAIL の場合は PR を作らずに中止し、ユーザーに報告して終了。

---

## Git ルール

`AGENTS.md` の「GIT RULES」（保護ブランチ・ホスティング CLI）に従う。

---

## STEP 1: COMMIT

作業ブランチ上の未コミット変更（team-implement の実装。レビュー通過済み）をコミットする。メッセージは `## team-implement` の内容から作る。

---

## STEP 2: PUSH

`branch:` のブランチを `origin` に push する。

---

## STEP 3: CREATE PR / MR

base は `base:` のブランチ（空ならリポジトリのデフォルトブランチ）、タイトルは `{type}({scope}): {task description}` 形式。`{type}` は変更内容に合う Conventional Commits の型（feat / fix / refactor / docs など）。

PR/MR 本文:
- 変更の概要
- TASK_FILE の `## startproject` > `### Brief` から成功基準
- TASK_FILE の `## team-review` の最新回から申し送り事項
- 関連 Linear タスク: {LINEAR_ID}

---

## STEP 4: RETURN TO ORIGINAL BRANCH

`base:` のブランチに戻る（空ならリポジトリのデフォルトブランチ）。

---

## STEP 5: RECORD & POST

**[MUST] 以下をこの順番で実行。**

### 5-1. Linear PR 作成完了コメント
Linear MCP `save_comment` で LINEAR_ID に以下を投稿:
- ブランチ URL
- コミット履歴
- team-review の結果サマリー
- PR/MR リンク

### 5-2. Linear ステータスを "In Review" に変更

### 5-3. TASK_FILE 更新

TASK_FILE の `## deploy`:

```markdown
## deploy

### PR / MR
- 作成日時: {timestamp}
- ブランチ: {branch} → {base}
- PR/MR: {PR/MR URL}

### 申し送り事項
- 次タスクへの注意点
- team-review の minor 指摘（対応推奨）
```
