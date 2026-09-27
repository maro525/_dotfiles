# Tool Routing Rules

**Defines which tools and operations are delegated to which agent.**

外部リサーチは firecrawl MCP + OpenCode リサーチの二系統、設計相談は OpenCode に振り分ける。

## Skill Routing hook への応答

`agent-router.py`（UserPromptSubmit hook）がスキル候補を `[Skill Routing]` として additionalContext に出す。ソフトな推奨として扱う。

- **従う**: プロンプトの意図と一致し、ユーザーの明示指示と矛盾しない場合。提案に従う旨を一言伝えてから Skill ツールで起動する
- **従わなくてよい**: ユーザーが別のことを明示している／提案スキルに対してタスクが小さすぎる（XS など）／進行中ワークフロー内の追加質問
- 提案がずれていると思ったら、理由を伝えてユーザーに確認する

## Adaptive Execution Override

> 参照: `.claude/rules/adaptive-execution.md`

ルーティングルールはタスクサイズに応じて適応される：

- **XS/S タスク**: OpenCode / firecrawl への委託は不要。Claude が直接対応する。
- **M タスク**: 必要な場合のみ OpenCode サブエージェントで設計相談。外部リサーチ（firecrawl + OpenCode）は未知のライブラリ・外部 API がある場合のみ。
- **L タスク**: フルルーティング（全ルール適用）。

## Routing Table

| Operation | Delegate To | Method |
|-----------|-------------|--------|
| External research | **firecrawl MCP + OpenCode** | 二系統を並列実行し Claude が統合（下記セクション参照） |
| PDF / 記事 (URL) | **firecrawl MCP** | `firecrawl_parse` / `firecrawl_scrape` |
| 音声・動画 | **未対応** | 委託先なし。ユーザーに扱い方を確認する |
| Library research | **firecrawl MCP + OpenCode** | `firecrawl_search` で一次情報 + OpenCode で実装知見 |
| Design decisions | **OpenCode** | Subagent（`opencode run --agent plan -m github-copilot/gpt-5.6-sol`） |
| git（書き込み系） | **`/deploy` skill** | Ad-hoc Git モード。読み取り系は Claude が直接 |
| docker/ruff/uv (in `context: fork` skills) | **Direct** | スキル内で直接実行 |
| docker/ruff/uv (ad-hoc) | **Subagent** | サブエージェント経由で直接実行 |
| GitHub MCP / Linear MCP | **Direct or Subagent** | スキル内は直接、アドホックはサブエージェント |

## External Research via firecrawl MCP + OpenCode

外部リサーチは **二系統を並列実行**し、Claude が突き合わせて統合する（`gemini` CLI は廃止済み）。

| 系統 | ツール | 得意分野 |
|------|-------|---------|
| **一次情報** | firecrawl MCP | 公式ドキュメント・リリースノートの実文面。出典 URL が取れる |
| **実装知見** | OpenCode CLI | 学習済み知識に基づく設計上の勘所・落とし穴・比較 |

**併用の理由**: firecrawl は「現在の事実」を出典付きで取れるが解釈はしない。OpenCode は解釈と経験則を出せるが出典を持たない。両者が食い違った場合は **firecrawl の一次情報を優先**し、相違点と採用した方を記録する（`/startproject` では TASK_FILE の `### Design`）。

### OpenCode リサーチの実行

**これが唯一動く呼び出し形。他のファイルはこの節を参照する。**

```bash
opencode run --agent plan -m github-copilot/gpt-5.6-sol "{research question}" < /dev/null
```

