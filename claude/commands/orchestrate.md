---
name: orchestrate
description: Project orchestrator — classify tier, create task file, run startproject → team-implement → team-review → deploy in sequence.
model: opus[1m]
color: green
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Agent, Skill, AskUserQuestion, TodoWrite, mcp__linear-server__get_issue, mcp__linear-server__save_issue, mcp__linear-server__save_comment, mcp__linear-server__list_issue_statuses
---

# orchestrate

プロジェクト全体のフローを管理する。各 command の実行・Gate 判定・状態管理を担当し、タスクの実行自体は各 command に委譲する。

## Input

```
$ARGUMENTS の形式: "{task description}"
例: "PROJ-573をやりたいです"
例: "カート機能にクーポン適用を追加する"
例（追加修正モード）: "レビュー指摘の型エラーを直す --task-file=.claude/docs/decisions/task-PROJ-573-coupon.md"
```

## 実行原則

**$ARGUMENTS を受け取ったら「モード判定」を行い、通常モードは STEP 0 から、追加修正モードは STEP 3F から開始する。追加の指示がない限り STEP 7 まで完走する。**

- 全 STEP を自律的に順番に実行する。報告・通知はするが応答を待たずに次へ進む
- 質問が必要なら質問し、回答を受け取ったら止まらず続行する
- **[MUST]** の付いたステップは、どの tier でもスキップしない
- Linear への投稿・ステータス変更に失敗したら、黙って飛ばさずユーザーに報告する
- orchestrate はメインのセッションで動き、各 command は fork（バックグラウンド）で動く。command を起動したら**完了通知で返却を受け取るまで次の手順に進まない**
- 各 command は TASK_FILE への書き込みと Linear への投稿をしない（startproject は Write / Edit を持たない）。OUTPUT フォーマットで返却するので、**書き込みと Linear 投稿は orchestrator が行う**。返却が OUTPUT フォーマットに従っていなければ、command に整形し直させてから書き込む
- git は `$HOME/.claude/rules/tool-routing.md` の「Git Operations」に従う

**原則として止まるのは以下の Gate のみ。** ただし各 command が途中でユーザーに確認を求めた場合（startproject の要件ヒアリングなど）は、それに従う。

| Gate | タイミング | 動作 |
|---|---|---|
| Gate 1 | startproject が計画提示時に自己判断で発動 | startproject 内でユーザー承認を待つ。orchestrate は返却を待つだけ |
| Gate 2 | team-review の FAIL 時 | ユーザーに報告し判断を待つ |

## モード判定

$ARGUMENTS を受け取ったら最初にモードを決め、判定結果（モードと TASK_FILE）をユーザーに報告して続行する。ユーザーが別のモードを指示したらそれに従う。

| モード | 判定 | 開始 STEP |
|---|---|---|
| **通常モード** | 下記に該当しない | STEP 0 |
| **追加修正モード** | (a) `--task-file={TASK_FILE}` で既存の `task-*.md` が指定された、または (b) Linear ID を検出し、`.claude/docs/decisions/task-{LINEAR_ID}-*.md` が存在する | STEP 3F |

- (b) で該当ファイルが複数あれば `AskUserQuestion` で選ばせる
- 追加修正モードは、`/orchestrate` が PR / MR を出したタスクに追加の変更（レビュー指摘への対応、仕様の追加など）を加えるときに使う。既存 PR への追加変更は必ずこのモードを通し、orchestrator が直接編集して push しない（`$HOME/.claude/rules/tool-routing.md` の「/orchestrate で作った PR への追加変更」）
- 呼び出し形: `/orchestrate "{追加の依頼} --task-file={TASK_FILE}"`（または `/orchestrate "{LINEAR_ID} {追加の依頼}"`）

## STEP 0: CLASSIFY

`$HOME/.claude/rules/adaptive-execution.md` の基準で tier を判定し、結果と根拠をユーザーに報告する。上書き指示がない限り即 STEP 1 へ進む。

**tier=XS の場合:** 直接実装を提案してここで終了する（STEP 1 以降は S / M / L のみ）。

## STEP 1: LINEAR タスク確認

$ARGUMENTS から Linear ID（例: `PROJ-573`）を検出する。

- **検出できた場合:** LINEAR_ID として使用（確認不要）。`mcp__linear-server__get_issue` でタスク詳細を取得してタスク説明を補完し、即 STEP 2 へ
- **検出できなかった場合:** ユーザーに Linear タスク ID または URL を質問する。既存タスクがあれば ID を取得、なければ `mcp__linear-server__save_issue` で新規作成し、即 STEP 2 へ

