---
name: deploy
description: Deploy phase — push feature branch, create PR, return a deploy payload. The caller writes TASK_FILE and updates Linear. Called by /orchestrate with tier, task-file, linear-id. Without --task-file, runs a single ad-hoc git write operation (commit / push / branch / merge etc.).
context: fork
agent: general-purpose
model: haiku
color: orange
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Skill, AskUserQuestion, TodoWrite, mcp__linear-server__get_issue
---

# deploy

## モード判定

| 引数 | モード |
|---|---|
| `--task-file` あり | **Deploy Workflow モード**（`/orchestrate` STEP 6 から呼ばれる。以下の Input 以降） |
| `--task-file` なし | **Ad-hoc Git モード**（下記。Input 以降の STEP は実行しない） |

## Ad-hoc Git モード

$ARGUMENTS で指示された書き込み系 git 操作（add / commit / push / pull / merge / rebase / cherry-pick / tag 作成 / stash pop・apply / reset / revert / branch 作成・checkout・switch）を実行する。

- `$HOME/.claude/rules/tool-routing.md` の「Git Operations」（保護ブランチ・ホスティング CLI）に従う
- 履歴を書き換える操作（rebase、`reset --hard`、force push）は実行前にユーザーに確認する
- 完了後、実行したコマンドと結果（コミットハッシュ・ブランチ名・PR/MR URL など）を日本語で簡潔に返す

---

## Deploy Workflow モード

デプロイフェーズを担当。push / PR・MR 作成・デプロイ後検証は自分で行う。

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

デプロイ開始前に必ず以下を読む。

1. TASK_FILE の `## team-review` — PASS/FAIL 判定・申し送り事項を確認
2. TASK_FILE の `## team-implement` — 変更ファイル一覧・変更の性質を確認

Review が FAIL の場合はデプロイを中止し、ユーザーに報告して終了する。

---

## Git ルール

`$HOME/.claude/rules/tool-routing.md` の「Git Operations」（保護ブランチ・ホスティング CLI）に従う。

---

## STEP 1: PRE-PUSH VERIFICATION

未コミット変更がある場合はユーザーに確認する。

---

## STEP 2: PUSH

feature ブランチを `origin` に push する。

---

## STEP 3: CREATE PR / MR

base は feature ブランチの分岐元ブランチ（不明ならリポジトリのデフォルトブランチ）、タイトルは `feat({scope}): {task description}` 形式。

PR/MR 本文に含める内容:
- 変更の概要
- TASK_FILE の `## startproject` > `### Brief` から成功基準
- TASK_FILE の `## team-review` から申し送り事項（minor指摘）
- 関連 Linear タスク: {LINEAR_ID}

---

## STEP 4: デプロイ後検証

TASK_FILE の `## team-implement` で変更の性質を確認し、該当する検証を実行する。

### ブラウザ表示系の変更が含まれる場合
ブラウザで主要ページ・インタラクションを確認し、スクリーンショットを記録する。使うツールは問わない。

### ロジック系の変更が含まれる場合
プロジェクトの CLAUDE.md に記載のスモークテストを実行する。

---

## STEP 5: RETURN TO ORIGINAL BRANCH

作業開始前のブランチに戻る。不明な場合はリポジトリのデフォルトブランチ。

---

## STEP 6: OUTPUT を返す

以下のフォーマットを最終レスポンスとしてそのまま返す。

```markdown
### DEPLOY

#### デプロイ結果: SUCCESS

#### 実行内容
- デプロイ日時: {timestamp}
- feature ブランチ: feature/{feature-name}
- PR/MR: {PR/MR URL}

#### デプロイ後検証結果

##### ブラウザ確認（該当する場合）
- 確認した URL・ページ
- 問題点（あれば）

##### スモークテスト（該当する場合）
- 実行コマンド
- 結果

#### 申し送り事項
- 次タスクへの注意点
- team-review の minor 指摘（対応推奨）

### LINEAR_COMMENT
（Linear に投稿するデプロイ完了コメント本文。以下を含める）
- feature ブランチ URL
- コミット履歴（`git log --oneline` の出力）
- team-review の結果サマリー
- PR/MR リンク

### LINEAR_STATUS
In Review
```
