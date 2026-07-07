#!/usr/bin/env bash
# herdr vim-aware pane ナビゲーション (旧 tmux + vim-tmux-navigator の後継)。
#
# herdr が ctrl+h/j/k/l を横取りし、この script が focus 中 pane を判定して振り分ける:
#   - nvim/vim pane      → 同じ chord を pane に send-keys で返す。nvim 側
#                          (lua/rc/mappings.lua の herdr_nav) が内部 split 移動と
#                          端での pane 越境を担う。insert 中は lexima の C-h=backspace
#                          や skkeleton の C-j 等がそのまま効く (forward されるだけ)。
#   - 非 vim (shell/claude) → herdr pane focus で pane 移動。ただし移動先 pane が
#                          無い (境界) 場合は元のキーを pane に返し、shell の
#                          C-l(clear)/C-j 等を殺さない。
#
# 引数: $1 = 方向 (left|right|up|down), $2 = 転送するキー (ctrl+h 等)
#
# tmux の NAVIGATOR テーブル + `if-shell "$is_vim"` の条件分岐を、herdr の
# keys.command(type=shell) + pane process-info で直チョード方式に置き換えたもの。
set -u

dir="${1:?direction required}"
key="${2:?key required}"
herdr="${HERDR_BIN:-herdr}"

# focus 中 pane を確定 (keybinding 実行時は HERDR_ACTIVE_PANE_ID が入る)。
pane="${HERDR_ACTIVE_PANE_ID:-}"
if [ -z "$pane" ]; then
  pane=$("$herdr" pane current --current 2>/dev/null \
    | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"]["pane"]["pane_id"])' 2>/dev/null)
fi
[ -n "$pane" ] || exit 0

# focus 中 pane の前面プロセスが vim/nvim か判定 (foreground_process_group_id の
# リーダープロセスの argv0 basename を見る)。
is_vim=$("$herdr" pane process-info --pane "$pane" 2>/dev/null | python3 -c '
import sys, json, os
try:
    d = json.load(sys.stdin)["result"]["process_info"]
except Exception:
    print("no"); sys.exit()
leader = d.get("foreground_process_group_id")
procs = d.get("foreground_processes", []) or []
name = ""
for p in procs:
    if p.get("pid") == leader:
        name = p.get("argv0") or p.get("name") or ""
        break
if not name and procs:
    name = procs[0].get("argv0") or procs[0].get("name") or ""
base = os.path.basename(name)
print("yes" if base in ("vim", "nvim", "view", "vimdiff", "nvimdiff") else "no")
' 2>/dev/null)

if [ "$is_vim" = "yes" ]; then
  # nvim に判断を委ねる (内部 split 移動 or 端で自前越境)。
  exec "$herdr" pane send-keys "$pane" "$key"
fi

# 非 vim pane: 方向に pane があれば移動。無ければ元キーを pane へ返す。
changed=$("$herdr" pane focus --direction "$dir" --pane "$pane" 2>/dev/null \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"]["focus"]["changed"])' 2>/dev/null)
if [ "$changed" != "True" ]; then
  exec "$herdr" pane send-keys "$pane" "$key"
fi
