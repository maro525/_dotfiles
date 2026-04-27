---
name: team-review
description: Review phase — parallel reviewers (Quality / Logic / Security / Simplify), browser/test verification. Outputs PASS / FAIL to task file. Use when the user mentions review, code review, team-review, or quality check.
user-invocable: true
argument-hint: "<task description> --tier=<S|M|L> --task-file=<path> --linear-id=<id> [--mode=self-review]"
---

# team-review

レビューフェーズを担当。

## Input

```
$ARGUMENTS: "{task description} --tier={S|M|L} --task-file={TASK_FILE} --linear-id={LINEAR_ID} [--mode=self-review]"
```

---

## 事前準備

1. TASK_FILE の `Brief` — スコープ・成功基準
2. TASK_FILE の `Design` — 設計方針・意図
3. TASK_FILE の `Implementation Notes` — 実装サマリー・申し送り
4. 変更ファイル一覧を `git diff` / Read で確認

**[MUST]** Linear にレビュー開始コメントを投稿。

変更の性質を判定:

| 性質 | 判定基準 | 検証方法 |
|------|---------|---------|
| ブラウザ表示系 | UI / CSS / レイアウト変更 | agent-browser スキルで確認 |
| ロジック系 | ビジネスロジック・API・データ処理 | テスト実行 |

---

## STEP 1: コードレビュー（並列）

**tier ごとのレビュアー構成:**

| tier | レビュアー |
|------|----------|
| S (mode=self-review) | Quality Reviewer のみ |
| M | Quality + Security |
| L | Quality + Logic + Security + Simplify |

pi の `subagent` ツールで PARALLEL モード:
```
subagent {
  tasks: [
    {agent: "default", task: "Quality review: {files}", output: "quality.md"},
    {agent: "default", task: "Security review: {files}", output: "security.md"},
    ...
  ],
  concurrency: 4
}
```

### Quality Reviewer
変更ファイルを Read してレビュー。
観点: 可読性・命名・重複・SOLID原則。

### Logic Reviewer
観点: バグ・エッジケース・エラーハンドリング。

### Security Reviewer
PI.md のセキュリティルールに従って変更ファイルをチェック。
観点: 認証・認可の抜け、入力バリデーション・サニタイズ、機密情報のハードコード、SQLインジェクション・XSS 等。

### Simplify Reviewer
観点: 過剰な複雑さ・不要な抽象化・デッドコード・リファクタ提案。

---

## STEP 2: Lead による統合

- 重複指摘は1件にまとめ severity を引き上げ
- 矛盾する指摘はより厳しい方を採用
- minor 指摘は申し送り事項へ

---

## STEP 3: 動作検証

### ブラウザ表示系 → agent-browser スキルで確認
- 対象ページを開いてスクリーンショット取得
- レイアウト・インタラクション・エラー状態を確認

### ロジック系 → テスト実行
プロジェクトのテストコマンドを実行:
- `npm test`, `pnpm test`, `pytest`, `uv run pytest` など

---

## STEP 4: 判定

| severity | 定義 | 判定 |
|---------|-----|-----|
| critical | セキュリティ脆弱性・データ破損・テスト失敗 | FAIL 確定 |
| major    | バグ・大きな設計問題・表示崩れ | FAIL |
| minor    | 改善提案・命名・リファクタ推奨 | PASS（申し送り） |

- **PASS** — critical / major がゼロ
- **FAIL** — critical または major が1件以上

---

## OUTPUT

TASK_FILE の `Review` セクション:

```markdown
## Review

### 判定: PASS / FAIL

### コードレビュー統合結果
- [severity] 指摘内容（レビュアー別）

### 動作検証結果
- テスト実行結果
- ブラウザ確認結果（該当時）

### 申し送り事項（minor）
- deploy フェーズへの注意点
- リファクタ推奨（次タスクで対応）
```

**[MUST]** Linear に PASS/FAIL + サマリーを投稿。
**[MUST]** TASK_FILE の `Decision Log` に `[team-review] POST` エントリ追加。
