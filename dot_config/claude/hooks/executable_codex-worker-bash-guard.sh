#!/bin/bash
# codex-worker subagent 専用 PreToolUse guard (agent frontmatter hooks から起動)
# 目的: haiku ドライバーが codex exec に委譲せず自力でタスクを解く「近道」を塞ぐ nudge。
# 注意: これはセキュリティ境界ではない。実際の隔離は Claude の Bash sandbox + tools:Bash 制限が担う。
#       本 guard は「codex を使わず自力で答える」インスペクト系コマンドを止めるのが役目。

input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command // empty')
[ -z "$cmd" ] && exit 0

# 先頭の空白・改行を除去（先頭が改行のコマンドを誤ブロックしないため）
c="${cmd#"${cmd%%[![:space:]]*}"}"

# codex を使うコマンドは許可（委譲の本旨）。one-shot 一括コマンドも codex exec を含むため通る。
# heredoc 本文は任意文字を含むため、ここでは連結チェックをしない。
case "$c" in
  *"codex exec"*) exit 0 ;;
esac

# 補助コマンド（結果確認・後始末・変更確認）。連結やコマンド置換を含むものは弾く（スマグリング防止）。
case "$c" in
  *'&&'*|*'||'*|*'`'*|*'|'*|*';'*|*'$('*) ;;            # 連結あり → 不許可へ落とす
  'cat "$'*|'cat $'*|"cat /tmp/codex"*) exit 0 ;;       # codex 出力ファイルの確認のみ（任意ファイル読みは不可）
  'rm -f "$'*|'rm -f $'*|"rm -f /tmp/codex"*) exit 0 ;; # 作業ファイルの後始末
  "git status"*|"git diff"*) exit 0 ;;                 # 編集タスクの変更確認
  "echo "*) exit 0 ;;                                   # rc 報告等
esac

echo "ブロック: codex-worker はタスクを自力実行してはならない。codex exec への委譲のみ許可（必須プロトコル参照）。" >&2
exit 2
