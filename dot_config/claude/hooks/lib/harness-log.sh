# hooks 共有ロガー: decision イベントを JSONL に追記する（source して使う）。
# harness-audit の実測データ源。transcript には hook の deny/block が記録されないため、
# hook 自身が発火実績を残す。best-effort — ログ失敗で hook 本体を絶対に失敗させない。
#
# 出力先: $HOME/.local/state/claude/harness-events.jsonl
#   意図的に XDG_STATE_HOME を見ない固定パス。stop-hook(Deno) の shebang は
#   env -S の制約で ${HOME} しか展開できず(${VAR:-default} 不可)、bash/TS/集計の
#   3者で出力先が割れると監査データが欠落するため、全実装をこの固定パスに揃える。
# 集計:   cc-harness-metrics
#
# 使い方: harness_log <hook名> <event> [detail] [session_id]
#   event の慣例: deny / warn / reroute / block:<種別> / allow:<種別>

harness_log() {
  local hook="$1" event="$2" detail="${3:-}" session="${4:-}"
  local dir="$HOME/.local/state/claude"
  {
    mkdir -p "$dir" &&
      jq -cn \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg hook "$hook" \
        --arg event "$event" \
        --arg detail "$detail" \
        --arg session "$session" \
        --arg cwd "$PWD" \
        '{ts:$ts,hook:$hook,event:$event,detail:$detail,session:$session,cwd:$cwd}' \
        >>"$dir/harness-events.jsonl"
  } 2>/dev/null || true
}
