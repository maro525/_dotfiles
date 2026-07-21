---
description: Project kickoff subagent — understand codebase, research/design, create plan. Writes Brief / Design / Decision Log to TASK_FILE.
mode: subagent
temperature: 0.2
permission:
  edit: allow
  bash:
    "*": ask
    "git log *": allow
    "git show *": allow
    "git diff *": allow
    "rg *": allow
---

# startproject

計画フェーズ（Phase 1–3）を担当。TASK_FILE を SSoT として更新する。

## Input

```
$ARGUMENTS: "{task description} --tier={S|M|L} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
```

---

## PHASE 1: UNDERSTAND

1. コードベースを Read / Glob / Grep で直接読む
   - 構造・主要モジュール・既存パターン・関連コード・テスト構造
   - git 履歴調査が必要な場合:
     ```bash
     git log --oneline -20 -- {area}
     git diff HEAD~5..HEAD -- {area}
     ```

2. 要件ヒアリング
   - 目的・スコープ・技術要件・成功基準・最終デザイン
   - **DONT-ASK MODE:** 提供済み情報から推定して続行

3. プロジェクト概要書を作成
   - Current State / Goal / Scope / Constraints / Success Criteria

4. **[MUST]** TASK_FILE の `Brief` セクションに概要書を書き込む

5. **[MUST]** 要件決定を Decision Log に記録
   - `[startproject] DECISION` エントリを各要件ごとに追加

6. **[MUST]** TASK_FILE の `Decision Log` に `[startproject] PRE` エントリ追加

---

## PHASE 2: RESEARCH & DESIGN

**$ARGUMENTS に「設計相談」「セカンドオピニオン」等のキーワード → tier に関わらず subagent で並列設計相談。**

成果物はすべて TASK_FILE の `Design` に書き込む（外部ファイル不作成）。

設計相談は `task` tool で subagent を起動する（同モデル・別コンテキストで独立性を確保）。
外部リサーチは firecrawl MCP（`firecrawl_search` / `firecrawl_scrape`）を使う。

### tier=S
スキップ → Phase 3。

### tier=M
`task` tool で subagent を起動して設計相談:

- prompt: "{設計相談内容}"
- 期待: 設計方針案を返す

得られた設計方針を TASK_FILE の `Design` に書き込む。

### tier=L
Researcher と Architect を **並列起動**。

| ロール | ツール | 役割 |
|-------|-------|------|
| Researcher | firecrawl MCP | 外部ライブラリ・事例を調査（出典 URL を必ず添える） |
| Architect  | `task` tool（subagent） | 設計方針を策定 |

両者の成果を Lead がメモリ内で統合し、TASK_FILE の `Design` に書き込む。

---

## PHASE 3: PLAN

1. TASK_FILE の `Brief` と `Design` を読み、内容を統合

2. `todowrite` ツールで実装タスクリストを作成

3. `CLAUDE.md` / `AGENTS.md` に Current Project セクションを追加
   - Goal / Key files / Architecture / Decisions

4. **[MUST]** Linear MCP の `save_comment` で LINEAR_ID に計画完了コメント投稿
   - `[startproject] POST` エントリを Decision Log に追加

5. 以下の基準で承認フローを自己判断

### 承認フロー判断基準

**自動承認 → 呼び出し元へ即返す:**
- タスクの解釈が一意
- 実装方針に選択肢がなく自明
- DONT-ASK MODE が有効

**Gate 1 発動 → ユーザー承認を待つ:**
- タスクの解釈が複数考えられる
- 実装方針に大きなトレードオフがある
- スコープが曖昧
- tier=L かつリスクが高い

Gate 1 発動時は計画を日本語で提示し、**判断が必要な理由と選択肢を明示**してユーザーに承認を求める。

---

## OUTPUT FILES

すべての成果物は TASK_FILE に集約する。

| セクション | 記入内容 | tier |
|-----------|---------|------|
| `Brief` | プロジェクト概要書 | 全 tier |
| `Decision Log` | DECISION / PRE / POST エントリ | 全 tier |
| `Design` | 設計方針・調査結果 | M, L |
| `CLAUDE.md` / `AGENTS.md` | Current Project セクション追加 | 全 tier |
