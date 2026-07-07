# stop-hook 誤判定の反例集

stop-hook の Haiku judge が誤った block/allow を出した実例を記録し、
judge の system prompt に反例として注入するためのファイル。

## 仕組み

- stop-hook.ts の `loadCounterexamples()` がこのファイルを読み、
  **行頭が `- [YYYY-MM-DD]` の行だけ**を entry として judge の system prompt
  末尾に注入する（このヘッダや見出し・空行は注入されない）。
- プロンプト肥大防止のため**最新 30 件**（ファイル末尾側）のみ注入される。
  30 件を超えたら古い entry や重複 entry を整理すること。
- ファイル不在・読み込み失敗時は注入なしで通常動作（fail-open）。

## 運用ループ

1. **発見**: 誤 block を体感したらその場で、または月次の harness-audit で
   `block:stop_gate` の reason 一覧（`~/.local/state/claude/harness-events.jsonl`）
   から誤判定疑いを抽出する。
2. **確認**: 該当セッションの transcript で文脈を確認し、誤判定と確定する。
3. **追記**: 下の Entries に 1 行で追記する（Claude に「今の block は誤判定。
   反例に追記して」と指示すれば追記される）。
   反例を追記する際は、同じ状況を `data/judge-eval/*.json` の fixture にすることも推奨。
   offline 回帰 eval は `cd dot_config/claude/hooks && deno run --allow-read --allow-net --allow-env judge-eval.ts` で実行する。
4. **反映**: chezmoi 管理のため、repo 側で編集したら `chezmoi apply` で
   `~/.config/claude/hooks/data/` に反映する。

## Entry フォーマット

1 entry = 1 行。judge (Haiku) が英語プロンプト内で読むため、状況要約は簡潔に:

    - [YYYY-MM-DD] <誤判定時の状況の要約> → correct: should_stop=true|false (<根拠>)

例（行頭 `- ` でないのでこの行は注入されない）:

    - [2026-07-05] Assistant answered a one-shot question and offered optional follow-ups → correct: should_stop=true (offering follow-ups is not an incomplete task)

## Entries
