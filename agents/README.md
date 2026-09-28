# Agent-general phase skills

`/orchestrate` の 4 フェーズ（startproject / team-implement / team-review / deploy）を、**Claude 以外の CLI エージェント**（pi / cline / opencode / codex）でも回せるようにした [Agent Skills](https://agentskills.io/specification) 形式の定義。Claude 版（`../claude/commands/*.md`）は OUTPUT を返して orchestrate が TASK_FILE に書くが、こちらは**各フェーズが TASK_FILE の自分の節を自分で書く**。

主な使い道は `/orchestrate` の**フェーズ指定モード**（`../claude/commands/orchestrate.md` STEP 3P）: 既存 TASK_FILE の 1 フェーズを別 AI で 1 回実行し、別案（`### 案 {k}`）や別視点のレビュー（`### {m}回目（{ai}）`）として追記する。

## Layout

```
agents/
├── README.md
└── skills/
    ├── startproject/SKILL.md    # 計画: Brief / Design / Plan（--label ありなら ### 案 {k}）
    ├── team-implement/SKILL.md  # 実装: feature ブランチ + TDD、### {m}回目、Meta の branch/base
    ├── team-review/SKILL.md     # レビュー: 観点別（Quality/Logic → Security → Simplify）、判定 PASS/FAIL
    └── deploy/SKILL.md          # commit → push → PR/MR（gh / glab）、## deploy
```

配布先は `~/.agents/skills/{name}/`（`./sync-agents.sh`）。Cline だけは `~/.cline/skills/{name}` → `~/.agents/skills/{name}` の symlink で読ませる。

## 共通規約

4 つの SKILL.md はすべて同じ規約で書かれている。

| 項目 | 規約 |
|---|---|
| frontmatter | `name`（ディレクトリ名と同一）/ `description` / `metadata.phase` / `metadata.writes` のみ。CLI 固有のキーは使わない |
| 引数 | `"{task description} --task-file={TASK_FILE} [--tier=S\|M\|L] [--linear-id={ID}] [--label={実行者名}]"`。`--tier` / `--linear-id` は省略時 `## Meta` から読む |
| 書く場所 | 自分の `##` 節だけ。`## Meta` の `status:` は書かない（team-implement だけ `branch:` / `base:` を書く）。`##` 見出しは増やさない（kanban が `##` で列判定） |
| 見出し | startproject: `--label` あり → `### 案 {k}（{label}、{日時}）` + `#### Brief/Design/Plan`、なし → `### Brief/Design/Plan` を上書き。team-implement / team-review: `### {m}回目（{label}）`。deploy: `### PR / MR`（追加は `#### 追加 push（…）`） |
| 対話 | 質問できない環境では推定して続行し、`前提（推定）` として節に残す。Gate 1 は候補モード・非対話では待たず `gate1: 要確認` |
| 外部ツール | サブエージェント・Web 検索・Linear 連携は「あれば使う、無ければ自分で行い、その旨を書く」。Linear のステータスは変えない |
| 最終メッセージ | `### RESULT`（phase / task_file / written / section / linear / フェーズ固有行）+ `### SECTION`（書いた節の丸写し）。サンドボックスで書けなかったとき orchestrate がこれを代筆する |

Claude 固有要素（`context: fork`、`agent:`、`allowed-tools`、`model:`、AskUserQuestion、Agent ツール、hook、`$HOME/.claude/rules`）には依存しない。tier の意味・セキュリティ観点・git 保護ブランチなど必要な共通ルールは各 SKILL.md に内包してある。

## 各 CLI がスキルを探す場所

| CLI | 探索場所（一次情報） |
|---|---|
| pi | `~/.agents/skills/`、`.agents/skills/`（cwd から祖先、リポジトリルートまで）。**同名は最初に見つかった方が勝ち**（`~/.pi/agent/skills` が先） — [docs/skills.md](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/skills.md) |
| cline | プロジェクト `.cline/skills/`、`.clinerules/skills/`、`.claude/skills/`。グローバル `~/.cline/skills/` — [Skills](https://docs.cline.bot/customization/skills) |
| opencode | `.opencode/skills`、`~/.config/opencode/skills`、`.claude/skills`、`~/.claude/skills`、`.agents/skills`、`~/.agents/skills` — [Agent Skills](https://opencode.ai/docs/skills/) |
| codex | `$CWD/.agents/skills`、`$CWD/../.agents/skills`、`$REPO_ROOT/.agents/skills`、`$HOME/.agents/skills`、`/etc/codex/skills` — [Build skills](https://developers.openai.com/codex/skills) |

orchestrate のフェーズ指定モードは探索に頼らず、プロンプトで `Read {abs path}/SKILL.md and follow it` と絶対パスを渡す（CLI ごとの探索差を吸収するため）。

**各 CLI の起動オプション（モデル指定・最終メッセージの取り出しを含む）は `../claude/rules/tool-routing.md` の「外部 CLI のフェーズ実行」の表が唯一の定義。** この README には起動例を書かない（2 か所に書くと食い違う）。手で 1 フェーズを回すときも同じ表のコマンドに `"$(cat {prompt_file})"` を渡す。

### 権限

**全フェーズ同じ権限で動く（読み取り専用にしない）。** startproject / team-review も、team-implement / deploy と同じ「確認なしで編集・コマンド実行を許す」指定で起動する（理由は tool-routing.md「外部 CLI のフェーズ実行 › 権限」）。startproject / team-review が TASK_FILE 以外を変更しないのは SKILL.md の指示によるもので、起動オプションでは強制しない。orchestrate は起動前後の簡単な比較で TASK_FILE 以外の変化を報告する（orchestrate.md STEP 3P P5）。

### codex の注意

- 全フェーズ `-s workspace-write` に **`.git` を `writable_roots` に足す**（tool-routing.md の表）。`workspace-write` は writable root 配下の `.git` を読み取り専用にするため、そのままでは `git checkout -b` / `git commit` が失敗する。deploy は push のため `sandbox_workspace_write.network_access=true` も付ける。`-s danger-full-access` は使わない
- 最終メッセージは `-o {file}`（`--output-last-message`）でファイルに取る。stdout は `--json` を付けなくてもイベントログが混ざる
- `which -a codex` で複数見つかる環境（WSL で Windows 側の `npm` の codex が先に来る等）では、PATH の先頭がどちらかを `codex --version` で確認してから使う

### 実機の状態（2026-09-28）

| CLI | 状態 |
|---|---|
| pi | `pi -p --no-session --tools read,grep,find,ls[,bash]` で動作確認済み（`~/.agents/skills` が見える。`bash` ありでは TASK_FILE に自分で書けた）。`--tools` 制限なしの起動（tool-routing.md の表）は未検証。pi の bash で何が通るかは `~/.pi/agent/extensions/permissions/` の許可リストで決まる |
| cline | `cline --json -t 150` で動作確認済み |
| opencode | 429 quota_exceeded（retry-after 約 2.4 日）。復旧後に追試 |
| codex | 0.80.0 は ChatGPT アカウントで使えるモデルが無く全モデル失敗。**`npm i -g @openai/codex@latest` で更新してから使う** |

## 配布とセットアップ

```bash
./sync-agents.sh          # 対話モード。初回は各スキルで (p) を選び repo → ~/.agents/skills にコピー
./sync-agents.sh -n       # 非対話。HOME → repo の自動コピー（初回配布には使えない）
```

`sync-agents.sh` は `~/.agents/skills` のうち **この 4 スキルだけ**を扱う（残りは `npx skills` 管理。`.skill-lock.json` に触らない）。同期後に:

1. **Cline 用 symlink**: `~/.cline/skills/{name}` → `~/.agents/skills/{name}` を作る。既に何かあればスキップして警告（実体ディレクトリなら手で消してから再実行）。`sync-cline.sh` は symlink の先を辿らないので `cline/skills/` に重複は入らない
2. **pi の旧コピー**: `~/.pi/agent/skills/{startproject,team-implement,team-review,deploy,orchestrate}` に旧仕様（Decision Log 前提）のコピーが残っていると、pi はそちらを先に見つけて `~/.agents/skills` 側を無視する。スクリプトは警告だけ出す。中身が旧コピーであることを確認してから手で削除する:

   ```bash
   for s in startproject team-implement team-review deploy orchestrate; do
     diff -q ~/.pi/agent/skills/$s/SKILL.md ~/.agents/skills/$s/SKILL.md 2>&1 | head -1
   done
   rm -r ~/.pi/agent/skills/{startproject,team-implement,team-review,deploy,orchestrate}
   ```

   `orchestrate` は一般向けには作らない（Claude の `/orchestrate` が外部 CLI を呼ぶ側）ので、旧コピーは削除するだけでよい。

3. `~/.claude/skills` には置かない（Claude の `/startproject` などと名前が二重になる）

## Claude 版との対応

| 項目 | Claude 版（`claude/commands/*.md`） | 一般向け（`agents/skills/*/SKILL.md`） |
|---|---|---|
| TASK_FILE の書き手 | orchestrate（command は OUTPUT を返す） | 各フェーズ自身（`written: no` のときだけ orchestrate が代筆） |
| Linear | orchestrate が投稿・ステータス変更 | 連携ツールがあればコメントのみ。ステータスは変えない |
| `status:` | orchestrate が各 STEP で更新 | 書かない（フェーズ指定モードでも orchestrate は変えない） |
| 回数・候補 | `### {m}回目` | `### {m}回目（{label}）`、startproject は `### 案 {k}（{label}、{日時}）` |
| 承認（Gate 1） | AskUserQuestion で待つ | 質問できれば待つ。候補モード・非対話では `gate1: 要確認` |
| 並列レビュアー（team-review） | Claude / OpenCode / Security / Simplify を並列 | 同一モデルで観点を順に（Quality/Logic → Security → Simplify）。セカンドオピニオンは任意 |
| 外部リサーチ・設計相談 | firecrawl + `opencode run` | 使えるツールがあれば。無ければ「不可: {理由}」 |
| deploy の Ad-hoc Git モード | あり | なし（Deploy Workflow のみ） |
| 共通ルールの参照 | `$HOME/.claude/rules/*.md` | 各 SKILL.md に内包 |

一般向け定義から Claude 版を生成することはしない（構造が違う）。Claude 版を変えたら、この表を見て対応する SKILL.md を手で追随させる。

## フェーズ指定モードの流れ（orchestrate STEP 3P）

```
/orchestrate "--task-file=.claude/docs/decisions/task-X-feature.md --phase=startproject --ai=pi:google/gemini-2.5-pro"
   → ## startproject に ### 案 2（pi/google/gemini-2.5-pro、2026-09-28 10:00） を追記
/orchestrate "--task-file=… --phase=startproject --adopt=案 2"
   → 案 2 の #### Brief/Design/Plan を ### Brief/Design/Plan に昇格（見出しに — 採用）
/orchestrate "--task-file=… --phase=team-review --ai=codex"
   → ## team-review に ### 1回目（codex） を追記（status は変わらない）
```

どのフェーズも同じ権限で起動し（上の「権限」）、CLI が TASK_FILE に直接書く。実行日時は orchestrate がプロンプトで渡す（CLI 側で推定させない）。orchestrate は `## {phase}` 節内の期待見出し（`### 案 {k}（` / `### {m}回目（` の前方一致）が起動前より増えていなければ、最終メッセージの `### SECTION` から代筆する。startproject / team-review では起動前後で作業ツリー・HEAD・ref・stash を比べ、TASK_FILE 以外に変化があれば報告する。

## 検証

```bash
# 一般向け定義に Claude 固有語が無いこと・name がディレクトリ名と一致すること
grep -nE 'context: fork|agent:|allowed-tools|model:|AskUserQuestion|Agent ツール|hook|TodoWrite|mcp__|\.claude/rules|AGENTS\.md|CLAUDE\.md|subagent|opencode run|firecrawl|Claude|OpenCode' agents/skills/*/SKILL.md
for d in agents/skills/*/; do n=$(basename "$d"); grep -q "^name: $n$" "$d/SKILL.md" || echo "name mismatch: $n"; done

# kanban が ### 案 / ### {m}回目（label）で列判定を変えないこと
cd kanban && uv run pytest
```
