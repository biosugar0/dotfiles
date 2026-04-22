#!/usr/bin/env bash
# Claude Code Notification hook → WezTerm OSC 777 (notify) toast.
# stdin の hook payload JSON から notification_type / message / cwd を抽出。
# 引数で title / body を指定すれば stdin を無視して上書き。
# tmux 内なら DCS passthrough でラップ。
set -u

sanitize() {
  # 改行類をスペースに、他の制御文字 (ESC 含む) は削除
  printf '%s' "$1" | tr '\n\r\t' '   ' | tr -d '\000-\010\013-\037\177'
}

title="Claude Code"
body=""

if [ ! -t 0 ] && command -v jq >/dev/null 2>&1; then
  payload=$(cat)
  if [ -n "$payload" ]; then
    msg=$(printf '%s' "$payload" | jq -r '.message // empty' 2>/dev/null)
    ntype=$(printf '%s' "$payload" | jq -r '.notification_type // empty' 2>/dev/null)
    event=$(printf '%s' "$payload" | jq -r '.hook_event_name // empty' 2>/dev/null)
    cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)
    proj="${cwd##*/}"
    label="${ntype:-${event:-notification}}"

    # message が空なら event 名から補う (Stop/SubagentStop 等は message を含まない)
    if [ -z "$msg" ]; then
      case "$event" in
        Stop) msg="タスク完了" ;;
        SubagentStop) msg="サブエージェント完了" ;;
      esac
    fi

    if [ -n "$proj" ]; then
      title="[$label] $proj"
    else
      title="[$label] Claude Code"
    fi
    body="$msg"
  fi
fi

# CLI 引数 override (手動テスト・他 hook からの流用向け)
[ $# -ge 1 ] && title="$1"
[ $# -ge 2 ] && body="$2"

title=$(sanitize "$title")
body=$(sanitize "$body")

[ -w /dev/tty ] || exit 0

if [ -n "${TMUX:-}" ]; then
  printf '\033Ptmux;\033\033]777;notify;%s;%s\033\033\\\033\\' "$title" "$body" > /dev/tty
else
  printf '\033]777;notify;%s;%s\033\\' "$title" "$body" > /dev/tty
fi
