---
name: deploy
description: Deploy phase — push feature branch, create PR, update Linear. Called by /orchestrate with tier, task-file, linear-id.
context: fork
agent: Bash
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, AskUserQuestion, TodoWrite, mcp__linear-server__save_comment, mcp__linear-server__get_issue, mcp__linear-server__save_issue, mcp__linear-server__list_issue_statuses, mcp__agent-browser__navigate, mcp__agent-browser__screenshot, mcp__agent-browser__click, mcp__agent-browser__type
---

# deploy

デプロイフェーズを担当。
タスクファイル・Decision Log・Linear・Don't-Ask の共通ルールは CLAUDE.md 参照。

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

デプロイ開始前に必ず以下を読む。

1. TASK_FILE の `Review` セクション — PASS/FAIL 判定・申し送り事項を確認
2. TASK_FILE の `Implementation Notes` セクション — 変更ファイル一覧・変更の性質を確認

Review が FAIL の場合はデプロイを中止し、ユーザーに報告して終了する。

---

## STEP 1: PRE-PUSH VERIFICATION

```bash
git status
git branch --show-current
```

- 未コミット変更がある場合はユーザーに確認
- **DONT-ASK MODE:** 未コミット変更は自動コミットして続行
  ```bash
  git add -A
  git commit -m "{変更内容から適切なメッセージを生成}"
  ```

---

## STEP 2: PUSH

```bash
git push -u origin feature/{feature-name}
```

コンフリクトが発生した場合:
```bash
git rebase origin/main
git push --force-with-lease
```

---

## STEP 3: CREATE PR

PR 作成は `gh CLI` を使用する（GitHub MCP は不安定なため使わない）。

```bash
gh pr create \
  --base main \
  --head feature/{feature-name} \
  --title "feat({scope}): {task description}" \
  --body "{PR本文}"
```

PR本文に含める内容:
- 変更の概要
- TASK_FILE の `Brief` から成功基準
- TASK_FILE の `Review` から申し送り事項（minor指摘）
- 関連 Linear タスク: {LINEAR_ID}

---

## STEP 4: デプロイ後検証

TASK_FILE の `Implementation Notes` で変更の性質を確認し、該当する検証を実行する。

### ブラウザ表示系の変更が含まれる場合
agent-browser で確認する。

```
1. mcp__agent-browser__navigate で対象 URL を開く
2. mcp__agent-browser__screenshot でスクリーンショットを取得
3. 主要ページ・インタラクションを確認
```

### ロジック系の変更が含まれる場合
スモークテストを実行する。

```bash
# CLAUDE.md のスモークテストコマンドを参照
{smoke_test_command}
```

---

## STEP 5: RETURN TO ORIGINAL BRANCH

```bash
git checkout {original-branch}
```

元ブランチが不明な場合は `main` にフォールバック。

---

## STEP 6: RECORD & POST

**[MUST] 以下を必ずこの順番で実行する。**

### 6-1. Linear にデプロイ完了コメントを投稿

`mcp__linear-server__save_comment` で LINEAR_ID に以下を含むコメントを投稿:
- feature ブランチ URL
- コミット履歴（`git log --oneline` の出力）
- team-review の結果サマリー
- PR リンク

### 6-2. Linear ステータスを "In Review" に変更

```
1. mcp__linear-server__list_issue_statuses で利用可能なステータス一覧を取得
2. "In Review" に該当するステータス ID を特定
3. mcp__linear-server__save_issue でステータスを更新
```

### 6-3. タスクファイルを更新

TASK_FILE の `Deploy` セクションに以下を記入する:

```markdown
## Deploy

### デプロイ結果: SUCCESS

### 実行内容
- デプロイ日時: {timestamp}
- feature ブランチ: feature/{feature-name}
- PR: {PR URL}

### デプロイ後検証結果

#### ブラウザ確認（該当する場合）
- 確認した URL・ページ
- 問題点（あれば）

#### スモークテスト（該当する場合）
- 実行コマンド
- 結果

### 申し送り事項
- 次タスクへの注意点
- team-review の minor 指摘（対応推奨）
```

TASK_FILE の `Meta` の `status` を `completed` に更新する。
TASK_FILE の `Decision Log` に `[deploy] POST` エントリを追加する。

---

## COMPLETION REPORT

ユーザーに日本語で以下を報告する。

```
## デプロイ完了

- feature ブランチ: feature/{feature-name}
- PR: {PR URL}
- 現在のブランチ: {current-branch}
- Linear: {LINEAR_ID} → In Review
```

---

## DONT-ASK MODE

| 通常の確認 | DONT-ASK 時の動作 |
|---|---|
| 未コミット変更の確認 | 自動コミットして続行 |
| tier=L 本番デプロイ承認 | 自動承認 |
| ブラウザ確認の要否判断 | UI 変更が含まれれば自動実行 |
| スモークテストの要否判断 | ロジック変更が含まれれば自動実行 |
| 元ブランチ不明 | main にフォールバック |
| デプロイ完了報告 | 結果を呼び出し元へそのまま返す |
