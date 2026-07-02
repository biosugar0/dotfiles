---
name: herdr-pm
description: "Herdr 上で並列 worker (Claude/codex) を PM として監督する。worker の起動 (herdr-wt)、状態監視 (agent list / wait agent-status)、成果回収 (pane read)、追加指示 (send)。Use when: 並列開発の指揮、複数 worktree での同時作業監督、PM セッション運用。HERDR_ENV=1 の Herdr pane 内でのみ使用。"
---

# herdr-pm: 並列 worker の監督ループ

前提: `HERDR_ENV=1` かつ `herdr status server --json` が `"running":true`。
満たさない場合はこの skill を使わず orchestrator skill（subagent 方式）に切り替える。

## 原則

- PM は実装しない。**割当・監視・評価・統合**に徹する（orchestrator skill の Sprint Contract と同じ思想）
- worker のログ全文を読まない。読むのは **状態が変わった瞬間の末尾だけ**（PM の context window 保護）
- worker の「完了しました」は検証ではない。**PM が自分で実行したコマンド出力**（テスト・diff 確認）だけを完了根拠にする
- worker が working の間は割り込まない。`wait agent-status` で idle/blocked/done を待ってから送る

## 1. worker 起動

```bash
# worktree 作成 (wt.copy/wt.hook 適用) → workspace 化 → claude 起動まで一発
herdr-wt feat/task-a --claude   # 出力末尾が worktree パス

# 起動した worker の pane を特定
herdr agent list   # JSON。cwd が worktree パスの claude を探す
# サイドバー agents 欄には herdr-pane-title.sh hook が Claude session name
# (無ければ repo:branch) を display_agent、repo:branch を custom_status として
# 自動報告する。rename は役割名 (reviewer 等) を上書きしたい時だけでよい
herdr agent rename <pane_id> "worker-task-a"
```

## 2. タスク割当

claude の入力欄が出るのを待ってから送る:

```bash
herdr wait agent-status <pane_id> --status idle --timeout 60000
# 単一行: pane run はテキスト+Enter を1リクエストで送る
herdr pane run <pane_id> "<タスク指示。完了条件と検証コマンドを必ず含める>"
# 複数行プロンプトの場合:
herdr pane send-text <pane_id> "$(cat /tmp/pm-task-a.txt)"
herdr pane send-keys <pane_id> Enter
```

指示には必ず「完了時に何を出力するか」（例: 変更ファイル一覧とテスト結果）を含めること。

## 3. 監視ループ（複数 worker の round-robin）

```bash
# blocked (承認/質問待ち) か done (完了・未読) を短いタイムアウトで順に見る
for p in <pane_id_1> <pane_id_2>; do
  if herdr wait agent-status "$p" --status blocked --timeout 2000 >/dev/null 2>&1; then
    herdr pane read "$p" --source recent-unwrapped --lines 30   # 何を聞かれているか
    # 回答して continue（permission prompt なら人間にエスカレーション）
  fi
  if herdr wait agent-status "$p" --status done --timeout 2000 >/dev/null 2>&1; then
    herdr pane read "$p" --source recent-unwrapped --lines 60   # 成果末尾を回収
  fi
done
```

長時間何も起きない時は漫然と待たず、`herdr agent list` で全体を俯瞰して
異常（unknown 固着・想定外 idle）がないか確認する。

## 4. 検証と統合

- worker の worktree に対して PM が**自分で** `git -C <worktree> diff --stat`・テストを実行して確認
- 統合の可否判断・マージ順序は PM が決め、マージ自体は人間に依頼する（Golden Rule）

## 5. 掃除

```bash
herdr workspace close <workspace_id>   # pane ごと閉じる
git wt -d <branch>                     # マージ済み worktree の削除
```

## 禁止事項

- working 中の worker への send（入力が混線する）
- Escape キーの送信（worker の実行中タスクを殺す）
- worker の transcript/ログ全文の read（context 汚染。末尾 30-60 行まで）
