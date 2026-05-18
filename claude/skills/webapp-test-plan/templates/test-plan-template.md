# {APP_NAME} テスト計画

## 前提

- **アクター一覧** （アプリのロール構成に合わせて記入。customer/admin に限らない）:
  - `{actor-1-session}`: {役割・権限の要約} (`{ACTOR_1_SIGN_IN_URL}`)
  - `{actor-2-session}`: {役割・権限の要約} (`{ACTOR_2_SIGN_IN_URL}`)
  - 必要に応じて追加（例: author + reviewer + admin、buyer + seller + moderator など）
- 各アクターのセッションを同時に開き、相互反映や role 別の表示差を確認する
- ロール限定の表示ルール（特定 status の隠蔽・別ラベル化など）があれば列挙: {VISIBILITY_RULES}

---

## 実装分析サマリ

- {finding-1}
- {finding-2}
- {finding-3}
- {finding-4}

---

## アップロード準備

### アップロード制約

- {constraint-1}
- {constraint-2}

### 推奨フィクスチャ

| ファイル名 | 用途 | 備考 |
| ---------- | ---- | ---- |
| `file-a.ext` | 基本ケース | — |
| `file-b.ext` | 複数アイテム | — |
| `too-large.ext` | サイズ超過テスト | 意図的にlimit超え |
| `invalid.txt` | 不正拡張子テスト | バリデーション確認 |

### 既存リポジトリ内の再利用候補

- `{PATH_1}`
- `{PATH_2}`

### 用意方針

- ファイル名は英数字・ハイフン中心、空白や日本語を避ける
- サイズは小さめ、サイズ超過検証用だけ意図的に limit 超え

---

## スクショファイル名規約

各テストステップの `スクショ` 列には `test-<テスト番号>-<ステップ番号>.png` を記入（例: `test-1-1.png`）。撮影タイミング・スコープ指定・`--annotate` の使い分けは実行時 (`webapp-test-run`) の関心事なので計画書側では決めない。

---

## テスト1: {基幹ハッピーパス名}

対象: {scope}

ステータス遷移:
`{S0} -> {S1} -> {S2} -> ... -> {SN}`

| #   | 操作者          | 操作 | 確認ポイント | スクショ       |
| --- | --------------- | ---- | ------------ | -------------- |
| 1-1 | `{actor-1}`     | ...  | ...          | `test-1-1.png` |
| 1-2 | `{actor-1}`     | ...  | ...          | `test-1-2.png` |
| 1-3 | `{actor-2}`     | ...  | ...          | `test-1-3.png` |

---

## テスト2: {次のワークフロー名}

| #   | 操作者      | 操作 | 確認ポイント | スクショ       |
| --- | ----------- | ---- | ------------ | -------------- |
| 2-1 | `{actor-1}` | ...  | ...          | `test-2-1.png` |

---

<!--
  Add as many tests as your app needs (typically 5-9 total; a small app may have 3,
  a complex one 12). Each test should be 5-17 steps; split if it grows beyond 20.

  See SKILL.md `Guidance on workflow selection` for the priority order to choose
  which workflows to cover (happy path → branching logic → exceptions → list UIs
  → real-time / heavy environment-dependent checks).
-->

---

## 実行順序

各テストの目的を1行で要約しつつ列挙する:

1. `{test-id}` — {このテストで確認する観点}
2. `{test-id}` — {...}

順序ガイドライン: 基幹ハッピーパス → 分岐ロジック → 例外ケース → 一覧/フィルタ系 → 帳票やリアルタイムなど環境依存の重い検証、の順で並べると後段のテストが前段の成功に依存しやすく組みやすい。

---

## ステータス一覧（参考）

<!-- Status enum を持つドメインの場合のみ記入。純粋な CRUD アプリでは丸ごと削除。 -->

### {EntityName}Status: `{actor-1}` 向け表示

| Status | ラベル |
| ------ | ------ |
| `S0`   | ...    |

### {EntityName}Status: `{actor-2}` 向け表示

| 実際のステータス | `{actor-2}` に見えるラベル |
| ---------------- | -------------------------- |

### {Group}Derived 派生ステータス

| DerivedStatus | ラベル | 条件 |
| ------------- | ------ | ---- |
