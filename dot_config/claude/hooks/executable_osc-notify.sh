#!/usr/bin/env bash
# Claude Code Notification hook → WezTerm OSC 777 (notify) toast.
# stdin の hook payload JSON から notification_type / message / cwd を抽出。
# 引数で title / body を指定すれば stdin を無視して上書き。
#
# 出力経路:
#   - hook context (stdin=pipe + jq あり): JSON `{terminalSequence}` を返し
#     Claude Code 2.1.141+ に代理出力させる (TTY なし環境でも届く + tmux DCS は本体側で wrap)。
#   - 手動実行 / jq 不在: 従来通り /dev/tty へ直書き。tmux 内は DCS passthrough。
set -u

sanitize() {
  # 1. 改行類をスペースに
  # 2. C0 + DEL を削除 (ESC を含む / OSC 早期終端の防止)
  # 3. C1 制御文字 (U+0080-U+009F) を UTF-8 バイト列で削除 (U+009C=ST 等)
  # 4. OSC 777 の区切り文字 ";" を "," に置換 (title/body の分割事故防止)
  printf '%s' "$1" \
    | tr '\n\r\t' '   ' \
    | tr -d '\000-\010\013-\037\177' \
    | LC_ALL=C sed $'s/\xc2[\x80-\x9f]//g' \
    | tr ';' ','
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

# Herdr 内では OSC 777 passthrough に依存せず socket API で通知する
# ([ui.toast] delivery の設定に従って配送される。sound は settings.json の
#  afplay hook と二重になるため none)。server 不達時は従来経路へフォールスルー。
if [ "${HERDR_ENV:-}" = "1" ] && command -v herdr >/dev/null 2>&1; then
  # toast 無効時は {"shown":false} が exit 0 で返るため、実際に表示された時のみ完了扱い
  herdr_out=$(herdr notification show "$title" --body "$body" --sound none 2>/dev/null || true)
  if printf '%s' "$herdr_out" | grep -q '"shown":true'; then
    exit 0
  fi
fi

# Hook channel (2.1.141+): JSON で返すと Claude Code が OSC を代理出力する。
# 受理されるのは生 OSC のみ (DCS で wrap すると allowlist で弾かれる)。
# tmux 内かどうかは Claude Code 側で検出して DCS passthrough まで行ってくれる。
if [ ! -t 0 ] && command -v jq >/dev/null 2>&1; then
  osc=$(printf '\033]777;notify;%s;%s\033\\' "$title" "$body")
  jq -n --arg seq "$osc" '{terminalSequence: $seq}'
  exit 0
fi

# Fallback: 手動実行 / jq 不在 → /dev/tty 直書き。
[ -w /dev/tty ] || exit 0

if [ -n "${TMUX:-}" ]; then
  printf '\033Ptmux;\033\033]777;notify;%s;%s\033\033\\\033\\' "$title" "$body" > /dev/tty
else
  printf '\033]777;notify;%s;%s\033\\' "$title" "$body" > /dev/tty
fi