| 要素 | 理由（外すと壊れる） |
|------|---------------------|
| `--agent plan` **必須** | 既定の `build` エージェントは非対話実行だとパーミッション確認で**無言ハング**する（11 分無反応を実測）。stderr にも何も出ないので原因が分からない |
| `< /dev/null` **必須** | stdin が**開いたパイプ**だと opencode は永久にハングする。`run_in_background: true` がまさにその状態を作る（フォアグラウンドの Bash 呼び出しには自動で付くが、バックグラウンドには付かない）。42 分と 12 分で kill された 2 回は stdout・stderr・ログすべて空。**下の「バックグラウンド実行必須」と必ずセットで使う** |
| `2>/dev/null` を**付けない** | opencode はエラーを stderr に出しつつ **exit code 0** で終わる。潰すと「成功したのに出力が空」という紛らわしい結果になる |
| `github-copilot/gpt-5.6-sol` が第一候補 | `openai/gpt-5.6-sol` は 2026-08-12 時点で `insufficient_quota` を返して**必ず失敗する**。一時的な超過ではなく残高切れ。課金が復活したら第一候補に戻す |
| **バックグラウンド実行必須** | 込み入った質問は 10 分超。Bash ツールの既定 10 分では途中で kill されて出力ゼロになり、ハングと見分けがつかない |
| cwd は **git リポジトリ**にする | 非 git ディレクトリ（`/tmp` 等）だと起動シーケンスの `service=vcs` 初期化で無言ハングする |

- 長文プロンプトはファイルに落として `"$(cat prompt.txt)"` で渡す
- ツール呼び出しで止まらせたくない場合はプロンプト冒頭に `DO NOT USE ANY TOOLS` と書く
- 空出力を見たら quota と決めつけない。ログは `~/.local/share/opencode/log/` に 1 セッション 1 ファイル。
  正常なセッションは `service=session id=` → `POST /session` → `service=snapshot hash=` → `resolveTools` →
  `service=llm … stream` と進む。**`service=vcs … initialized` の後で止まっていれば stdin 詰まり**（`< /dev/null` を付け忘れ）で、cwd が非 git のときと同じ見た目になる
- 疎通確認は `opencode run --agent plan -m <model> "Reply with exactly: PONG"`（数十秒で返る）
- サブエージェント経由で実行し、メインコンテキストを汚さない
- OpenCode はコードを実際に読まずに答えることがある。結論は採用してよいが**根拠は必ず自分で検証する**

### Scope

- ライブラリ・フレームワークの最新仕様、公式ドキュメント
- リリースノート・変更履歴・非推奨情報
- 既知の不具合・脆弱性・回避策
- 実装事例・ベンチマーク・比較記事

### Tools（firecrawl 系統）

| Tool | 用途 |
|------|------|
| `firecrawl_search` | Web 検索（本文抽出込み）。まずこれを使う |
| `firecrawl_scrape` | URL が判明しているページを Markdown で取得 |
| `firecrawl_map` | サイト内の URL 一覧を取得（ドキュメントサイトの探索） |
| `firecrawl_extract` | 複数ページから構造化データを抽出 |
| `firecrawl_parse` | PDF など URL 上のドキュメントをパース |

### How to Route

2 つのサブエージェントを **同時に起動**する（片方の結果を待たない）。

```
# 系統 1: 一次情報
Task tool parameters:
- subagent_type: "general-purpose"
- run_in_background: true
- prompt: |
    Research the following using the firecrawl MCP tools: {topic}

    Start with firecrawl_search, then firecrawl_scrape the authoritative
    sources (official docs / release notes) for detail.
    Cite the source URL for every claim.

    Save full output to: .claude/docs/research/{topic}-sources.md
    Return CONCISE summary.

# 系統 2: 実装知見
Task tool parameters:
- subagent_type: "general-purpose"
- run_in_background: true
- prompt: |
    Run OpenCode research on: {topic}

    opencode run --agent plan -m github-copilot/gpt-5.6-sol "{research question}" < /dev/null

    Keep `--agent plan` and the `< /dev/null`, and do NOT append 2>/dev/null — see
    "OpenCode リサーチの実行" in rules/tool-routing.md for why.
    Expect this to take over 10 minutes.

    Save full output to: .claude/docs/research/{topic}-opencode.md
    Return CONCISE summary, and flag anything you are NOT confident about
    so it can be checked against the firecrawl sources.
```

両者の結果を Claude が統合する。**食い違いがあれば firecrawl の一次情報を採用**し、相違点と採用した方を記録する。

### Triggers

| User Input | Action |
|------------|--------|
| 「調べて」「リサーチして」「最新バージョンは」 | firecrawl + OpenCode を並列実行 |
| 「公式ドキュメントを見て」「仕様を確認して」 | firecrawl 主体（OpenCode は任意） |
| 「既知の不具合はある?」「脆弱性を確認して」 | firecrawl + OpenCode を並列実行 |

