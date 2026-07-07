#!/usr/bin/env bash
# worktree.created イベント hook。
# Herdr ネイティブの worktree 作成 (prefix+shift+g / herdr worktree create) は
# git-wt と違い wt.copy / wt.hook を適用しないので、ここで補完する。
# herdr-wt (git wt 経由) で作った worktree には既に適用済みだが、
# コピーは「存在しないファイルのみ」なので二重適用しても安全。
set -u

STATE_DIR="${HERDR_PLUGIN_STATE_DIR:-/tmp}"
LOG="$STATE_DIR/worktree-setup.log"
log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG" 2>/dev/null; }

herdr_bin="${HERDR_BIN_PATH:-herdr}"
ws="${HERDR_WORKSPACE_ID:-}"

# 1. worktree path の解決: イベント JSON を最優先、無ければ workspace から逆引き
wt_path=""
if [ -n "${HERDR_PLUGIN_EVENT_JSON:-}" ]; then
  wt_path=$(printf '%s' "$HERDR_PLUGIN_EVENT_JSON" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

def find(obj, keys):
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k in keys and isinstance(v, str) and v:
                return v
        for v in obj.values():
            r = find(v, keys)
            if r:
                return r
    elif isinstance(obj, list):
        for v in obj:
            r = find(v, keys)
            if r:
                return r
    return None

print(find(d, {"checkout_path", "path"}) or "")
' 2>/dev/null)
fi
if [ -z "$wt_path" ] && [ -n "$ws" ]; then
  wt_path=$("$herdr_bin" worktree list --workspace "$ws" --json 2>/dev/null \
    | WS="$ws" python3 -c '
import json, os, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
ws = os.environ["WS"]
for w in d.get("result", {}).get("worktrees", []):
    if w.get("open_workspace_id") == ws:
        print(w.get("path", ""))
        break
' 2>/dev/null)
fi
if [ -z "$wt_path" ] || [ ! -d "$wt_path" ]; then
  log "skip: worktree path unresolved (ws=$ws)"
  exit 0
fi

# 2. main checkout の解決 (git native なので Herdr の配置場所に依存しない)
git_common=$(git -C "$wt_path" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
repo_root=$(dirname "$git_common")
if [ ! -d "$repo_root" ] || [ "$repo_root" = "$wt_path" ]; then
  log "skip: repo root unresolved for $wt_path"
  exit 0
fi

log "start: $wt_path (repo=$repo_root)"

# 3. wt.copy: main checkout からコピー (既存は上書きしない)。
#    git-wt は wt.copy を gitignore syntax の pattern として扱う (.env* 等) ため、
#    literal パスではなく glob として展開する。ディレクトリ横断のフル gitignore
#    semantics までは追わない (必要なら herdr-wt = git wt 経由を使う)
# wt.nocopy は wt.copy より優先される除外パターン (git-wt 仕様)。
# これを無視すると repo が wt.nocopy = .env.production 等で除外した secret を
# コピーしてしまうため、候補ごとに glob 照合して除外する。
nocopy_pats=$(git -C "$repo_root" config --get-all wt.nocopy 2>/dev/null)
git -C "$repo_root" config --get-all wt.copy 2>/dev/null | while IFS= read -r pat; do
  [ -n "$pat" ] || continue
  (
    cd "$repo_root" || exit 0
    # 意図的に unquoted: glob 展開させる (.env* → .env.local .env.development ...)
    for src in $pat; do
      [ -e "$src" ] || continue
      skip=false
      for np in $nocopy_pats; do
        # shellcheck disable=SC2254  # 意図的に unquoted: glob として照合
        case "$src" in $np) skip=true; break ;; esac
      done
      if [ "$skip" = true ]; then
        log "nocopy: $src"
        continue
      fi
      dst="$wt_path/$src"
      [ -e "$dst" ] && continue
      mkdir -p "$(dirname "$dst")" && cp -Rp "$src" "$dst" && log "copied: $src"
    done
  )
done

# wt.copyignored の全 ignored コピーは非対応 (node_modules 等を巻き込むため)。
# フル semantics が必要な場合は herdr-wt (git wt 経由) を使う。
if [ "$(git -C "$repo_root" config --get wt.copyignored 2>/dev/null)" = "true" ]; then
  log "notice: wt.copyignored=true is not replicated; use herdr-wt for full git-wt semantics"
fi

# 4. wt.hook: worktree 内で実行 (依存インストール等)
git -C "$repo_root" config --get-all wt.hook 2>/dev/null | while IFS= read -r hook; do
  [ -n "$hook" ] || continue
  log "hook: $hook"
  (cd "$wt_path" && sh -c "$hook") >>"$LOG" 2>&1 || log "hook FAILED: $hook"
done

log "done: $wt_path"
