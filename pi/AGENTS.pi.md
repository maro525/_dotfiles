### pi 固有

- Git 操作: `bash` ツールで直接実行
- Linear 連携: MCP または `gh` CLI で代替
- 設計相談: OpenCode CLI（`opencode run -m github-copilot/gpt-5.5 "..."`）またはサブエージェント
- サブエージェント起動: pi の `subagent` ツールを使用

#### DONT-ASK MODE

環境変数 `PI_DONT_ASK_MODE=1` が設定されている場合:

| 通常の確認 | DONT-ASK 時の動作 |
|-----------|------------------|
| tier 上書き確認 | 判定結果をそのまま使用して続行 |
| Gate 1 承認 | 自動承認して続行 |
| Gate 3 FAIL 時の判断 | 自動で team-implement に戻り1回リトライ |
| 未コミット変更の確認 | 自動コミットして続行 |
| 元ブランチ不明 | main にフォールバック |