```
LINEAR_ID = "XXX-123"
```

## STEP 2: タスクファイル作成

以下のパスにタスクファイルを作成して即 STEP 3 へ進む。feature は LINEAR_ID のタスク内容から短いスネークケースで命名する。

```
TASK_FILE = .claude/docs/decisions/task-{LINEAR_ID}-{feature}.md
```

**初期テンプレート:**

```markdown
# Task: {LINEAR_ID} — {task description}

## Meta
- linear_id: {LINEAR_ID}
- tier: {tier}
- created: {timestamp}
- status: planning
- branch:
- base:

## startproject
### Brief
<!-- orchestrator が startproject の返却 BRIEF から記入 -->

### Design
<!-- orchestrator が startproject の返却 DESIGN から記入 -->

### Plan
<!-- orchestrator が startproject の返却 PLAN から記入 -->

## team-implement
<!-- orchestrator が team-implement の返却 IMPLEMENTATION_NOTES から記入 -->

## team-review
<!-- orchestrator が team-review の返却 REVIEW から記入 -->

## deploy
<!-- orchestrator が deploy の返却 DEPLOY から記入 -->
```

`##` 見出しはプロセス名で固定する（kanban がこの見出しでフェーズを判定する）。

## STEP 3: startproject を実行

```
/startproject "{task description} --tier={tier} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
```

startproject は `agent: Plan` の読み取り専用コマンド。`BRIEF` / `DESIGN` / `PLAN` / `LINEAR_COMMENT` / `GATE1` を返してくる。途中の質問にはユーザーが回答し、計画完成後に返却される。

**[MUST]** 返却内容を TASK_FILE に書き込む:

| OUTPUT セクション | 書き込み先 |
|---|---|
| `BRIEF` | `## startproject` > `### Brief` |
| `DESIGN` | `## startproject` > `### Design` |
| `PLAN` | `## startproject` > `### Plan` |

**[MUST]** `LINEAR_COMMENT` の本文を `mcp__linear-server__save_comment` で LINEAR_ID に投稿する。

**Gate 1:** startproject が自己判断で発動し、ユーザーの承認（または修正）が済んでから返却してくる（詳細は startproject.md）。`GATE1`（`auto-approved` / `approved` / `revised`）の値に関わらず即 STEP 4 へ進み、値は STEP 7 の完了報告に含める。

## STEP 3F: 追加修正モード

通常モードの STEP 0〜3 の代わりに実行し、STEP 4 に合流する。追加依頼も team-implement → team-review → deploy を必ず通す（orchestrator が直接編集して push しない）。F1〜F5 を順に実行し、途中で止まるのは前提不成立のときだけ。

### F1: TASK_FILE を読む

指定された TASK_FILE から以下を読み、「状態管理」の変数を復元する。

| 読む場所 | 復元するもの |
|---|---|
| `# Task: {LINEAR_ID} — {task description}`（先頭行） | 元の task description |
| `## Meta` の `linear_id:` / `tier:` / `status:` / `branch:` / `base:` | `LINEAR_ID` / `tier` / 前提確認の材料 |
| `## deploy` の `PR/MR:` | 既存 PR / MR の URL |
| `## startproject` > `### Plan` の `#### 追加依頼 {n}` | 追加依頼の通し番号 n（既存の最大 + 1 を次の n にする） |
| `## team-implement` / `## team-review` の `### {m}回目` | 実装・レビューの回数 m（既存の最大 + 1 を次の m にする） |

n と m は独立に数える（差し戻しで m だけ増えることがある）。

### F2: 前提確認

以下をすべて満たすときだけ続行する。読み取り系なので orchestrator が直接実行してよい。

| 条件 | 確認方法 |
|---|---|
| `status` が `in-review` | `## Meta` |
| `branch:` が空でない | `## Meta` |
| `## deploy` に PR / MR URL がある | `## deploy` の `PR/MR:` |
| その PR / MR が open | GitHub: `gh pr view {URL} --json state --jq .state` が `OPEN` ／ GitLab: `glab mr view {IID} --output json` の `state` が `opened`（IID は URL 末尾の番号） |

不成立なら理由別に案内して終了する（STEP 4 以降は実行しない）。

