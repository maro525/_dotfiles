---
name: doc-clarity-check
description: ドキュメント/ヘルプ/UIテキストの「分かりやすさと正確さ」をレビューする。初見の読者が一読で理解でき、かつ何度読んでも誤解しない（語が実画面ラベルと一致し、呼称がぶれない）かを、専門語/具体性/呼称の統一/画面一致/次の行動など7観点で、dynamic Workflow による「多観点レビュー → 敵対的検証 → ルーブリック採点」で点検する。Use when asked to review help/docs/UI copy for clarity, plain language, terminology consistency, or matching real UI labels. Triggers: 「分かりやすく」「初見でわかるか」「用語のゆれ/呼称の統一」「画面と説明が合っているか」「コピーをチェック」「難しいと言われた」.
context: fork
argument-hint: "[file globs...] [--fix] [--scope=diff|files]"
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Workflow, AskUserQuestion
---

# doc-clarity-check（ドキュメント明瞭性チェック）

ユーザー向けの文章を **「業界・開発者しか分からない言葉になっていないか」「初めて見る人にも伝わるか」「何度読んでも誤解しないか」** という視点で点検するスキル。
コードレビュー（`/code-review`）やデザインUX評価（`/critique`）とは別物で、**自然言語コピーの分かりやすさと正確さ** に特化する。

中核の問い：**「意味は分かるけれど、初めて見る人にも伝わるか？ そして、何度読んでも誤解しないか？」**

## いつ使うか

- ヘルプ / マニュアル / オンボーディング文 / 空状態メッセージ / ボタン・ラベル / エラーメッセージ などのレビュー
- 「難しいというフィードバックが来た」「もっと分かりやすくしたい」と言われたとき
- 用語のゆれ（同じものを別名で呼んでいないか）を洗い出したいとき

## 評価7観点（ルーブリック）

| # | 観点 | 合格の状態 |
|---|------|-----------|
| 1 | **専門語・開発者語** | 業界用語・社内語・難しいカタカナ語がない、または初出で平易に言い換え/補足している |
| 2 | **初見の理解** | 前提知識ゼロの人が意味を取れる（最重要・「分かるが伝わるか」を問う） |
| 3 | **具体性** | 抽象論で終わらず「ユーザーが何をできるか」（効用・例）が示されている |
| 4 | **自然な日本語** | 一読で頭に入る。冗長・文のねじれ・不自然な係り受けがない |
| 5 | **呼称の統一** | 同じ概念を別名で呼んでいない。プロジェクトの用語ルールに沿っている |
| 6 | **画面との一致** | 説明・見出し・alt が実画面のラベルやスクショ内容と一致している |
| 7 | **次の行動** | 各段階で「次に何をすればよいか」が分かる。順序・導線が明確 |

採点：各観点 **0–2点**（2=問題なし / 1=軽微 / 0=ブロッカー）、満点14点。
**合格＝合計12点以上 かつ「初見の理解(2)」「呼称の統一(5)」が各2点**。

## 手順

### Step 1 — 対象を決める

`$ARGUMENTS` を解釈する：

- ファイルパス/glob が指定 → それを対象にする。
- `--scope=diff` または対象未指定 → **現ブランチで変更したユーザー向けファイル** を既定対象にする
  （`git diff --name-only $(git merge-base HEAD staging)...HEAD` 等で抽出し、`.astro/.md/.mdx/.tsx/.ts` のうちコピーを含むものに絞る。ベースブランチは `staging` 優先、無ければ `main`）。
- それでも0件なら `AskUserQuestion` で対象を尋ねる。

`--fix` … 確定した指摘を本文に反映する（既定はレビューのみ）。

対象ファイルのパス一覧を確定する（全文の読み込みは Workflow 内の各エージェントが行う。画像内容そのものは判定外＝alt文と説明文の整合で代替）。

### Step 2 — プロジェクトの用語ルール（glossary）を読み込む

呼称の統一(観点5)・画面一致(観点6)は **正解語** が要る。次を探して `glossary` 文字列にまとめる：

