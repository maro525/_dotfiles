---
name: team-review
description: Review phase — 4 parallel reviewers (Claude / OpenCode / Security / Simplify), browser check or test execution. Called by /orchestrate with tier, task-file, linear-id.
context: fork
agent: Plan
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Agent, Skill, AskUserQuestion, TodoWrite, mcp__linear-server__save_comment, mcp__linear-server__get_issue, mcp__agent-browser__navigate, mcp__agent-browser__screenshot, mcp__agent-browser__click, mcp__agent-browser__type
---

# team-review

レビューフェーズを担当。
タスクファイル・Decision Log・Linear・Don't-Ask の共通ルールは CLAUDE.md 参照。

## Input

```
$ARGUMENTS の形式: "{task description} --tier={S|M|L} --task-file={TASK_FILE} --linear-id={LINEAR_ID} [--mode=self-review]"
```

| 引数 | 説明 |
|---|---|
| `--tier` | orchestrator が判定済み |
| `--task-file` | orchestrator が作成済みのタスクファイルパス |
| `--linear-id` | orchestrator が確認済みの Linear タスク ID |
| `--mode=self-review` | tier=S 時に orchestrator が付与。Claude 単独レビュー |

---

## 事前準備

レビュー開始前に必ず以下を読む。

1. TASK_FILE の `Brief` セクション — スコープ・成功基準
2. TASK_FILE の `Design` セクション — 設計方針・意図
3. TASK_FILE の `Implementation Notes` セクション — 実装サマリー・申し送り事項
4. `.claude/rules/security.md` — セキュリティチェックルール（Security Reviewer が使用）
5. 変更ファイル一覧を Read で確認

変更の性質を判定する（複数該当可）:

| 性質 | 判定基準 | 検証方法 |
|---|---|---|
| ブラウザ表示系 | UI コンポーネント・CSS・レイアウト変更を含む | agent-browser で表示確認 |
| ロジック系 | ビジネスロジック・API・データ処理を含む | テスト実行 |

---

## STEP 1: コードレビュー（4並列）

**以下の4レビュアーを同時に起動し、結果を Claude Lead に報告する。**
**mode=self-review の場合は Claude Reviewer のみ実行。**

### Claude Reviewer
変更ファイルを直接 Read してレビュー。

観点:
- **Quality** — 可読性・命名・重複・SOLID原則
- **Logic** — バグ・エッジケース・エラーハンドリング

### OpenCode Reviewer
```bash
opencode run -m github-copilot/gpt-5.4 "以下のコード変更をレビューしてください。Quality / Logic の観点で問題点と改善提案を列挙してください。\n\n{変更ファイルの内容}" 2>/dev/null
```

観点:
- **Quality** — 可読性・命名・重複・SOLID原則
- **Logic** — バグ・エッジケース・エラーハンドリング

### Security Reviewer
`.claude/rules/security.md` を Read し、記載されたルールに従って変更ファイルをチェックする。

```
1. Read .claude/rules/security.md
2. ルールの各項目を変更コードに照合
3. 違反・懸念箇所を severity 付きで列挙
```

観点（security.md の内容に従う）:
- 認証・認可の抜け
- 入力バリデーション・サニタイズ
- 機密情報のハードコード
- SQL インジェクション・XSS などの脆弱性
- その他 security.md に記載されたルール

### Simplify Reviewer
`/simplify` スキルを実行して複雑さを検出する。

```
Skill: simplify
対象: 変更ファイル一覧
```

観点:
- 過剰な複雑さ・不要な抽象化
- デッドコード・未使用変数
- 簡略化できるロジック
- リファクタリング提案

---

## STEP 2: Claude Lead による統合

4レビュアーの結果を受け取り統合する。

- 重複する指摘は1件にまとめ、severity を引き上げる
- 矛盾する指摘はより厳しい方を採用
- minor 指摘はまとめて申し送り事項へ

---

## STEP 3: 動作検証

変更の性質に応じて実行する。両方該当する場合は両方実施。

### ブラウザ表示系 → agent-browser で確認

```
1. mcp__agent-browser__navigate で対象ページを開く
2. mcp__agent-browser__screenshot でスクリーンショットを取得
3. 表示崩れ・レイアウト問題を目視確認
4. インタラクションが必要な場合は click / type で操作
5. 各状態のスクリーンショットを取得して記録
```

確認観点:
- デザイン仕様との一致
- レスポンシブ対応（必要な場合）
- インタラクション動作（ホバー・クリック・フォーム送信など）
- エラー状態・空状態の表示

### ロジック系 → テスト実行

```bash
# プロジェクトのテストコマンドを CLAUDE.md または package.json から確認して実行
{test_command}
```

確認観点:
- 全テストが通過しているか
- 新規実装に対応するテストが存在するか
- カバレッジに明らかな欠落がないか

---

## STEP 4: 判定

統合レビュー結果と動作検証結果をもとに判定する。

| severity | 定義 | 判定への影響 |
|---|---|---|
| critical | セキュリティ脆弱性・データ破損リスク・テスト失敗 | FAIL 確定 |
| major | バグ・大きな設計問題・表示崩れ | FAIL |
| minor | 改善提案・命名・スタイル・リファクタリング推奨 | PASS（申し送りとして記録） |

- **PASS** — critical / major がゼロ
- **FAIL** — critical または major が1件以上

---

## OUTPUT

TASK_FILE の `Review` セクションに以下を記入する。

```markdown
## Review

### 判定: PASS / FAIL

### コードレビュー統合結果

#### Claude Reviewer
- [severity] 指摘内容

#### OpenCode Reviewer
- [severity] 指摘内容

#### Security Reviewer
- [severity] 指摘内容（security.md ルール参照）

#### Simplify Reviewer
- [severity] 指摘内容

#### 統合サマリー
- 複数レビュアー共通の指摘（severity 引き上げ）
- 個別の指摘

### 動作検証結果

#### ブラウザ表示確認（該当する場合）
- 確認したページ・状態
- 問題点（あれば）

#### テスト実行結果（該当する場合）
- 実行コマンド
- 結果サマリー
- 失敗したテスト（あれば）

### 申し送り事項（minor）
- deploy フェーズへの注意点
- リファクタリング推奨（次タスクで対応）
```

**[MUST]** Linear にコメントを投稿する。
- `mcp__linear-server__save_comment` で LINEAR_ID にレビュー結果（PASS/FAIL + サマリー）を投稿
- TASK_FILE の `Decision Log` に `[team-review] POST` エントリを追加

---

## DONT-ASK MODE

| 通常の確認 | DONT-ASK 時の動作 |
|---|---|
| ブラウザ確認の要否判断 | 変更ファイルに UI 関連が含まれれば自動実行 |
| テスト実行の要否判断 | ロジック変更が含まれれば自動実行 |
| PASS/FAIL 報告 | 判定結果を呼び出し元へそのまま返す |
