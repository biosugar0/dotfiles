#!/bin/bash
# PreToolUse(Bash|Write): テストファイルの「削除・空化」をブロックする(best-effort)。
#
# 調査(Anthropic long-running harness 等)で確認された失敗モード: エージェントがテストを消す/骨抜きにして
# 「通った」状態を捏造する("It is unacceptable to remove or edit tests")。本 hook はその破壊的ケースを
# 止め、正常なテストの追加・更新・rename は通す(誤爆で hook ごと無効化されるのを避けるため対象を狭く保つ)。
#
# 対象(DENY):
#   - Bash:  rm / git rm(git global option 越しも含む) でテストファイル・ディレクトリ削除 / find ... -delete /
#            truncate / cp /dev/null / 単一リダイレクト `> <testfile>` による空化。引用符付き operand も判定。
#   - Write: 既存テストファイルを空(ほぼ0バイト)に上書き = 削除相当。
# 非対象(ALLOW): 新規テスト作成 / 通常の編集・更新 / mv(rename) / `>>`追記。
#
# 限界(正直に): best-effort。security boundary ではない。以下は **意図的に対象外**(検出が不安定/誤爆源のため):
#   - Edit/MultiEdit による空化(replace_all・部分置換と全体空化が PreToolUse では判別困難)
#   - 任意の言語/API による書き込み(python・sed -i 等)や cp/mv 以外の経路
#   役割は「うっかり/横着でテストを消す」典型操作の抑止。完全防御ではない。

input=$(cat)
command -v jq >/dev/null 2>&1 || exit 0
# 発火実績を JSONL 記録(cc-harness-metrics 集計用)。lib 欠損時は no-op。
. "$(dirname "$0")/lib/harness-log.sh" 2>/dev/null || harness_log() { :; }
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty')

# token を囲む1層の quote を除去(word-split 後の 'tests/x' / "tests/x" に対応)。
unquote() {
  local t="$1"
  case "$t" in
    \"*\") t="${t#\"}"; t="${t%\"}" ;;
    \'*\') t="${t#\'}"; t="${t%\'}" ;;
  esac
  printf '%s' "$t"
}

# テストファイル判定。誤爆回避のため拡張子は実テストコードのものに限定(*.spec.json 等のデータ/設定は除外)。
is_test_file() {
  case "$1" in
    */tests/*|tests/*|*/__tests__/*|__tests__/*) return 0 ;;
    *.test.js|*.test.jsx|*.test.ts|*.test.tsx|*.test.mjs|*.test.cjs) return 0 ;;
    *.spec.js|*.spec.jsx|*.spec.ts|*.spec.tsx|*.spec.mjs|*.spec.cjs) return 0 ;;
    *_test.go|*_test.py|*_spec.rb|*Test.java|*Tests.cs) return 0 ;;
    */test_*.py|test_*.py) return 0 ;;
    *) return 1 ;;
  esac
}

# テストディレクトリ判定(末尾スラッシュ有無問わず tests / __tests__ 自体、またはその配下指定)。
is_test_dir() {
  case "${1%/}" in
    tests|__tests__|*/tests|*/__tests__) return 0 ;;
    *) return 1 ;;
  esac
}

deny() { # $1=reason
  harness_log "guard-test-mutation" "deny" "$tool" "$(printf '%s' "$input" | jq -r '.session_id // empty')"
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

R_DELETE="テストファイル/ディレクトリの削除はブロックされた。テストは回帰の証拠であり、消すと「通った」状態を捏造できる。テストが本当に不要なら、その判断は人間が別途明示的に行うこと。"
R_GUT="既存テストファイルを空(ほぼ0バイト)に上書き/空化する操作はブロックされた。テストの骨抜きは検証の無効化に等しい。"

# operand が テストファイル/ディレクトリなら deny_delete。flag(-...)は skip、quote は除去。
scan_delete_operands() {
  for tok in "$@"; do
    case "$tok" in -*) continue ;; esac
    local t; t=$(unquote "$tok")
    { is_test_file "$t" || is_test_dir "$t"; } && { set +f; deny "$R_DELETE"; }
  done
}

case "$tool" in
  Bash)
    cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
    [ -n "$cmd" ] || exit 0
    # 複合コマンドを区切り(&&,||,;,|)で分割し、各セグメントを単独に判定する(他コマンドの引数を誤爆しない)。
    segs=$(printf '%s' "$cmd" | sed -E 's/(\|\||&&|;|\|)/\n/g')
    set -f  # token 走査中の glob 展開を抑止
    while IFS= read -r seg; do
      seg="${seg#"${seg%%[![:space:]]*}"}"   # 先頭空白除去
      [ -n "$seg" ] || continue
      set -- $seg
      verb="$1"

      # (1) 単一 `>`(追記 `>>` は除く)の対象がテストファイルなら空化として deny。
      prev_redir=0
      for tok in "$@"; do
        if [ "$prev_redir" = 1 ]; then
          prev_redir=0
          is_test_file "$(unquote "$tok")" && { set +f; deny "$R_GUT"; }
        fi
        case "$tok" in
          '>') prev_redir=1 ;;
          '>>'*) : ;;                                     # 追記は空化でない
          '>'?*) is_test_file "$(unquote "${tok#>}")" && { set +f; deny "$R_GUT"; } ;;
        esac
      done

      # (2) verb 別: 削除/空化系のみ、そのセグメントの operand を走査。
      case "$verb" in
        rm)
          shift; scan_delete_operands "$@" ;;
        git)
          # 'git [global-options] rm <operands>' : 最初の rm token 以降を operand として判定。
          found=0
          for tok in "$@"; do
            if [ "$found" = 1 ]; then
              case "$tok" in -*) continue ;; esac
              t=$(unquote "$tok")
              { is_test_file "$t" || is_test_dir "$t"; } && { set +f; deny "$R_DELETE"; }
            elif [ "$tok" = "rm" ]; then found=1; fi
          done ;;
        truncate)
          shift
          for tok in "$@"; do
            case "$tok" in -*) continue ;; esac
            is_test_file "$(unquote "$tok")" && { set +f; deny "$R_GUT"; }
          done ;;
        cp)
          case " $* " in
            *" /dev/null "*)
              for tok in "$@"; do is_test_file "$(unquote "$tok")" && { set +f; deny "$R_GUT"; }; done ;;
          esac ;;
        find)
          if printf '%s' "$seg" | grep -qE '(-delete|-exec[[:space:]]+rm)\b'; then
            for tok in "$@"; do
              case "$tok" in find|-*) continue ;; esac
              t=$(unquote "$tok")
              { is_test_file "$t" || is_test_dir "$t"; } && { set +f; deny "$R_DELETE"; }
            done
          fi ;;
      esac
    done <<EOF
$segs
EOF
    set +f
    ;;
  Write)
    fp=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
    [ -n "$fp" ] || exit 0
    is_test_file "$fp" || exit 0
    cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
    case "$fp" in /*) abs="$fp" ;; *) abs="${cwd:-.}/$fp" ;; esac
    [ -f "$abs" ] || exit 0                            # 新規作成は許可
    cur=$(wc -c < "$abs" 2>/dev/null | tr -d ' ' || echo 0)
    content=$(printf '%s' "$input" | jq -r '.tool_input.content // empty')
    newlen=${#content}
    # 既存が非自明(>200B)なテストを、ほぼ0(<50B)に上書き = 空化とみなす
    if [ "${cur:-0}" -gt 200 ] && [ "$newlen" -lt 50 ]; then
      deny "$R_GUT"
    fi
    ;;
esac
exit 0
