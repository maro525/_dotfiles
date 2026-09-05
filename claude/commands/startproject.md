---
name: startproject
description: Project kickoff — understand codebase, research/design, return a plan payload. Read-only; the caller performs all writes. Called by /orchestrate with tier, task-file, linear-id.
context: fork
agent: Plan
model: best
color: red
allowed-tools: Read, Bash, Grep, Glob, AskUserQuestion, TodoWrite, mcp__linear-server__get_issue, mcp__firecrawl__firecrawl_search, mcp__firecrawl__firecrawl_scrape, mcp__firecrawl__firecrawl_map
---

# startproject

計画フェーズ（Phase 1–3）を担当。

**このコマンドは読み取り専用（`agent: Plan`）。**
Write / Edit / Agent は使えない。したがって以下は**自分では行わない**:

- TASK_FILE・CLAUDE.md への書き込み
- Linear へのコメント投稿
- サブエージェント（Agent ツール）の起動

成果物は最終レスポンスとして OUTPUT フォーマットで呼び出し元（`/orchestrate`）に返し、
**書き込みと Linear 投稿は呼び出し元が行う**。

`agent: Plan` では CLAUDE.md が自動ロードされない。共通ルール（Don't-Ask 等）が必要なら
`Read` で `$HOME/.claude/CLAUDE.md` とプロジェクトの `CLAUDE.md` を明示的に読む。

## Input

```
$ARGUMENTS の形式: "{task description} --tier={S|M|L} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
```

| 引数 | 説明 |
|---|---|
| `--tier` | orchestrator が判定済み。省略時は S |
| `--task-file` | orchestrator が作成済みのタスクファイルパス（Read のみ。書き込みは呼び出し元） |
| `--linear-id` | orchestrator が確認済みの Linear タスク ID |

---

## PHASE 1: UNDERSTAND

**担当: Claude Lead**

1. コードベースを Glob / Grep / Read で直接読む
   - 構造・主要モジュール・既存パターン・関連コード・テスト構造
   - git 履歴調査は Bash で直接実行する（`git log` / `git diff`）。Agent ツールは使えない

2. 要件ヒアリング
   - 目的・スコープ・技術要件・成功基準・最終デザイン
   - **DONT-ASK MODE:** 提供済み情報から推定して続行

3. プロジェクト概要書を作成
   - Current State / Goal / Scope / Constraints / Success Criteria
   - → OUTPUT の `BRIEF` に含める

4. 要件決定を記録用にまとめる
   - `[startproject] DECISION` エントリを要件ごとに1件
   - `[startproject] PRE` エントリを1件
   - → OUTPUT の `DECISION_LOG` に含める

---

## PHASE 2: RESEARCH & DESIGN

**以下のいずれかに該当する場合は tier に関係なく OpenCode に相談する:**
- $ARGUMENTS に「opencodeに相談」「opencode相談」「opencodeで設計」等のキーワードを含む

**それ以外は tier によって動作を切り替える。成果物はすべて OUTPUT の `DESIGN` に含める。ファイルは作成しない。**

Agent ツールが無いため、リサーチは**サブエージェント経由ではなく直接実行する**
（`context: fork` によりコンテキストはすでに隔離されている）。

### tier=S
スキップ → Phase 3 へ進む。

### tier=M
OpenCode に設計相談する。Bash から直接実行する:

```bash
# --agent plan と < /dev/null は必須。2>/dev/null は付けない。詳細は rules/tool-routing.md 参照
opencode run --agent plan -m github-copilot/gpt-5.6-sol "{question}" < /dev/null
```

- **バックグラウンド実行必須**（`run_in_background: true`）。込み入った質問は 10 分を超える
- バックグラウンドでは stdin が開いたままになるため `< /dev/null` を必ず付ける
- cwd は git リポジトリにする（非 git だと無言ハングする）
- 得られた設計方針を `DESIGN` に含める

### tier=L
二系統を **同時に開始**する（firecrawl の呼び出しと opencode のバックグラウンド起動を同一メッセージで出す）。