- プロジェクト直下 `CLAUDE.md` の「UI用語ルール / 用語 / 表記」表（`grep -nA30 "用語" CLAUDE.md` などで抽出）
- `docs/**/glossary*`, `**/terminology*`, デザインシステム文書があれば併せて
- 見つからなければ `glossary = "(プロジェクト固有の用語ルールは見つからず。一般的な日本語UI慣習で判定)"`

### Step 3 — dynamic Workflow を実行する

以下のスクリプトを **Workflow ツールの `script` に渡す**。`args` には Step1 で確定した `paths`（対象ファイルパスの配列）と Step2 の `glossary` を入れる。
（このスキルの指示が Workflow 呼び出しの opt-in を兼ねる。）

```javascript
export const meta = {
  name: 'doc-clarity-check',
  description: '初見読解度7観点で多観点レビュー→敵対的検証→ルーブリック採点',
  phases: [
    { title: 'Review', detail: '7観点+ペルソナ通読を並列レビュー' },
    { title: 'Verify', detail: '各指摘を敵対的に検証し誤検出を落とす' },
    { title: 'Synthesize', detail: 'ルーブリック採点と報告書化' },
  ],
}

const files = (args && args.paths) || []
const docs = files.join('\n')
const glossary = (args && args.glossary) || '(用語ルールなし)'

const FINDING_SCHEMA = {
  type: 'object',
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          criterion: { type: 'string', description: '観点ラベル' },
          severity: { type: 'string', enum: ['blocker', 'major', 'minor'] },
          location: { type: 'string', description: '原文の該当箇所をそのまま引用（行の手がかりも）' },
          problem: { type: 'string', description: '初見の読者が引っかかる理由' },
          suggestion: { type: 'string', description: '具体的な修正案（語・文レベル）' },
        },
        required: ['criterion', 'severity', 'location', 'problem', 'suggestion'],
      },
    },
  },
  required: ['findings'],
}

const VERDICT_SCHEMA = {
  type: 'object',
  properties: {
    real: { type: 'boolean', description: '本当に初見の読者にとって問題か' },
    ruleSafe: { type: 'boolean', description: '修正案が用語ルール/実画面ラベルと矛盾しないか' },
    reason: { type: 'string' },
    revisedSuggestion: { type: 'string', description: '必要なら改善した修正案（なければ空）' },
  },
  required: ['real', 'ruleSafe', 'reason'],
}

const DIMENSIONS = [
  { key: 'jargon', label: '専門語・開発者語', q: '業界用語・社内語・難しいカタカナ語を使っていないか。初出で平易な言い換えや補足があるか。' },
  { key: 'first-time', label: '初見の理解', q: '前提知識ゼロの人が意味を取れるか。「意味は分かるが初見の人に伝わるか？」を最優先で見る。' },
  { key: 'concrete', label: '具体性', q: '抽象的な説明で終わらず、ユーザーが具体的に何をできるか（効用・例）が示されているか。' },
  { key: 'natural-ja', label: '自然な日本語', q: '一読で頭に入る自然な日本語か。冗長・文のねじれ・不自然な係り受けがないか。' },
  { key: 'consistency', label: '呼称の統一', q: '同じ概念を別名で呼んでいないか。まず文書全体の用語マップ（概念→使われている表記の一覧）を作り、表記ゆれ・別名・用語ルール違反を洗い出す。' },
  { key: 'ui-match', label: '画面との一致', q: '説明文・見出し・altが実画面のラベルやスクショ内容と一致しているか。実在しないUI語や食い違いがないか。' },
  { key: 'next-action', label: '次の行動', q: 'ユーザーが各段階で次に何をすればよいか分かるか。順序・導線が明確か。' },
  { key: 'persona', label: '初見ペルソナ通読', persona: true },
]

const reviewPrompt = (d) => d.persona
  ? `あなたはこのアプリを初めて触る現場担当者で、専門知識はありません。次のファイルを Read で開いて全文を上から1回だけ通読し、引っかかった箇所をすべて挙げてください。
criterion は "初見ペルソナ"、severity は引っかかりの強さ（読み進めるのを止めた=blocker / もたついた=major / 軽い違和感=minor）。

対象ファイル（Read して読む）:
${docs}

参考（用語ルール）:
${glossary}

