---
description: Project kickoff subagent — understand codebase, research/design, create plan. Writes Brief / Design / Plan under the startproject section of TASK_FILE.
mode: subagent
model: github-copilot/gpt-5.6-sol
variant: xhigh
permission:
  edit: allow
---

# startproject

計画フェーズ（Phase 1–3）を担当。TASK_FILE を SSoT として更新する。

## Input

```
$ARGUMENTS: "{task description} --tier={S|M|L} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
```

---

## PHASE 1: UNDERSTAND

1. コードベースを読む（構造・既存パターン・関連コード・テスト構造・git 履歴）

2. 要件ヒアリング
   - 目的・スコープ・技術要件・成功基準・最終デザイン

3. プロジェクト概要書を作成
   - Current State / Goal / Scope / Constraints / Success Criteria
   - ヒアリングで決まった要件は、その理由も添えて Scope / Constraints に書く

4. **[MUST]** TASK_FILE の `## startproject` > `### Brief` に概要書を書き込む

---

## PHASE 2: RESEARCH & DESIGN

**$ARGUMENTS に「設計相談」「セカンドオピニオン」等のキーワード → tier に関わらず subagent で並列設計相談。**

成果物はすべて TASK_FILE の `## startproject` > `### Design` に書き込む（外部ファイル不作成）。全 tier で書く。

`Design` に書く内容: 採用した方針とその理由 / 検討して却下した案 / 主要な変更ファイル。

設計相談は `task` tool で subagent を起動する（同モデル・別コンテキストで独立性を確保）。
外部リサーチは firecrawl MCP（`firecrawl_search` / `firecrawl_scrape`）を使う。

### tier=S
リサーチはしない。Phase 1 の理解から方針を1-2行で `Design` に書いて Phase 3 へ進む。

### tier=M
`task` tool で subagent を起動して設計相談:

- prompt: "{設計相談内容}"
- 期待: 設計方針案を返す

得られた設計方針を `Design` に書き込む。

### tier=L
Researcher と Architect を **並列起動**。

| ロール | ツール | 役割 |
|-------|-------|------|
| Researcher | firecrawl MCP | 外部ライブラリ・事例を調査（出典 URL を必ず添える） |
| Architect  | `task` tool（subagent） | 設計方針を策定 |

両者の成果を統合し、`Design` に書き込む。**食い違いは firecrawl の一次情報を優先**し、相違点と採用した方を `Design` に残す。

---

## PHASE 3: PLAN

1. 実装タスクリストを作成し、**[MUST]** TASK_FILE の `## startproject` > `### Plan` に書き込む（進捗管理に `todowrite` を使ってもよい）

2. **[MUST]** Linear MCP の `save_comment` で LINEAR_ID に計画完了コメント投稿

3. 以下の基準で承認フローを自己判断

### 承認フロー判断基準

**自動承認 → 呼び出し元へ即返す:**
- タスクの解釈が一意
- 実装方針に選択肢がなく自明

**Gate 1 発動 → ユーザー承認を待つ:**
- タスクの解釈が複数考えられる
- 実装方針に大きなトレードオフがある
- スコープが曖昧
- tier=L かつリスクが高い

Gate 1 発動時は計画を日本語で提示し、**判断が必要な理由と選択肢を明示**してユーザーに承認を求める。

