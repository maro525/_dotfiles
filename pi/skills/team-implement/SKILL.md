---
name: team-implement
description: Implementation phase — reads design, implements code, writes to task file. Called by /orchestrate with tier, task-file, linear-id. Use when the user mentions implementation, coding phase, or team-implement.
user-invocable: true
argument-hint: "<task description> --tier=<S|M|L> --task-file=<path> --linear-id=<id>"
---

# team-implement

実装フェーズを担当。TASK_FILE の Design に沿って実装する。

## Input

```
$ARGUMENTS: "{task description} --tier={S|M|L} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
```

---

## 事前準備

実装開始前に必ず以下を読む:

1. TASK_FILE の `Brief` — スコープ・成功基準
2. TASK_FILE の `Design`（tier=M,L）— 設計方針・アーキ決定
3. TASK_FILE の `Decision Log` — これまでの意思決定
4. 実装タスクリスト

**[MUST]** Linear に実装開始コメントを投稿（ステータス → In Progress）。

---

## IMPLEMENTATION

### tier=S
直接実装。

- feature ブランチを作成して作業
- TDD（テスト先行）を推奨
- 完了後 TASK_FILE の `Implementation Notes` に記録

### tier=M
直接実装 or 1-2 subagent に委譲。

- feature ブランチを作成
- モジュールが独立している場合は subagent に並列実装させる
- 各 subagent の成果を Lead がレビュー・統合

pi の `subagent` ツールで PARALLEL モード:
```
subagent {
  tasks: [
    {agent: "default", task: "Implement module A: {details}", output: "module-a.md"},
    {agent: "default", task: "Implement module B: {details}", output: "module-b.md"}
  ],
  concurrency: 2,
  worktree: true
}
```

### tier=L
フルチームでモジュール単位のオーナーシップ制。

- feature ブランチを作成
- Lead がモジュールを分割し、各 subagent にアサイン
- 各 subagent は担当モジュールの実装・テストまで完結
- subagent 間の依存は Lead が調整

pi の `subagent` ツールで CHAIN モード + PARALLEL:
```
subagent {
  chain: [
    {agent: "orchestrator", task: "Plan module split for {task}"},
    {parallel: [
      {agent: "implementer", task: "Implement {module}", count: N}
    ]},
    {agent: "integrator", task: "Merge and verify all modules"}
  ]
}
```

---

## エスカレーション確認

| チェックポイント | 確認内容 |
|----------------|---------|
| 実装 30-40% 時点 | スコープが広がっていないか |
| 新依存追加時 | Hard Trigger に該当しないか |
| 未解決設計問題 | tier 引き上げが必要か |

エスカレーションが必要な場合はユーザーに報告して承認を得る。

---

## 完了条件

- [ ] 実装タスクリストがすべて完了
- [ ] テストがすべて通過
- [ ] TASK_FILE の `Implementation Notes` 記入済み

---

## OUTPUT

TASK_FILE の `Implementation Notes`:

```markdown
## Implementation Notes

### 実装サマリー
- 実装したモジュール・ファイル一覧
- 主要な実装判断とその理由

### 変更ファイル
- path/to/file.ts — 変更内容の概要

### テスト
- テストファイルの場所
- カバレッジの概要

### 残課題・注意点
- レビュアーへの申し送り事項
```

**[MUST]** Linear に実装完了コメントを投稿。
**[MUST]** TASK_FILE の `Decision Log` に `[team-implement] POST` エントリ追加。