| 系統 | 実行方法 | 役割 |
|---|---|---|
| 一次情報 | firecrawl MCP（`firecrawl_search` → `firecrawl_scrape`） | 公式ドキュメント・リリースノートを出典 URL 付きで調査 |
| 実装知見 | `opencode run --agent plan -m github-copilot/gpt-5.6-sol "{question}" < /dev/null`（background Bash） | 設計上の勘所・落とし穴を調査 |

- 結果はファイルに保存せず、Claude Lead がメモリ内で統合して `DESIGN` にまとめる
- **食い違いは firecrawl の一次情報を優先**し、相違点を `DECISION_LOG` に残す
- Researcher / Architect teammate の並列起動・双方向通信は Agent ツールが無いため行わない

---

## PHASE 3: PLAN

**担当: Claude Lead**

1. TASK_FILE を Read し、Phase 1 / Phase 2 の結果と統合する

2. 実装タスクリストを作成する
   - 進捗管理用に `TodoWrite` を使ってよいが、フォーク終了時に消えるため
     **必ず OUTPUT の `PLAN` にテキストとして含める**

3. `CLAUDE.md` の Current Project セクション本文を作成する
   - Goal / Key files / Architecture / Decisions
   - → OUTPUT の `CLAUDE_MD_CURRENT_PROJECT` に含める（書き込みは呼び出し元）

4. Linear への計画完了コメント本文を作成する
   - → OUTPUT の `LINEAR_COMMENT` に含める（投稿は呼び出し元）
   - あわせて `[startproject] POST` エントリを `DECISION_LOG` に含める

5. 以下の基準で承認フローを自己判断する

### 承認フロー判断基準

**自動承認 → 呼び出し元へ即返す:**
- タスクの解釈が一意に定まっている
- 実装方針に選択肢がなく自明
- DONT-ASK MODE が有効

**Gate 1 発動 → ユーザー承認を待つ:**
- タスクの解釈が複数考えられる
- 実装方針に大きなトレードオフがある（例: 既存コード大幅変更 vs 新規作成）
- スコープが曖昧で確認が必要
- tier=L かつリスクが高い

Gate 1 発動時は `AskUserQuestion` で計画を日本語で提示し、**判断が必要な理由と選択肢を明示**して承認を求める。
承認されたら即呼び出し元へ制御を返す。差し戻しの場合はフィードバックをもとに計画を修正する。

---

## OUTPUT

**ファイルには一切書き込まない。以下のフォーマットを最終レスポンスとしてそのまま返す。**
呼び出し元（`/orchestrate` STEP 3-2 / 3-3）が各セクションを TASK_FILE・CLAUDE.md・Linear へ反映する。

```markdown
### BRIEF
（TASK_FILE の `Brief` セクションにそのまま貼れる本文）

### DECISION_LOG
- [startproject] DECISION: ...
- [startproject] PRE: ...
- [startproject] POST: ...

### DESIGN
（tier=M,L のみ。tier=S は N/A）

### CLAUDE_MD_CURRENT_PROJECT
（CLAUDE.md の Current Project セクションにそのまま貼れる本文）

### PLAN
1. ...
2. ...

### LINEAR_COMMENT
（Linear に投稿する計画完了コメント本文）

### GATE1
auto-approved | approved | revised
```

| OUTPUT セクション | 呼び出し元での反映先 | tier |
|---|---|---|
| `BRIEF` | TASK_FILE の `Brief` | 全 tier |
| `DECISION_LOG` | TASK_FILE の `Decision Log` に追記 | 全 tier |
| `DESIGN` | TASK_FILE の `Design` | M, L |
| `CLAUDE_MD_CURRENT_PROJECT` | プロジェクトの `CLAUDE.md` | 全 tier |
| `PLAN` | STEP 4（team-implement）へ引き渡し | 全 tier |
| `LINEAR_COMMENT` | Linear に投稿 | 全 tier |