| 不成立の理由 | 案内 |
|---|---|
| `status` が `planning` / `implementing` / `reviewing` / `deploying` | 通常フローの途中で止まっている。該当 STEP から再開するかユーザーに確認する |
| `status` が `done`、または PR / MR が merged / closed | 既存 PR には追加できない。通常モードで新しいタスクとして起票するか確認し、了承なら STEP 0 から実行する |
| `branch:` が空、または `## deploy` に URL がない | deploy が済んでいない。STEP 6 から再開するかユーザーに確認する |

### F3: 規模判定

追加依頼**単体**を `$HOME/.claude/rules/adaptive-execution.md` の基準で見る。以下のいずれかに当たれば「再設計」、それ以外は「そのまま追加」とし、判定と根拠をユーザーに報告して続行する。

- 元の `tier` より上になる
- Hard Trigger に当たる
- `### Design` の「採用した方針」を変える
- 独立した機能を複数含む

**再設計の場合**（STEP 4 のエスカレーションと同形）:

1. `tier` 変数と `## Meta` の `tier:` を更新する（`status` はこの時点では変えない）
2. F4 で `#### 追加依頼 {n}` を追記する
3. 新しい tier で STEP 3 を実行し、返却で `## startproject` を上書きする（Brief / Design / Plan は追加依頼を含めて書き直させる）
4. 上書き後の `### Plan` 末尾に `#### 追加依頼 {n}` を再掲し、F5 へ進む。書き直した Plan には追加依頼が含まれるので、再掲時は F4 テンプレートの前提行を次に差し替える（そのまま再掲すると「この追加依頼だけを実装する」が新 Plan と矛盾し、再設計部分の実装が飛ばされる）:
   `- 前提: 上の Plan のうち既存 PR で実装済みの部分を除いて実装する（この追加依頼を含む再設計分が対象）`

### F4: 追加依頼を記録

`### Plan` の末尾に以下を追記する（既存の Plan は消さない。`#### 追加依頼` は kanban の見出し判定に影響しない）。

```markdown
#### 追加依頼 {n}
- 依頼日時: {timestamp}
- 依頼内容: {追加の依頼}
- 対象: {変更するファイル・機能の見込み}
- 既存 PR: {PR/MR URL}
- 扱い: team-implement / team-review の {m}回目
- 前提: 上の Plan は既存 PR で実装済み。この追加依頼だけを実装する
```

前提行は「そのまま追加」のときの文言。F3 で再設計した場合は F3 の手順 4 の文言に差し替える。

以降の task description は `"{元の task description}（追加依頼 {n}: {追加の依頼}）"` とする。

### F5: STEP 4 へ

「状態管理」に従い `status` を `implementing` に戻し、Linear を "In Progress" にして STEP 4 を実行する。STEP 4 → 5 → 6 → 7 は通常モードと同じ（実装・レビューは `{m}回目` として追記。STEP 6 は既存 PR / MR へ追加 push する。Gate 2 の差し戻しも同じ）。

> **kanban の副作用:** `## deploy` が埋まった TASK_FILE の `status` を `implementing` に戻すため、追加修正中は kanban が deploy 列に stale（status が古い）として表示する。仕様として許容する。STEP 7 で `in-review` に戻ると解消する。

## STEP 4: team-implement を実行

開始時に「状態管理」に従い TASK_FILE の `status` と Linear のステータスを更新する。**完了次第即 STEP 5 へ進む。**

```
/team-implement "{task description} --tier={tier} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
```

team-implement はコードと git 操作のみ行い、`IMPLEMENTATION_NOTES` / `LINEAR_COMMENT` / `BRANCH` / `BASE` / `ESCALATION` を返してくる。

**[MUST]** 返却内容を TASK_FILE に書き込む:

| OUTPUT セクション | 書き込み先 |
|---|---|
| `IMPLEMENTATION_NOTES` | `## team-implement` に `### {m}回目` として追記 |
| `BRANCH` | `## Meta` の `branch:` |
| `BASE` | `## Meta` の `base:` |

`{m}` は実装・レビューの回数（`## team-implement` の既存の最大 + 1。初回は `### 1回目`）。`{n}` は追加依頼の通し番号にだけ使う（STEP 3F）。

**[MUST]** `LINEAR_COMMENT` の本文を `mcp__linear-server__save_comment` で LINEAR_ID に投稿する。

**エスカレーション:** 返却に `ESCALATION` がある場合（team-implement が tier の引き上げで中断した）:

