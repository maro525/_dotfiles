# Tool Routing Rules

**Defines which tools and operations are delegated to which agent, and how skills are auto-routed.**

This file provides cross-cutting routing decisions.
外部リサーチは firecrawl MCP + OpenCode リサーチの二系統、設計相談は OpenCode、コードベース解析は Explore サブエージェントに振り分ける。

## Skill Auto-Routing

**ユーザーがスキル名を明示しなくても、`UserPromptSubmit` hook (`agent-router.py`) がプロンプトを分析し、適切なスキルを `additionalContext` で提案する。**

→ 詳細: `.claude/rules/skill-auto-routing.md`

### ルーティング優先順位

```
1. 明示的スキルコマンド (/startproject 等) → そのまま実行
2. スキル意図検出 + 軽量タスクでない → スキルを提案
3. エージェント意図検出 (OpenCode / firecrawl MCP / Explore) → エージェントを提案
4. いずれにも該当しない → 通常応答
```

### スキル意図の発火条件

| スキル | 典型的なトリガー |
|--------|----------------|
| `/startproject` | 「新機能を作りたい」「issue #Nを進めたい」「計画して」 |
| `/team-implement` | 「実装して」「承認します」「この計画で進めて」 |
| `/team-review` | 「レビューして」「品質チェック」「実装完了」 |
| `/fs-ops` | 「ディレクトリを作って」「ファイルを削除して」「移動して」 |
| `/deploy` | 「PRを作って」「pushして」「デプロイ」 |

### 発火しないケース

- 質問・説明依頼
- 単発の軽微な操作（コミット、lint、テスト実行など）
- 短すぎるプロンプト（5文字未満）

## `context: fork` スキルの直接実行

以下のスキルは `context: fork` で実行され、メインのルーティングフックを経由しない。
スキル内では git/ruff/uv/gh 等を直接実行する（サブエージェント経由不要）：

| スキル | 直接実行する操作 |
|--------|----------------|
| `/team-implement` | git checkout/branch、ruff、pytest、uv、Linear MCP |
| `/team-review` | git diff/log、pytest、ruff、Linear MCP |
| `/fs-ops` | mkdir、rm、cp、mv、chmod、ln、touch |
| `/deploy` | git push、gh pr create、git checkout、Linear MCP |

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
| PDF / 画像 (ローカル) | **Claude 直接** | Read ツール（PDF・画像はネイティブ対応） |
| PDF / 記事 (URL) | **firecrawl MCP** | `firecrawl_parse` / `firecrawl_scrape` |
| 音声・動画 | **未対応** | 委託先なし。ユーザーに扱い方を確認する |
| Codebase analysis | **Explore subagent** | `Explore`（推奨）or `general-purpose` |
| Library research | **firecrawl MCP + OpenCode** | `firecrawl_search` で一次情報 + OpenCode で実装知見 |
| Design decisions | **OpenCode** | Subagent or Agent Teams |
| git (all operations) | **`/deploy` skill** | Deploy Workflow or Ad-hoc Git モード |
| docker/ruff/uv (in `context: fork` skills) | **Direct** | スキル内で直接実行 |
| docker/ruff/uv (ad-hoc) | **Subagent** | サブエージェント経由で直接実行 |
| GitHub MCP / Linear MCP | **Direct or Subagent** | スキル内は直接、アドホックはサブエージェント |

## External Research via firecrawl MCP + OpenCode

外部リサーチは **二系統を並列実行**し、Claude が突き合わせて統合する（`gemini` CLI は廃止済み）。

| 系統 | ツール | 得意分野 |
|------|-------|---------|
| **一次情報** | firecrawl MCP | 公式ドキュメント・リリースノートの実文面。出典 URL が取れる |
| **実装知見** | OpenCode CLI | 学習済み知識に基づく設計上の勘所・落とし穴・比較 |

**併用の理由**: firecrawl は「現在の事実」を出典付きで取れるが解釈はしない。OpenCode は解釈と経験則を出せるが出典を持たない。両者が食い違った場合は **firecrawl の一次情報を優先**し、相違点を Decision Log に残す。

### OpenCode リサーチの実行

```bash
opencode run -m openai/gpt-5.6-sol-pro "{research question}" 2>/dev/null
```

- モデルが `Quota exceeded` 等で失敗した場合は `github-copilot/gpt-5.6-sol` にフォールバックする
- サブエージェント経由で実行し、メインコンテキストを汚さない

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

    opencode run -m openai/gpt-5.6-sol-pro "{research question}" 2>/dev/null
    On "Quota exceeded" or model error, retry with:
    opencode run -m github-copilot/gpt-5.6-sol "{research question}" 2>/dev/null

    Save full output to: .claude/docs/research/{topic}-opencode.md
    Return CONCISE summary, and flag anything you are NOT confident about
    so it can be checked against the firecrawl sources.
