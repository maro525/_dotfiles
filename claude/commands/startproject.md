---
name: startproject
description: Project kickoff — understand codebase, research/design, create plan. Called by /orchestrate with tier, task-file, linear-id.
context: fork
agent: Plan
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Agent, Skill, AskUserQuestion, SendMessage, TodoWrite, mcp__linear-server__save_comment, mcp__linear-server__get_issue
---

# startproject

計画フェーズ（Phase 1–3）を担当。
タスクファイル・Decision Log・Linear・Don't-Ask の共通ルールは CLAUDE.md 参照。

## Input

```
$ARGUMENTS の形式: "{task description} --tier={S|M|L} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
```

| 引数 | 説明 |
|---|---|
| `--tier` | orchestrator が判定済み。省略時は S |
| `--task-file` | orchestrator が作成済みのタスクファイルパス |
| `--linear-id` | orchestrator が確認済みの Linear タスク ID |

---

## PHASE 1: UNDERSTAND

**担当: Claude Lead（1M context）**

1. コードベースを Explore / Glob / Grep / Read で直接読む
   - 構造・主要モジュール・既存パターン・関連コード・テスト構造
   - git 履歴調査が必要なら Gemini サブエージェントに委託

2. 要件ヒアリング
   - 目的・スコープ・技術要件・成功基準・最終デザイン
   - **DONT-ASK MODE:** 提供済み情報から推定して続行

3. プロジェクト概要書を作成
   - Current State / Goal / Scope / Constraints / Success Criteria

4. **[MUST]** TASK_FILE の `Brief` セクションに概要書を書き込む

5. **[MUST]** 要件決定を Decision Log に記録
   - TASK_FILE の `Decision Log` に `[startproject] DECISION` エントリを追加
   - 要件ごとに1件

6. **[MUST]** TASK_FILE の `Decision Log` に `[startproject] PRE` エントリを追加

---

## PHASE 2: RESEARCH & DESIGN

**tier によって動作を切り替える。成果物はすべて TASK_FILE の `Design` セクションに書き込む。外部ファイルは作成しない。**

### tier=S
スキップ → Phase 3 へ進む。

### tier=M
OpenCode サブエージェントに設計相談:

```bash
opencode run -m github-copilot/gpt-5.4 "{question}" 2>/dev/null
```

- subagent_type: general-purpose
- 得られた設計方針を TASK_FILE の `Design` セクションに書き込む

### tier=L
Researcher と Architect を **並列起動**し、双方向通信させる。
両者の成果はファイルに保存せず、Claude Lead がメモリ内で受け取り統合する。

| エージェント | ツール | 役割 |
|---|---|---|
| Researcher | Gemini CLI | 外部ライブラリ・事例を調査し Claude Lead に報告 |
| Architect | OpenCode CLI | 設計方針を策定し Claude Lead に報告 |

両者はリアルタイムで発見を共有し、設計を相互に調整する。
Claude Lead は統合結果を TASK_FILE の `Design` セクションに書き込む。

---

## PHASE 3: PLAN

**担当: Claude Lead**

1. TASK_FILE の `Brief` と `Design` セクションを読み、内容を統合

2. `TodoWrite` で実装タスクリストを作成

3. `CLAUDE.md` に Current Project セクションを追加
   - Goal / Key files / Architecture / Decisions

4. **[MUST]** Linear にコメントを投稿する
   - `mcp__linear-server__save_comment` で LINEAR_ID に計画完了コメントを投稿
   - TASK_FILE の `Decision Log` に `[startproject] POST` エントリを追加

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

Gate 1 発動時は計画を日本語で提示し、**判断が必要な理由と選択肢を明示**してユーザーの承認を求める。
承認されたら即呼び出し元へ制御を返す。差し戻しの場合はフィードバックをもとに計画を修正する。

---

## OUTPUT FILES

すべての成果物は TASK_FILE に集約する。外部ファイルは作成しない。

| TASK_FILE セクション | 記入内容 | tier |
|---|---|---|
| `Brief` | プロジェクト概要書 | 全 tier |
| `Decision Log` | DECISION / PRE / POST エントリ | 全 tier |
| `Design` | 設計方針・調査結果の統合 | M, L |
| `CLAUDE.md` | Current Project セクション追加 | 全 tier |
