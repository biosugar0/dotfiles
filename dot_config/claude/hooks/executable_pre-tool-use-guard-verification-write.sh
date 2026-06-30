#!/bin/bash
# PreToolUse(Edit|Write|MultiEdit|Bash): ai/state/verification.json への直接書き込みをブロックする。
#
# verification.json は stop-hook が短絡判断(test/lint/build の PASS で即停止)に信頼する検証 receipt。
# 書き込み主体を `ai-run-check --write-receipt` に集約し、LLM が「本当は失敗なのに PASS」と手書きする
# verifier-gaming を低減する。調査でも「検証は外部・決定的シグナルで、自己申告に任せない」が確認されている。
#
# 注: shell 経由(任意の書き込み API/言語)を完全には防げない。これは security boundary ではなく
#     gaming 低減策(best-effort)。正規ルート: ai-run-check --write-receipt -- <検証コマンド>

input=$(cat)
command -v jq >/dev/null 2>&1 || exit 0
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty')

deny() {
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "ai/state/verification.json への直接書き込みはブロックされた。検証 receipt は `ai-run-check --write-receipt -- <検証コマンド>` が実 exit code から機械生成する(verifier-gaming 防止)。手書きでの PASS 記録は不可。"
    }
  }'
  exit 0
}

case "$tool" in
  Edit|Write|MultiEdit)
    fp=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
    case "$fp" in
      */ai/state/verification.json|ai/state/verification.json) deny ;;
    esac
    ;;
  Bash)
    cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
    # 書き込み演算子(>, >>, >|, tee, tee -a)の **直後のリダイレクト先トークン** が ai/state/verification.json
    # (receipt 本体)の時のみ deny。docs/verification.json など別物は対象外。区切り(; && 空白)や pipe を跨いだ
    # 「別ファイルへ書いて verification.json を読むだけ」も誤検知しない。
    # 例: `make > build.log; cat ai/state/verification.json`(読み取り)は allow。`echo x >| ai/state/verification.json` は deny。
    if printf '%s' "$cmd" | grep -qE '(>>?\|?[[:space:]]*|tee[[:space:]]+(-a[[:space:]]+)?)([^[:space:]|;&<>]*/)?ai/state/verification\.json'; then
      deny
    fi
    ;;
esac
exit 0
