LANGUAGE PROTOCOL
  思考・コード: 英語 / ユーザー対話: 日本語

TIME ZONE
  ユーザーに見せる日時は日本時間（JST, UTC+9）で書く。UTC などのログ時刻は JST に直して示す

GPT のレビュー（このPC）
  本物の codex はこのPCでは gpt-6 に届かない。自分で呼ぶときは opencode を使う（注意点は ~/.claude/rules/tool-routing.md の「OpenCode リサーチの実行」）
  timeout -k 1m 20m opencode run --agent plan -m github-copilot/gpt-6-astra "{prompt}" < /dev/null
  `codex` コマンドは ~/scripts/codex-opencode-shim.mjs へのリンク（~/.local/bin/codex）で、opencode に読み替える。
  codex を直接呼ぶスクリプト（review-eval.mjs・review-weekly-gpt6.sh）はこれで動く。通すのは exec --sandbox read-only だけ。リンクを消せば本物に戻る
  MR やスレッドに書く役の名前は gpt-6 のまま。この経路で出した Review-Eval: の数字には「opencode 経由」と書き添える