### Exceptions (Claude handles directly)

- URL が 1 本だけ分かっていて要約するだけ（WebFetch で足りる）

## Git Operations

**書き込み系の git 操作は `/deploy`（Ad-hoc Git モード）経由で実行する。読み取り系は Claude が直接実行してよい。**

| 分類 | コマンド | 実行者 |
|------|---------|--------|
| **書き込み** | `add`, `commit`, `push`, `pull`, `merge`, `rebase`, `cherry-pick`, `tag`（作成）, `stash`（push/pop/apply）, `reset`, `revert`, `branch`（作成）, `checkout`, `switch` | `/deploy` |
| **読み取り** | `status`, `log`, `diff`, `show`, `blame`, `branch`（一覧）, `fetch`, `stash list/show`, `rev-parse`, `config --get` | Claude が直接 |

`/team-implement` `/team-review` `/deploy` の fork 内では、書き込み系も直接実行する。

### 保護ブランチ

- **`release` / `staging` / `main`（master 含む）への直接コミット・push は、ユーザーの明示的な許可がない限り禁止**。反映は必ず PR / MR 経由
- 保護ブランチ上で書き込み操作が必要になったら、feature ブランチを作成してから実行する（tier=XS も同様）

### ホスティング CLI

`origin` のリモート URL で判定し、GitLab（セルフホスト含む）は `glab`、GitHub は `gh` を使う。GitHub MCP は不安定なため使わない。

## GitHub / Linear MCP Operations

### アドホック操作

スキル外での MCP 操作はサブエージェント経由で実行する。

```
Task tool parameters:
- subagent_type: "general-purpose"
- prompt: |
    Perform the following MCP operation.
    Task: {description}
    Use Linear/GitHub MCP tools directly.
    Report results back concisely in Japanese.
```

### Linear Triggers

| User Input | Action |
|------------|--------|
| 「Linearにissue作って」 | サブエージェント経由で実行 |
| 「チケットを更新して」 | サブエージェント経由で実行 |
| 「タスクのステータスを変えて」 | サブエージェント経由で実行 |

## Operational Commands (Subagent Routing)

以下の操作はアドホック実行時にサブエージェント経由で実行する（コンテキスト分離のため）。
`context: fork` スキル内では直接実行される。

### 共通ルーティング方法

```
Task tool parameters:
- subagent_type: "general-purpose"
- prompt: |
    Task: {description}
    Execute the commands directly and report results concisely.
```

### 対象操作と Triggers

| 操作 | コマンド例 | Triggers |
|------|-----------|----------|
| **依存管理** | `uv add/remove/sync` | 「パッケージを更新して」「依存を追加して」 |
| **Lint/Format** | `ruff check .`, `ruff format .` | 「lintして」「フォーマットして」 |
| **Docker** | `docker build/run`, `docker compose` | 「コンテナを起動して」「docker build して」 |
| **環境セットアップ** | `uv sync`, version checks | 「環境セットアップして」「バージョン確認して」 |
| **ファイル整理** | bulk rename, directory restructure | 「ファイルを整理して」「リネームして」 |
| **シェルスクリプト** | Bash script creation | 「スクリプト書いて」「自動化して」 |
| **Changelog** | `git log` → formatted notes | 「changelog作って」「リリースノート生成して」 |

### 例外（Claude が直接実行してよい操作）

- ファイル内容の編集（Edit/Write ツール）
- 新規ソースコード作成（Claude の領域）

### 外部リサーチを使うケース（外部情報が必要な場合のみ）

以下の場合はサブエージェント内で firecrawl MCP / OpenCode を併用する：

- パッケージの最新バージョン・脆弱性チェック
- 未知のライブラリの使い方調査

```
firecrawl_search: "Check the latest stable versions and known issues for: {packages}"
→ 公式ドキュメント / リリースノートは firecrawl_scrape で本文を取得

opencode run --agent plan -m github-copilot/gpt-5.6-sol "{same question}"
→ `--agent plan` / `< /dev/null` / 「2>/dev/null を付けない」は必須。理由は「OpenCode リサーチの実行」参照
→ バージョン番号など「現在の事実」は firecrawl の結果を正とする
```