```

両者の結果を Claude が統合する。**食い違いがあれば firecrawl の一次情報を採用**し、相違点を TASK_FILE の Decision Log に記録する。

### Triggers

| User Input | Action |
|------------|--------|
| 「調べて」「リサーチして」「最新バージョンは」 | firecrawl + OpenCode を並列実行 |
| 「公式ドキュメントを見て」「仕様を確認して」 | firecrawl 主体（OpenCode は任意） |
| 「既知の不具合はある?」「脆弱性を確認して」 | firecrawl + OpenCode を並列実行 |

### Exceptions (Claude handles directly)

- URL が 1 本だけ分かっていて要約するだけ（WebFetch で足りる）
- ローカルの PDF / 画像の読み取り（Read ツールがネイティブ対応）

## Codebase Analysis via Explore Subagent

コードベース解析は Explore サブエージェント（ローカルツールのみ、Web アクセスなし）に振り分ける。

### Scope

- Repository-wide architecture analysis
- Cross-module dependency understanding
- Pattern discovery across the codebase
- Data flow and impact analysis
- Code structure overview

### How to Route

```
Task tool parameters:
- subagent_type: "Explore"  (preferred; general-purpose if edits are needed)
- run_in_background: true
- prompt: |
    Analyze the codebase: {description}

    Use Grep/Glob/Read to map structure, then read the key files in detail.
    Specify search breadth ("medium" / "very thorough") explicitly.

    Save full output to: .claude/docs/research/{topic}.md
    Return CONCISE summary.
```

### Triggers

| User Input | Action |
|------------|--------|
| 「コードベースを理解して」「アーキテクチャ分析して」 | Explore サブエージェントに委託 |
| 「コード全体を見て」「横断的に分析して」 | Explore サブエージェントに委託 |
| 「依存関係を調べて」「影響範囲を分析して」 | Explore サブエージェントに委託 |

### Exceptions (Claude handles directly)

- Reading a specific single file (Read tool)
- Searching for a specific symbol/function (Grep/Glob tools)
- Quick reference during implementation (targeted file reads)

## Git Operations

**全てのアドホック git 操作は `/deploy` スキル経由で実行する。**

`/deploy` スキルは 2 つのモードを持つ:
- **Deploy Workflow モード**: PR 作成 + push + Linear 投稿（従来の deploy フロー）
- **Ad-hoc Git モード**: 単発の git 操作（commit, log, diff, branch 等）

### Push/Pull 分類（Ad-hoc Git モード）

Ad-hoc Git モードでは、操作を **Push-type（書き込み）** と **Pull-type（読み取り）** に分類する：

| 分類 | コマンド | 特徴 |
|------|---------|------|
| **Push-type（書き込み）** | `git add`, `git commit`, `git push`, `git merge`, `git rebase`, `git cherry-pick`, `git tag`（作成）, `git stash pop/apply`, `git reset`, `git revert` | リポジトリの状態を変更する |
| **Pull-type（読み取り）** | `git log`, `git diff`, `git show`, `git blame`, `git status`, `git branch`（一覧）, `git pull`, `git fetch`, `git stash list/show` | リポジトリの状態を読み取るのみ |

**main ブランチ保護**: Push-type 操作で main/master 上にいる場合、feature ブランチを自動作成してから実行する。Pull-type 操作にはブランチ制限なし。

→ 詳細: `.claude/skills/deploy/SKILL.md`

### `context: fork` スキル内

`/team-implement`, `/team-review`, `/deploy` はスキル内で git コマンドを直接実行する。

### アドホック操作

スキル外でのアドホックな git 操作は **`/deploy` スキル（Ad-hoc Git モード）** 経由で実行する。
`/deploy` は `context: fork` で動作するため、コンテキスト分離が保証される。

#### Claude が直接実行してよい操作（例外）

- `git status`（現在の状態確認のみ）
- `git branch --show-current`（現在のブランチ名取得）
- `git rev-parse`, `git config --get`（情報取得）
- `.gitignore` 等の設定ファイル読み取り（Read ツール経由）

#### `/deploy` スキル経由で実行する操作

| 操作 | コマンド例 | タイプ |
|------|-----------|--------|
| コミット | `git add`, `git commit` | Push-type |
| ブランチ | `git branch`, `git checkout`, `git switch`, `git merge` | Push-type |
| 履歴参照 | `git log`, `git diff`, `git show`, `git blame` | Pull-type |
| リモート送信 | `git push` | Push-type |
| リモート取得 | `git pull`, `git fetch` | Pull-type |
| その他 | `git stash`, `git rebase`, `git cherry-pick`, `git tag` | Push/Pull mixed |

### Git Triggers

| User Input | Action |
|------------|--------|
| 「コミットして」「pushして」 | `/deploy` スキル経由で実行 |
| 「PRを作って」「ブランチを切って」 | `/deploy` スキル経由で実行 |
| 「git log見せて」「差分を見せて」 | `/deploy` スキル経由で実行 |
| 「履歴を調べて」「blame して」 | `/deploy` スキル経由で実行 |

## Linear ステータス遷移

**各スキルが Linear タスクのステータスを適切なタイミングで変更する。**

| スキル | タイミング | ステータス変更 |
|--------|----------|--------------|
| `/team-implement` | Step 0（実装開始時） | → "In Progress" |
| `/team-review` | Step 0（レビュー開始時） | → "In Progress" |
| `/deploy` | Step 5-2（デプロイ完了後） | → "In Review" |

## GitHub / Linear MCP Operations

### `context: fork` スキル内

`/team-implement`, `/team-review`, `/deploy` はスキル内で git コマンドによる情報取得 + Linear MCP を直接実行する。

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

opencode run -m openai/gpt-5.6-sol-pro "{same question}" 2>/dev/null
→ Quota exceeded 等で失敗したら github-copilot/gpt-5.6-sol にフォールバック
→ バージョン番号など「現在の事実」は firecrawl の結果を正とする
```

---

## Adding New Routes

To add a new tool routing rule:

1. Add entry to the **Routing Table** above
2. Define **Scope** (what operations are covered)
3. Define **How to Route** (subagent prompt template)
4. Define **Trigger Detection** (user input patterns)
5. Note any **Exceptions** (when Claude handles directly)