原文を location に引用すること。`
  : `あなたは「初見の読者が最初の一読でどれだけ理解できるか」を評価するレビュアーです。
観点: ${d.label} — ${d.q}

対象ファイル（Read で開いて全文を読んでから評価）:
${docs}

プロジェクトの用語ルール（呼称の正解。これに反する語は finding にする）:
${glossary}

ルール:
- 推測でなく原文を引用して指摘する（location に原文の該当箇所をそのまま入れる）。
- 実画面の正式ラベル（ボタン名・メニュー名など）は安易に言い換えない。言い換えると画面と食い違う場合は suggestion にその旨を注記する。
- この観点で問題がなければ findings は空配列にする。`

phase('Review')
const reviewed = await pipeline(
  DIMENSIONS,
  (d) => agent(reviewPrompt(d), { label: `review:${d.key}`, phase: 'Review', schema: FINDING_SCHEMA }),
  (res, d) => {
    const fs = (res && res.findings) || []
    return parallel(fs.map((f) => () =>
      agent(`次の指摘を批判的に検証してください。本当に初見の読者にとって問題ですか？ 修正案はプロジェクトの用語ルール・実画面ラベルと矛盾しませんか？ 迷ったら real=false に寄せてください。

指摘(JSON):
${JSON.stringify(f)}

用語ルール:
${glossary}

対象:
${docs}`, { label: `verify:${d.key}`, phase: 'Verify', schema: VERDICT_SCHEMA })
        .then((v) => ({ ...f, verdict: v }))
    ))
  }
)

const all = reviewed.flat().filter(Boolean)
const confirmed = all.filter((f) => f.verdict && f.verdict.real && f.verdict.ruleSafe)
  .map((f) => ({ ...f, suggestion: (f.verdict.revisedSuggestion || f.suggestion) }))
log(`検出 ${all.length} 件 → 確定 ${confirmed.length} 件`)

phase('Synthesize')
const report = await agent(`次の「確定した指摘」を、初見読解度ルーブリックで採点し、重要度順に並べた日本語Markdownのレビュー報告書にしてください。

ルーブリック（各0-2点・満点14）:
1 専門語・開発者語 / 2 初見の理解 / 3 具体性 / 4 自然な日本語 / 5 呼称の統一 / 6 画面との一致 / 7 次の行動
合格＝合計12点以上 かつ「初見の理解」「呼称の統一」が各2点。

確定指摘(JSON):
${JSON.stringify(confirmed)}

出力構成:
1. 観点別スコア表（観点 / 点数 / 一言）と合計・合否
2. 重要度順の指摘リスト（severity / 原文引用 / 問題 / 修正案）。同じ語のゆれは1件にまとめる
3. 総評: 初見の読者が最初の一読でつまずく最大の要因を2〜3行で`, { phase: 'Synthesize' })

return { report, confirmed, total_findings: all.length }
```

### Step 4 — 報告する

Workflow の戻り値 `report` をそのままユーザーに提示する。観点別スコア表・重要度順の指摘・総評を含める。

### Step 5 —（`--fix` 指定時のみ）修正を反映する

- `confirmed` の各指摘について、`location`（原文引用）を手がかりに **メインスレッドで Edit** を使って反映する。Workflow 側では書き換えない（並列編集の競合回避）。
- 同じ語のゆれは `replace_all` も検討しつつ、別の意味で使っている箇所を巻き込まないよう原文を確認してから置換する。
- 反映後、ビルド/型チェックが用意されていれば実行して壊れていないか確認する（例: astro/Next なら build、md のみなら省略可）。
- **コミットはしない**。「反映したので確認後に commit/push をお願いします」と伝える（プロジェクトの Git 規約に従う）。

## メモ

- 汎用スキル。nanco 以外でも、用語ルールが見つかればそれを正解語として使い、無ければ一般的な日本語UI慣習で判定する。
- 規模に応じて Workflow の観点数は増減してよい（軽微なら観点を束ねる、徹底なら検証票数を増やす）。
- 画像そのものの内容判定は行わない。観点6は「alt文・説明文 ↔ 実画面ラベル」の整合で代替する。実画像との突合が要る場合はユーザーに確認を促す。
