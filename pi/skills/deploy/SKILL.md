---
name: deploy
description: Deploy phase — push feature branch, create PR, update Linear. Called by /orchestrate with tier, task-file, linear-id. Use when the user mentions deploy, push, PR creation, or deployment.
user-invocable: true
argument-hint: "<task description> --tier=<S|M|L> --task-file=<path> --linear-id=<id>"
---

# deploy

デプロイフェーズを担当。前提: feature ブランチ作成済み・team-review 完了済み・PASS 判定済み。

## Input

```
$ARGUMENTS: "{task description} --tier={S|M|L} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
```

---

## 事前準備

デプロイ開始前に必ず以下を読む:

1. TASK_FILE の `Review` — PASS/FAIL 判定・申し送り事項を確認
2. TASK_FILE の `Implementation Notes` — 変更ファイル一覧・変更の性質を確認

Review が FAIL の場合はデプロイを中止し、ユーザーに報告して終了。

---

## STEP 1: PRE-PUSH VERIFICATION

```bash
git status
git branch --show-current
```

- 未コミット変更がある場合はユーザーに確認
- **DONT-ASK MODE:** 自動コミットして続行
  ```bash
  git add -A
  git commit -m "{変更内容から適切なメッセージを生成}"
  ```

---

## STEP 2: PUSH

```bash
git push -u origin feature/{feature-name}
```

コンフリクト時:
```bash
git rebase origin/main
git push --force-with-lease
```

---

## STEP 3: CREATE PR

PR 作成は `gh` CLI を使用。

```bash
gh pr create \
  --base main \
  --head feature/{feature-name} \
  --title "feat({scope}): {task description}" \
  --body "{PR本文}"
```

PR本文:
- 変更の概要
- TASK_FILE の `Brief` から成功基準
- TASK_FILE の `Review` から申し送り事項
- 関連 Linear タスク: {LINEAR_ID}

---

## STEP 4: デプロイ後検証

TASK_FILE の `Implementation Notes` で変更の性質を確認し、該当する検証を実行。

### ブラウザ表示系
agent-browser スキルで確認:
1. navigate で対象 URL を開く
2. screenshot でスクリーンショットを取得
3. 主要ページ・インタラクションを確認

### ロジック系
スモークテストを実行:
```bash
{smoke_test_command}  # PI.md を参照
```

---

## STEP 5: RETURN TO ORIGINAL BRANCH

```bash
git checkout {original-branch}
```

元ブランチ不明時は `main` にフォールバック。

---

## STEP 6: RECORD & POST

**[MUST] 以下をこの順番で実行。**

### 6-1. Linear デプロイ完了コメント
Linear に以下を投稿:
- feature ブランチ URL
- コミット履歴（`git log --oneline`）
- team-review の結果サマリー
- PR リンク

### 6-2. Linear ステータスを "In Review" に変更

```
1. list_issue_statuses で利用可能なステータス一覧を取得
2. "In Review" に該当するステータス ID を特定
3. save_issue でステータスを更新
```

### 6-3. TASK_FILE 更新

TASK_FILE の `Deploy` セクション:

```markdown
## Deploy

### デプロイ結果: SUCCESS

### 実行内容
- デプロイ日時: {timestamp}
- feature ブランチ: feature/{feature-name}
- PR: {PR URL}

### デプロイ後検証結果

#### ブラウザ確認（該当時）
- 確認した URL・ページ
- 問題点

#### スモークテスト（該当時）
- 実行コマンド
- 結果

### 申し送り事項
- 次タスクへの注意点
- team-review の minor 指摘（対応推奨）
```

TASK_FILE の `Meta.status` を `completed` に更新。
TASK_FILE の `Decision Log` に `[deploy] POST` エントリを追加。

---

## COMPLETION REPORT

ユーザーに日本語で報告:

```
## デプロイ完了

- feature ブランチ: feature/{feature-name}
- PR: {PR URL}
- 現在のブランチ: {current-branch}
- Linear: {LINEAR_ID} → In Review
```

---

## AD-HOC GIT MODE

$ARGUMENTS に `--task-file` が含まれない場合はアドホック git モードとして動作:

### Push-type（書き込み）
`git add`, `git commit`, `git push`, `git merge`, `git rebase`, `git cherry-pick`, `git tag`, `git stash pop/apply`, `git reset`, `git revert`

**main ブランチ保護:** Push-type 操作で main/master 上にいる場合は feature ブランチを自動作成してから実行。

### Pull-type（読み取り）
`git log`, `git diff`, `git show`, `git blame`, `git status`, `git branch` (一覧), `git pull`, `git fetch`, `git stash list/show`

ブランチ制限なし。
