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

# 補助コマンド（結果確認・後始末・変更確認・write worktree 操作）。
# 連結・コマンド置換・リダイレクト・改行を含むものは弾く（スマグリング/任意ファイル書き込み防止）。
# 注: codex exec を含む one-shot ブロックは上で許可済み。ここは「ブロックを分けて」実行する補助系で、
#     いずれも cat/rm/git/echo の単純な単発コマンドしか想定しないため >, <, 改行は不要。
nl=$(printf '\nx'); nl=${nl%x}                          # 改行1文字
case "$c" in
  # 連結/置換/リダイレクト/改行/git の任意ファイル read・write オプション → 不許可へ落とす
  *'&&'*|*'||'*|*'`'*|*'|'*|*';'*|*'$('*|*'>'*|*'<'*|*"$nl"*|*'--no-index'*|*'--output'*|*' -O'*) ;;
  # cat/rm は codex 出力ファイル(変数形)のみ。追加引数での任意ファイル read/削除を防ぐため完全一致。
  'cat "$OUT"'|'cat "$ERR"') exit 0 ;;
  'rm -f "$OUT" "$ERR"'|'rm -f "$OUT"'|'rm -f "$ERR"') exit 0 ;;
  "git status"*|"git diff"*) exit 0 ;;                 # 編集タスクの変更確認(--no-index/--output は上で拒否済)
  "git wt --nocd "*"ai-codex/"*) exit 0 ;;             # write role: ai-codex worktree 作成
  "git wt -d "*"ai-codex/"*|"git wt -D "*"ai-codex/"*) exit 0 ;; # ai-codex worktree 後始末
  "git -C "*"ai-codex"*" status"*|"git -C "*"ai-codex"*" diff"*) exit 0 ;; # worktree の差分確認
  "echo "*) exit 0 ;;                                   # rc 報告等
esac

# deny のまま（統合は親 Claude + codex-worker-apply の責務。ドライバーには許可しない）:
#   git apply / git commit / git checkout / git reset / git clean / git add

echo "ブロック: codex-worker はタスクを自力実行してはならない。codex exec への委譲のみ許可（必須プロトコル参照）。" >&2
exit 2
