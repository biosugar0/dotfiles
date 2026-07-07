#!/bin/bash
# PostToolUse / PostToolUseFailure(Bash): test/build/typecheck コマンドの出力を捕捉し、anti-loop の signature を
# 自動記録する (PR2 追補)。
#
# 狙い: モデルが `ai-run-check -- pytest` を使わず素の `pytest` を叩いても、同一失敗の反復を機械的に検出する。
#   ここで loop.json を populate しておけば、次の編集で PreToolUse(pre-tool-use-anti-loop) が warn(v1)/deny(v2) する。
#   = anti-loop が「モデルの ai-run-check 採用」に依存せず常時稼働する。
#
# ★ 実測した Claude Code の hook 仕様(重要):
#   - PostToolUse は **コマンド成功(exit 0)時のみ**発火し、入力は `tool_response.{stdout,stderr}`。
#   - 失敗(非ゼロ終了)時は **PostToolUseFailure** が発火し、入力は `.error`(="Exit code N\n<出力>") と `.is_interrupt`。
#   この hook は両方に登録され、どちらの schema でも出力を拾えるよう defensive に抽出する。失敗判定は
#   出力中の failure マーカー(ai-run-check の has_failure。`^Exit code [1-9]` も含む)で行う。

command -v jq >/dev/null 2>&1 || exit 0
command -v ai-run-check >/dev/null 2>&1 || exit 0   # 未 deploy(chezmoi apply 前)では何もしない

json_tmp=$(mktemp /tmp/anti-loop-rec-json.XXXXXX) || exit 0
out_tmp=""
cleanup() {
  rm -f "$json_tmp"
  [ -z "$out_tmp" ] || rm -f "$out_tmp"
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM

cat > "$json_tmp"

cmd=$(jq -r '.tool_input.command // empty' "$json_tmp")
[ -n "$cmd" ] || exit 0
cwd=$(jq -r '.cwd // empty' "$json_tmp")
[ -n "$cwd" ] || exit 0

# 中断(Ctrl-C 等)は失敗でないので記録しない(PostToolUseFailure の is_interrupt)
[ "$(jq -r '.is_interrupt // false' "$json_tmp")" = "true" ] && exit 0

# ai-run-check 経由のコマンドは二重計上になるので skip(ai-run-check 自身が既に記録済み)。
# コマンド位置(行頭 / ; / && / || / | / ( の後、任意の path prefix 可)の ai-run-check のみ検出。
# 引数中の test_ai-run-check.py 等は誤 skip しない。`cd x && ai-run-check ...` も確実に skip する。
printf '%s' "$cmd" | grep -qE '(^|[[:space:];&|(])([^[:space:]]*/)?ai-run-check([[:space:]]|$)' && exit 0

# 対象は test/build/typecheck/lint の既知ランナーのみ(allowlist。任意コマンドへの過剰計上を避ける)
printf '%s' "$cmd" | grep -qE \
  '(^|[[:space:];&|(])((py\.?test)|jest|vitest|mocha|ava|rspec|phpunit|tsc|ctest|nox|tox)([[:space:]]|$)|(^|[[:space:];&|(])(cargo|go|npm|yarn|pnpm|bun|deno|make|just|mix|gradle|\./gradlew|mvn|dotnet|rake)[[:space:]]+(run[[:space:]]+)?(vet|clippy|(test|build|check|lint|typecheck|ci)(:[^[:space:]]+)?)([[:space:]]|$)' \
  || exit 0

# PostToolUse(tool_response.stdout/stderr)と PostToolUseFailure(.error)の両 schema から出力を結合抽出
out_tmp=$(mktemp /tmp/anti-loop-rec.XXXXXX) || exit 0
jq -r '[(.tool_response.stdout // ""), (.tool_response.stderr // ""), (.error // "")] | join("\n")' "$json_tmp" > "$out_tmp" || exit 0
grep -q '[^[:space:]]' "$out_tmp" || exit 0

# ai-run-check は cwd の git root を基準に loop.json を書く。stderr の警告(上限到達)はそのまま通す。
( cd "$cwd" 2>/dev/null && ai-run-check --record --cmd "$cmd" --output-file "$out_tmp" )
exit 0
