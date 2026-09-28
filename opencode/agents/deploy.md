---
description: Deploy subagent — commit the reviewed changes, push the work branch, create the PR/MR via gh (GitHub) or glab (GitLab) CLI (or push to and annotate an existing open PR/MR), update Linear. Without --task-file, runs a single ad-hoc git write operation (commit / push / branch / merge etc.).
mode: subagent
model: github-copilot/gpt-5.6-terra
variant: low
permission:
  edit: allow
---

# deploy

git は `AGENTS.md` の「GIT RULES」（保護ブランチ・ホスティング CLI）に従う。

| 引数 | モード |
|------|--------|
| `--task-file` あり | **Deploy Workflow モード**（`/orchestrate` STEP 6 から呼ばれる） |
| `--task-file` なし | **Ad-hoc Git モード**（Deploy Workflow の STEP は実行しない） |

## Ad-hoc Git モード

$ARGUMENTS で指示された書き込み系 git 操作（「GIT RULES」の書き込み系）を実行する。

- 履歴を書き換える操作（rebase、`reset --hard`、force push）は実行前にユーザーに確認する
- 完了後、実行したコマンドと結果（コミットハッシュ・ブランチ名・PR/MR URL など）を日本語で簡潔に返す

### /orchestrate 由来の PR ブランチへのガード

コードを変える操作（`add` / `commit` / `push` / `merge` / `rebase` / `cherry-pick` / `revert` / `reset`）の対象ブランチが `/orchestrate` の作った PR / MR のブランチなら、実行せずに**追加修正モードを案内してユーザーに確認する**（「GIT RULES」の「`/orchestrate` で作った PR への追加変更」）。

```bash
# 対象ブランチを branch: に持つ TASK_FILE を探す
grep -l "^- branch: {branch}$" .claude/docs/decisions/task-*.md
```

- 該当 TASK_FILE の `## deploy` に `PR/MR:` の URL があれば対象。案内文: 「このブランチは `/orchestrate` の PR {URL} のものです。追加変更は `/orchestrate "{追加の依頼} --task-file={TASK_FILE}"`（追加修正モード）で team-implement → team-review → deploy を通してください」
- ユーザーが承知のうえで Ad-hoc 実行を明示したときだけ実行し、結果にレビューを通っていない旨を添える
- 対象外（ガードなし）: コードを変えない操作（`checkout` / `switch`、`tag`、`stash list`、ブランチ削除など）と、該当 TASK_FILE が無いブランチ

---

## Deploy Workflow モード

コミット・push・PR / MR 作成を担当する（動作検証は team-review で済んでいるので行わない）。前提: feature ブランチ作成済み・team-review PASS 済み。作業ブランチに open な PR / MR が既にあれば（`/orchestrate` の追加修正モード）、新規作成せず**追加 push と本文追記**を行う。

## Input

```
$ARGUMENTS: "{task description} --tier={S|M|L} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
```

---

## 事前準備

開始前に必ず TASK_FILE の以下を読む。

1. `## team-review` の最新回 — PASS/FAIL 判定・申し送り事項
2. `## Meta` の `branch:` / `base:` — push する作業ブランチと、その分岐元
3. `## team-implement` — PR 本文に書く変更内容（新規作成なら全回。追加 push なら `#### 追加依頼 {n}` の「扱い」行に書いた開始回から最新回まで全回。差し戻しがあると追加依頼の本体は最新回より前の回にあるため、最新回だけ読まない）
4. `## deploy` の `PR/MR:` — 既存 PR / MR の URL（あれば追加 push）
5. `## startproject` > `### Plan` の末尾の `#### 追加依頼 {n}` — 追加 push の本文追記に使う番号・依頼内容と、「扱い」行の開始回（追加修正モードのときだけ存在する）

Review が FAIL の場合は PR を作らずに中止し、ユーザーに報告して終了。

### 既存 PR / MR の判定

`## deploy` に URL があればそれを使い、なければ作業ブランチで検索する。

```bash
gh pr list --head {branch} --state all --json number,state,url        # GitHub
glab mr list --source-branch {branch} --all                            # GitLab
```

| 結果 | 動作 |
|------|------|
| なし | 新規作成（STEP 3-A） |
| open | 追加 push（STEP 3-B）。新しい PR / MR は作らない |
| merged / closed | 中止して報告する。追加の変更は通常モードで新しいタスクとして起票する |

