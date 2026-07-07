#!/bin/sh
# Claude Code hook (SessionStart / UserPromptSubmit):
# Herdr のサイドバー agents 欄に session name (無ければ repo:branch) を出し、
# どのセッション・リポジトリの worker かを一目で識別できるようにする。
# あわせて未 pin の workspace label を repo 名で pin し、フォルダ名への
# 自動追従を止める。
#
# - agents 行の描画は「1行目=workspace label / 2行目=状態 · display_agent
#   (無ければ agent rename 名 → 検知 agent 名) · custom_status」(実機確認済)。
#   pane title は agents 欄には出ないため、--display-agent で報告する。
# - session name は transcript (jsonl) の custom-title レコード末尾が現在名。
#   Claude Code が自動生成・自動更新するため初回ターン以降はほぼ常に存在する。
#   name あり: display_agent=name, custom_status=repo:branch (幅が余れば見える)
#   name なし: display_agent=repo:branch (従来表示)
# - herdr 管理の integration (herdr-agent-state.sh) は編集禁止のため、
#   「add custom hooks beside this file」方針に従った自作 hook。
# - pane.report_metadata は表示専用。agent の state/通知/rollup には影響しない。
#   同一 source の再報告は全項目置き換え(マージされない)。
# - UserPromptSubmit でも発火させるのは、セッション途中の branch 切替に追従するため。
set -eu

# UserPromptSubmit の stdout は context に注入されるため、一切出力しない
exec >/dev/null 2>&1

# hook 入力 JSON (session_id / transcript_path を含む) を先に取り込む
input=$(cat 2>/dev/null) || input=""

[ "${HERDR_ENV:-}" = "1" ] || exit 0
[ -n "${HERDR_PANE_ID:-}" ] || exit 0
command -v herdr >/dev/null 2>&1 || exit 0

# hook のプロセス cwd はセッション shell の cd に引きずられるため、
# pane の起動 cwd (herdr が保持) を基準にする
if command -v jq >/dev/null 2>&1; then
	pane_cwd=$(herdr pane get "$HERDR_PANE_ID" 2>/dev/null |
		jq -r '.result.pane.cwd // empty' 2>/dev/null) || pane_cwd=""
	[ -n "$pane_cwd" ] && cd "$pane_cwd" 2>/dev/null
fi

if top=$(git rev-parse --show-toplevel 2>/dev/null); then
	# worktree (git wt / herdr worktree) でも主リポジトリ名を出すため
	# git-common-dir (主リポジトリの .git) の親ディレクトリ名を repo 名にする
	common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) ||
		common="$top/.git"
	repo=$(basename "$(dirname "$common")")
	branch=$(git branch --show-current 2>/dev/null) || branch=""
	# detached HEAD は短縮 SHA で代替
	[ -n "$branch" ] || branch="@$(git rev-parse --short HEAD 2>/dev/null || echo '?')"
	title="$repo:$branch"
else
	title=$(basename "$PWD")
	repo=$title
fi

# session name: transcript の custom-title レコードの最後の1件が現在名。
# UserPromptSubmit はそのターンの自動改名前に発火するため 1 ターン遅れで追従する
session_name=""
if command -v jq >/dev/null 2>&1 && [ -n "$input" ]; then
	transcript=$(printf '%s' "$input" |
		jq -r '.transcript_path // empty' 2>/dev/null) || transcript=""
	if [ -n "$transcript" ] && [ -r "$transcript" ]; then
		session_name=$(grep '"type":"custom-title"' "$transcript" 2>/dev/null |
			tail -n 1 | jq -r '.customTitle // empty' 2>/dev/null) ||
			session_name=""
	fi
fi

# sidebar_width(36) から最長 state 接頭辞 "working · "(10文字) を引いた 26 文字に
# 丸める。herdr 側の hard-cut と違い、切れたことが分かるよう … を付ける
if [ -n "$session_name" ] && [ "${#session_name}" -gt 26 ]; then
	session_name="$(printf '%s' "$session_name" | cut -c1-25)…"
fi

# --agent claude: pane の検知 agent が claude の間だけ適用される表示ガード。
# 同一 source の再報告は全項目置き換えのため、name 無し分岐では custom_status が
# 自然に消える (--clear-custom-status 不要)
if [ -n "$session_name" ]; then
	herdr pane report-metadata "$HERDR_PANE_ID" \
		--source user:cc-title --agent claude \
		--title "$title" --display-agent "$session_name" \
		--custom-status "$title" || true
else
	herdr pane report-metadata "$HERDR_PANE_ID" \
		--source user:cc-title --agent claude \
		--title "$title" --display-agent "$title" || true
fi

# workspace label の自動追従 (custom_name 未設定時のみ働く) を止める:
# 未 pin の workspace は repo 名で pin する。手動 rename (custom_name あり) は
# 触らない。custom_name は API に出ないため session.json (socket と同じ
# ディレクトリ) から読む。
if [ -n "${HERDR_WORKSPACE_ID:-}" ] && command -v jq >/dev/null 2>&1; then
	sess="$(dirname "${HERDR_SOCKET_PATH:-$HOME/.config/herdr/herdr.sock}")/session.json"
	if [ -r "$sess" ]; then
		pinned=$(jq -r --arg w "$HERDR_WORKSPACE_ID" \
			'.workspaces[] | select(.id == $w) | .custom_name // ""' \
			"$sess" 2>/dev/null) || pinned=""
		[ -n "$pinned" ] ||
			herdr workspace rename "$HERDR_WORKSPACE_ID" "$repo" || true
	fi
fi
