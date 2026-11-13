LANGUAGE PROTOCOL
  思考・コード: 英語 / ユーザー対話: 日本語

TIME ZONE
  ユーザーに見せる日時は日本時間（JST, UTC+9）で書く。UTC などのログ時刻は JST に直して示す

別モデルでのレビュー（このPC）
  レビューは別モデルに任せたいとき、opencode 経由で呼ぶ（外部ワークフローを導入していれば `~/.claude/rules/tool-routing.md` の「OpenCode リサーチの実行」に注意点がある）
  timeout -k 1m 20m opencode run --agent plan "{prompt}" < /dev/null
  モデルは指定しない（`opencode/opencode.jsonc` の既定に任せる）。
  MR やスレッドに書く役の名前は固定のまま。この経路で出した Review-Eval: の数字には「opencode 経由」と書き添える