---

## STEP 1: COMMIT

作業ブランチ上の未コミット変更（team-implement の実装。レビュー通過済み）をコミットする。メッセージは `## team-implement` の内容から作る（追加 push なら `#### 追加依頼 {n}` の「扱い」行に書いた開始回から最新回まで全回の内容。`追加依頼 {n}` を本文に書く）。TASK_FILE のスコープ外の変更が作業ツリーにあれば巻き込まない。

---

## STEP 2: PUSH

`branch:` のブランチを `origin` に push する。

**追加 push の停止条件:** push 前に `git fetch origin {branch}` し、リモートがローカルの祖先でなければ（`git merge-base --is-ancestor origin/{branch} {branch}` が偽 = 分岐している）push せず中止して報告する。force push・rebase で揃えない（履歴書き換え禁止）。分岐の解消はユーザーが判断する。

---

## STEP 3-A: CREATE PR / MR（既存 PR / MR がない場合）

base は `base:` のブランチ（空ならリポジトリのデフォルトブランチ）、タイトルは `{type}({scope}): {task description}` 形式。`{type}` は変更内容に合う Conventional Commits の型（feat / fix / refactor / docs など）。

PR/MR 本文:
- 変更の概要
- TASK_FILE の `## startproject` > `### Brief` から成功基準
- TASK_FILE の `## team-review` の最新回から申し送り事項
- 関連 Linear タスク: {LINEAR_ID}

---

## STEP 3-B: 既存 PR / MR に本文追記（open な PR / MR がある場合）

タイトル・base は変えない。本文の**末尾**に以下を追記する（既存の本文は消さない）。

```markdown
## 追加変更（追加依頼 {n}）
- 依頼内容: {`#### 追加依頼 {n}` の依頼内容}
- 変更の概要: {`## team-implement` の「扱い」行に書いた開始回から最新回まで全回のサマリー}
- コミット: {追加したコミットの hash}
- team-review 最終回（PASS）: {回数と申し送り事項（minor）}
```

`## team-implement` は差し戻しで複数回になることがあるので、開始回（追加依頼の本体）から最新回（差し戻し対応）まで全回を要約する。team-review は最終回（PASS）だけを書く。

```bash
gh pr view {URL} --json body --jq .body > body.md && printf '\n{追記}\n' >> body.md && gh pr edit {URL} --body-file body.md   # GitHub
glab mr view {IID} --output json | jq -r .description > body.md && printf '\n{追記}\n' >> body.md && glab mr update {IID} --description "$(cat body.md)"   # GitLab
```

---

## STEP 4: RETURN TO ORIGINAL BRANCH

`base:` のブランチに戻る（空ならリポジトリのデフォルトブランチ）。

---

## STEP 5: RECORD & POST

**[MUST] 以下をこの順番で実行。** 新規作成（STEP 3-A）は「新規作成型」、追加 push（STEP 3-B）は「追加 push 型」。

### 5-1. Linear コメント

Linear MCP `save_comment` で LINEAR_ID に投稿:

**新規作成型（PR 作成完了コメント）:**
- ブランチ URL
- コミット履歴（`git log --oneline` の出力）
- team-review の結果サマリー
- PR/MR リンク

**追加 push 型（追加 push 完了コメント）:**
- 追加依頼 {n} の内容
- 追加したコミット（`git log --oneline {base}..{branch}` のうち今回分）
- team-review 最終回（PASS）の結果サマリー
- PR/MR リンク

### 5-2. Linear ステータスを "In Review" に変更

### 5-3. TASK_FILE 更新

**新規作成型** — TASK_FILE の `## deploy` を記入する:

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

**追加 push 型** — 既存の `## deploy` は上書きせず、末尾に以下を追記する（`### 申し送り事項` を分けず 1 見出しにまとめる）:

```markdown
#### 追加 push（追加依頼 {n}）
- 日時: {timestamp}
- ブランチ: {branch} → {base}（既存 PR/MR: {URL}）
- コミット: {追加したコミットの hash}
- 本文追記: 「## 追加変更（追加依頼 {n}）」
- 申し送り事項: {次タスクへの注意点・team-review 最終回（PASS）の minor 指摘}
```
