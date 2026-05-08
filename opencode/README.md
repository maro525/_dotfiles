# OpenCode Config (Port of Claude Code Workflow)

Claude Code 版の `orchestrate + 4 subcommands` フローを OpenCode CLI 用に移植したもの。

## Layout

```
opencode/
├── AGENTS.md            # OpenCode 用グローバル指示（pi は pi/AGENTS.md と独立）
├── opencode.jsonc       # 主設定（model / permission / MCP）
├── agents/              # 各フェーズの subagent 定義（実体）
│   ├── startproject.md
│   ├── team-implement.md
│   ├── team-review.md
│   └── deploy.md
└── commands/            # スラッシュコマンド（薄いラッパー）
    ├── orchestrate.md   # メインオーケストレーター（@agent で駆動）
    ├── startproject.md  # → agents/startproject.md
    ├── team-implement.md
    ├── team-review.md
    └── deploy.md
```

## Deployment

### Global（全プロジェクト共通）

```bash
mkdir -p ~/.config/opencode/{agents,commands}
cp AGENTS.md           ~/.config/opencode/
cp opencode.jsonc      ~/.config/opencode/
cp agents/*.md         ~/.config/opencode/agents/
cp commands/*.md       ~/.config/opencode/commands/
```

### Per-project

リポジトリ直下に `.opencode/` として配置:

```bash
mkdir -p .opencode/{agents,commands}
cp -r opencode/agents/*.md    .opencode/agents/
cp -r opencode/commands/*.md  .opencode/commands/
```

## Portability Notes

Claude Code 版と完全に一致しない点:

| 機能 | Claude Code | OpenCode 版 |
|------|-------------|-------------|
| スキル連鎖 | `Skill` tool で別 skill 呼出 | `@agent-name` mention で呼出 |
| `context: fork` | ネイティブ | `mode: subagent` + `subtask: true` で同等 |
| UserPromptSubmit hook (`agent-router.py`) | あり | **なし**（自動スキル提案は不可） |
| `AskUserQuestion` / `TodoWrite` ツール | あり | `todowrite` は OpenCode にもあり / 質問は通常の対話で代替 |
| `Agent` tool（サブエージェント起動） | あり | `task` tool / `@agent` mention |
| Linear MCP | `mcp__linear-server__*` | 同 MCP をそのまま利用可能 |
| agent-browser MCP | あり | 同 MCP または Playwright MCP |
| `/simplify` など design skills | あり | 未移植（必要なら個別移植） |

## Limitations

1. **自動ルーティングなし**: Claude Code の `agent-router.py` 相当が OpenCode にないため、ユーザーは明示的に `/orchestrate` を呼ぶ必要がある。
2. **スキル間呼出しの制約**: OpenCode のコマンドは他のコマンドを直接呼べない。orchestrate はサブエージェント `@` mention で連鎖させる設計。
3. **`context: fork` の完全一致不可**: `subtask: true` で近似するが、親子間のトークン共有挙動は若干異なる。
4. **DONT-ASK MODE**: Claude Code 側の環境変数連動（`CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING` など）は OpenCode にない。必要なら agent 内で環境変数チェックを明示的に実装する。

## Testing

```bash
# OpenCode を起動
opencode

# TUI 内で試す
/orchestrate NSKETCH-573 をやりたいです
/startproject 新機能を追加したい
/team-review レビューして
```

## 参考

- 元 Claude Code 版: `../claude/commands/`
- OpenCode 公式: https://opencode.ai/docs/
