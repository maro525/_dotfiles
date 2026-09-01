# Cline CLI Config

Cline CLI (`npm i -g cline`) の設定のうち、**認証情報を含まないもの**だけをこのリポジトリで管理する。

## Cline の設定レイアウト

Cline は設定を 2 つのルートに分けて置く。

| パス | 用途 | 上書き手段 |
|------|------|-----------|
| `~/.cline/` | 設定ルート | `CLINE_DIR` / `--config <dir>` |
| `~/.cline/data/` | CLI が書く設定・状態 | `CLINE_DATA_DIR` / `--data-dir <dir>` |
| `~/Cline/` | ユーザーが書く Rules / Hooks / Workflows | — |

## Layout

```
cline/
├── README.md
├── global-settings.json     # ← ~/.cline/data/settings/global-settings.json
├── cline_mcp_settings.json  # ← ~/.cline/data/settings/cline_mcp_settings.json
├── Rules/                   # ← ~/Cline/Rules
├── Hooks/                   # ← ~/Cline/Hooks
├── Workflows/               # ← ~/Cline/Workflows
└── skills/                  # ← ~/.cline/skills（Cloudflare バンドルは除外）
```

`Rules/` `Hooks/` `Workflows/` `skills/` は現在すべて空（skills は Cloudflare
プラグイン由来のみ）。git は空ディレクトリを追跡しないため、中身を追加して
`sync-cline.sh` を実行した時点でリポジトリに現れる。

## 同期対象外（重要）

以下は **認証情報を含むため一切コピーしない**。`sync-cline.sh` は
HOME → repo / repo → HOME のどちらの方向でも触らない。

| ファイル | 含まれるもの |
|----------|-------------|
| `~/.cline/data/secrets.json` | `geminiApiKey` / `openAiNativeApiKey` |
| `~/.cline/data/settings/providers.json` | 各プロバイダの `apiKey`、Cline アカウントの OAuth トークン |
| `~/.cline/config.json` | `openAiApiKey`（Fireworks 経由・レガシー） |

`providers.json` にはデフォルトプロバイダとモデルの設定も入っているが、同じ
ファイルに API キーが同居しているためリポジトリでは管理しない。別マシンに移す
ときは `cline auth` で設定し直す:

```bash
cline auth -p gemini -m gemini-flash-latest -k "$GEMINI_API_KEY"
```

`cline auth` は `providers.json` の `lastUsedProvider` を書き換える。これが
`-P` 省略時に使われる既定プロバイダになる（`--help` の `(default: cline)` は
未設定時のフォールバックを説明した文言で、実際の既定値ではない）。

その他、同期しないもの:

| 対象 | 理由 |
|------|------|
| `~/.cline/data/globalState.json` | 旧形式の実行時状態。移行処理からしか読まれない |
| `~/.cline/data/settings/cli-notices.json` | 通知の既読フラグ |
| `~/.cline/data/{tasks,sessions,db,logs,cache}/` | セッション履歴・DB |
| `~/.cline/cli-node-extra-ca-certs.pem` | インストール時に生成される CA バンドル |
| `~/.cline/skills/` の Cloudflare プラグイン 11 個 | ベンダーコンテンツ（`lib/sync-common.sh` の `SYNC_COMMON_CLOUDFLARE_SKILLS`） |

## Usage

```bash
./sync-cline.sh        # 対話モード（差分を見て方向を選ぶ）
./sync-cline.sh -n     # 非対話（HOME → repo に一括コピー）
```
