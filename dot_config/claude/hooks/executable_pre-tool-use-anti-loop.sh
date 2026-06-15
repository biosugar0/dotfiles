#!/bin/bash
# PreToolUse(Edit|Write|MultiEdit): 同一失敗ループを編集境界で検出する機械的 anti-loop gate (PR2)。
# データ源は ai/state/loop.json(ai-run-check が失敗出力を正規化・signature 化して記録する)。
# LLM の自己判断に頼らず、同じ失敗が max_attempts 回連続したら「パッチを当て直すループ」を止める。
#
# 段階導入(plan):
#   v1(既定): 警告のみ(stderr, 非ブロック)。主たる警告は ai-run-check のインライン出力が担う。
#   v2: 環境変数 AI_ANTILOOP_ENFORCE=1 で、上限到達時に Edit/Write を deny(reason はモデルに渡る)。
# 解除: ai-run-check --reset、または別アプローチで失敗内容が変われば signature が変わり自動リセット。

input=$(cat)
command -v jq >/dev/null 2>&1 || exit 0
cwd=$(echo "$input" | jq -r '.cwd // empty')
[ -n "$cwd" ] || exit 0
# loop.json は git root 基準(ai-run-check と揃える)。サブディレクトリ起動でも正しく読む。
repo=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || echo "$cwd")
loop="$repo/ai/state/loop.json"
[ -f "$loop" ] || exit 0

cnt=$(jq -r '.consecutive_same_failure // 0' "$loop")
max=$(jq -r '.max_attempts // 3' "$loop")
ack=$(jq -r '.strategy_reset_ack // false' "$loop")
sig=$(jq -r '.last_failure_signature // ""' "$loop")

# 数値以外は無視(壊れた loop.json で誤動作しない)
case "$cnt" in ''|*[!0-9]*) exit 0 ;; esac
case "$max" in ''|*[!0-9]*) max=3 ;; esac
[ "$ack" = "true" ] && exit 0
[ "$cnt" -ge "$max" ] || exit 0

reason="同一失敗が ${cnt} 回連続(sig=${sig})。パッチを当て直すループの可能性。広い編集を続ける前に、決定的な repro/test/harness を作るか、仮説を ranked で立て直す(weakest_assumption の falsifiable check)。解除: ai-run-check --reset。"

if [ "${AI_ANTILOOP_ENFORCE:-0}" = "1" ]; then
  jq -n --arg r "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
else
  echo "⚠ anti-loop(warn): $reason" >&2
fi
exit 0