1. ユーザーに新しい tier と理由を報告する
2. `tier` 変数と `## Meta` の `tier:` を更新する（`status` は `implementing` のまま。`planning` に戻すと kanban が「status が古い」と警告する）
3. 新しい tier で STEP 3 からやり直し、startproject の返却で `## startproject` を上書きする。作業ブランチ上の変更はそのまま引き継ぐ

**完了確認:** `ESCALATION` がなく、`## team-implement` が埋まっていることを確認してから STEP 5 へ進む。

## STEP 5: team-review を実行

```
/team-review "{task description} --tier={tier} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
```

team-review は `VERDICT` / `REVIEW` / `LINEAR_COMMENT` を返してくる。

**[MUST]** 返却内容を TASK_FILE に書き込む:

| OUTPUT セクション | 書き込み先 |
|---|---|
| `REVIEW` | `## team-review` に `### {m}回目` として追記 |

**FAIL の場合も必ず書き込む**（差し戻し履歴を残すため）。Gate 2 で STEP 4 に戻ったら、次の実装・レビューは m+1 回目として追記する（上書きしない）。

**[MUST]** `LINEAR_COMMENT` の本文を `mcp__linear-server__save_comment` で LINEAR_ID に投稿する。

**Gate 2:** `VERDICT` が `PASS` なら即 STEP 6 へ。`FAIL` ならユーザーに報告し判断を待ち、team-implement に戻るか確認する。

## STEP 6: deploy を実行

**完了次第即 STEP 7 へ進む。**

```
/deploy "{task description} --tier={tier} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
```

deploy はコミット・push・PR / MR 作成（既存の PR / MR があれば追加 push と本文追記）のみ行い、`DEPLOY` / `LINEAR_COMMENT` を返してくる。

**[MUST]** 返却内容を TASK_FILE に書き込む:

| OUTPUT セクション | 書き込み先 |
|---|---|
| `DEPLOY` | `## deploy`。**追加修正モードでは上書きせず**、返却の `#### 追加 push（追加依頼 {n}）` を `## deploy` の末尾に追記する |

**[MUST]** `LINEAR_COMMENT` を投稿し、Linear のステータスを「状態管理」に従って変更する。

## STEP 7: 完了報告

ユーザーに日本語で最終サマリーを報告する。

```
## 完了: {task description}

- Linear: {LINEAR_ID}
- Tier: {tier}
- Task File: {TASK_FILE}
- Mode: 通常 | 追加修正（追加依頼 {n}、{m}回目）

### 各フェーズのサマリー
- startproject: ...（Gate 1: {GATE1}）
- team-implement: ...
- team-review: ...
- deploy: ...
```

追加修正モードでは startproject 行を「（追加修正モード: スキップ）」または再設計時の結果にし、deploy 行に既存 PR / MR の URL を書く。

## 状態管理

orchestrator は以下を変数として保持し、全 command に引数で渡す。

| 変数 | 設定タイミング |
|---|---|
| `tier` | STEP 0（追加修正モードは STEP 3F F1 で `## Meta` の `tier:` から復元。F3 の再設計で更新） |
| `LINEAR_ID` | STEP 1（追加修正モードは STEP 3F F1 で `## Meta` の `linear_id:` から復元） |
| `TASK_FILE` | STEP 2（追加修正モードは $ARGUMENTS または Linear ID から特定） |

作業ブランチとその分岐元は、引数ではなく TASK_FILE の `## Meta` の `branch:` / `base:` で受け渡す（STEP 4 で記入。追加修正モードでは既存の値をそのまま使う）。

### TASK_FILE の `status` と Linear ステータス

各 STEP の開始時に `## Meta` の `status` を更新する（Gate 2 で STEP 4 に戻った場合も `implementing` に戻す）。`done` には orchestrator はしない。PR がマージされた後に人間が変更する。

| タイミング | TASK_FILE `status` | Linear ステータス |
|---|---|---|
| STEP 2（作成時） | `planning` | — |
| STEP 3F F5（追加修正の開始 = STEP 4 開始と同じ） | `implementing` | "In Progress" |
| STEP 4 開始 | `implementing` | "In Progress" |
| STEP 5 開始 | `reviewing` | — |
| STEP 6 開始 | `deploying` | — |
| STEP 6（deploy 返却後） | — | "In Review" |
| STEP 7 | `in-review`（PR を出してマージ待ち） | — |
