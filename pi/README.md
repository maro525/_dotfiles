# pi 設定移植計画

Claude Code + OpenCode CLI の設定を pi に移植するための分析ドキュメント。

## 概要

| カテゴリ | Claude Code | OpenCode | pi | 移植可否 |
|---------|-------------|----------|----|---------|  
| グローバル指示 | CLAUDE.md | `../AGENTS.md`（root 共通） | `../AGENTS.md`（root 共通） | ✅ 統一済み |
| ワークフローコマンド | commands/*.md | commands/*.md | skills/*/SKILL.md | ✅ 作成済み |
| サブエージェント定義 | agents/*.md | agents/*.md | pi subagent tool | ✅ 作成済み |
| パーミッション | permissions (allow/deny/ask) | permission (allow/ask/deny) | extensions/permissions.ts | ✅ 作成済み |
| フック | PostToolUse/UserPromptSubmit hooks | ❌ | extensions | ⚠️ 拡張機能で代替 |
| MCP サーバー | Figma/GitHub/Linear/Playwright/Stitch | Linear | ❌ 非対応 | ⚠️ 外部ツール連携 |
| スキルシステム | Skill(tool) | skills | pi skills | ✅ 互換 |
| タスクファイル | .claude/docs/decisions/task-*.md | 共有 | 共有 | ✅ 同じ構造 |
| 自動ルーティング | agent-router.py | ❌ | ❌ | ⚠️ スキルトリガーで代替 |

## 移植済みファイル

グローバル指示は repo ルートの `../AGENTS.md`（Claude / OpenCode / pi で共有）を参照。

```
pi/
├── skills/
│   ├── orchestrate/SKILL.md       # ✅ メインオーケストレーター
│   ├── startproject/SKILL.md      # ✅ 計画フェーズ
│   ├── team-implement/SKILL.md    # ✅ 実装フェーズ
│   ├── team-review/SKILL.md       # ✅ レビューフェーズ
│   └── deploy/SKILL.md            # ✅ デプロイフェーズ
├── agents/
│   ├── planner.md                 # ✅ 計画フェーズ用エージェント
│   ├── implementer.md             # ✅ 実装フェーズ用エージェント
│   ├── reviewer.md                # ✅ レビューフェーズ用エージェント
│   └── deployer.md                # ✅ デプロイフェーズ用エージェント
├── prompts/
│   └── orchestrate.md             # ✅ ワークフローpromptテンプレート
├── extensions/
│   └── permissions.ts             # ✅ パーミッション + Atuin履歴統合
└── README.md                      # ✅ 本ファイル
```

## 必要な追加設定

### 1. pi 設定更新(settings.json)

```jsonc
// ~/.pi/agent/settings.json に追加
{
  "packages": ["npm:pi-subagents"],
  "defaultProvider": "fireworks",
  "defaultModel": "accounts/fireworks/models/qwen3p6-plus",
  // 追加提案
  "env": {
    "PI_DONT_ASK_MODE": "0",  // 1 で自動承認モード
    "PI_VERBOSE": "1"
  }
}
```

### 2. Linear 連携

**現状:** Claude Code では MCP サーバー (`mcp__linear-server__*`) を使用。

**pi での代替案:**
- オプションA: Linear API を直接叩く bash スクリプトを作成
- オプションB: `gh` CLI と Linear Webhook を組み合わせて使用
- オプションC: pi extension として Linear API 連携を実装

**推奨:** オプションA(最もシンプル)

```bash
# Linear API 呼び出し例
curl -s -X POST "https://api.linear.app/graphql" \
  -H "Content-Type: application/json" \
  -H "Authorization: ${LINEAR_API_KEY}" \
  -d '{"query": "{ issues { nodes { id title identifier } } }"}'
```

### 3. Atuin 連携

**現状:** Claude Code の hooks で `atuin hook claude-code` を実行。

**pi での代替:** `permissions.ts` 内に Atuin 履歴追跡を統合済み。

> `atuin.ts` は削除済み（2026-05-01）。
> `atuin hook install pi` で配置されるテンプレートは使用しない。

### 4. agent-router.py 相当

**現状:** Claude Code の UserPromptSubmit hook で `python3 "$HOME/.claude/hooks/agent-router.py"` を実行。

**pi での代替:**
- ❌ pi には UserPromptSubmit hook に相当する機能がない
- ✅ スキルの `description` フィールドでトリガーキーワードを設定することで類似機能を実現
- ✅ または pi extension でカスタムルーティングを実装可能

**推奨:** スキルトリガーで代替(スキルファイルの `description` にキーワードを記載)

### 5. パーミッションシステム ✅

**ファイル:** `pi/extensions/permissions.ts`

claude/settings.json の `permissions` をそのまま移植。

| カテゴリ | パターン数 | 動作 |
|---------|-----------|------|
| **allow** | 69 | 確認なしで即実行 |
| **deny** | 4 | 即ブロック (`sudo`, `rm -rf`, `wget`, `git reset`) |
| **ask** | 2 | ユーザーに確認 (`git rebase`, `rm`) |
| **default** | — | 不明なコマンドは `ask` 扱い |

**デプロイ方法:**
```bash
mkdir -p ~/.pi/agent/extensions/permissions
ln -sf $(pwd)/pi/extensions/permissions.ts ~/.pi/agent/extensions/permissions/index.ts
```

pi で `/reload` すれば有効になる。

### 6. サブエージェント定義

**現状:** Claude Code の `agent` ツール、OpenCode の `@agent` mention でサブエージェントを起動。

**pi での代替:** ✅ `subagent` ツールで完全に同等の機能を実現可能。

```
# SINGLE モード(1つのタスク)
subagent {
  agent: "default",
  task: "startproject: {task description} --tier=M --task-file={TASK_FILE}"
}

# CHAIN モード(順次パイプライン)
subagent {
  chain: [
    {agent: "default", task: "Understand codebase for {task}"},
    {agent: "default", task: "Design based on {previous}"},
    {agent: "default", task: "Plan implementation based on {previous}"}
  ]
}

# PARALLEL モード(並列実行)
subagent {
  tasks: [
    {agent: "default", task: "Quality review: {files}", output: "quality.md"},
    {agent: "default", task: "Security review: {files}", output: "security.md"},
    {agent: "default", task: "Logic review: {files}", output: "logic.md"}
  ],
  concurrency: 3
}
```

## ワークフロー実行方法

### 通常モード

```
/orchestrate NSKETCH-573 をやりたいです
```

pi は以下のフローを自動実行:
1. STEP 0: tier 判定
2. STEP 1: Linear タスク確認
3. STEP 2: タスクファイル作成
4. STEP 3: startproject スキル実行
5. STEP 4: team-implement スキル実行
6. STEP 5: team-review スキル実行(tier=XS はスキップ)
7. STEP 6: deploy スキル実行
8. STEP 7: 完了報告

### DONT-ASK MODE

```
# 環境変数を設定
export PI_DONT_ASK_MODE=1

# 実行
/orchestrate NSKETCH-573 をやりたいです
```

DONT-ASK MODE では:
- Gate 1(計画承認)をスキップして自動続行
- Gate 3(レビュー FAIL 時)に自動で team-implement に戻りリトライ
- 未コミット変更を自動コミット

## 制限事項

1. **ファイル読み書きのパーミッション**: `Read(**/.env*)` 等のパス制限は extension で制御不可。AGENTS.md で指示するしかない。

2. **MCP サーバー非対応**: pi 自体は MCP プロトコルをサポートしていない。外部ツール(Linear API curl, gh CLI, agent-browser スキル等)で代替する必要がある。

3. **サブエージェント間のメモリ共有**: pi の subagent は独立したコンテキストで実行される。Claude Code の `context: fork` とは異なり、親子間での変数共有は明示的にファイル経由で行う必要がある。

4. **Skill ツールの連鎖**: Claude Code の `Skill(tool)` 呼び出しと異なり、pi のスキルは TUI でトリガーされるか、サブエージェントの task として呼び出す必要がある。スキル内から他のスキルを直接呼び出すことはできない。

5. **ask パターンの確認方法**: ターミナルの `read -p` でユーザー入力を待つため、非対話モードでは機能しない。

## 次のステップ

1. [ ] Linear 連携 extension を作成(または API スクリプト)
2. [x] パーミッション extension 作成 → `pi/extensions/permissions.ts`
3. [x] サブエージェント定義ファイル作成 → `pi/agents/*.md`
4. [x] ワークフローpromptテンプレート作成 → `pi/prompts/orchestrate.md`
5. [ ] agent-router.py 相当の pi extension を作成(任意)
6. [ ] テスト実行 `/orchestrate` で動作確認

## 参考ファイル

- Claude Code 設定: `claude/settings.json`, `claude/CLAUDE.md`, `claude/commands/*.md`
- 共通グローバル指示: `AGENTS.md`（repo root）
- OpenCode 設定: `opencode/opencode.jsonc`, `opencode/agents/*.md`, `opencode/commands/*.md`, `opencode/config.toml`
- pi 設定: `~/.pi/agent/settings.json`, `pi/skills/*/SKILL.md`, `pi/agents/*.md`, `pi/extensions/permissions.ts`
