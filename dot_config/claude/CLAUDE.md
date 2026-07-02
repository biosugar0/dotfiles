## 計画・Specファイル

すべての計画・specは `~/.config/claude/plans/` に保存。
「planを読んで」「specを確認して」等の指示時は、まずこのディレクトリ内を確認すること。

## ツール使い分け

- **探索・参照検索**: Claude Code LSP（軽量、トークン効率良い）
- **Fetch**: fetch MCP または readability MCP

## 作業方針

- 抜け漏れがないかをチェックし、慎重に作業を進める
- タスクは細かく分割し、subagentで実行
- 論理的かつ批判的な姿勢で議論

## トラブルシューティング

CI/ビルド失敗時は、ワークアラウンド（空コミット、手動リラン等）を試す前に**必ず根本原因を特定**する。
ログを読み、エラーをトレースし、原因分析を提示してから修正に着手すること。

## セッション引き継ぎ

- `ai/log/sessions/` にhookが自動生成
- 手動保存: `/save-session`

## モデル運用（tool-call タグ破損対策）

既定 main は **Opus 4.8**。Opus 4.8/4.7 は長大な Bash（python heredoc・tmux guard・多段パイプ等）で
tool-call の XML タグを text チャネルに漏らして壊す既知バグがある（先頭が `court` に化け `antml:`
名前空間が欠落し、未実行のまま text 漏洩）。同一セッションで Sonnet 5 は未観測、Opus のみ多発
（Bash 4倍で Sonnet 0件・Opus 12漏洩3 malformed）。tool_use はループのモデル自身が吐くので
main=Opus では Opus が吐く＝破損箇所そのもの（reasoning/tool-call のモデル分離は不可）。

**行動ルールは Opus セッションのみ自動注入**: sonnet-bash-runner 委譲・verbatim 再送禁止などの
具体的な行動指示は `hooks/data/golden-rules-opus.txt` にあり、userpromptsubmit-context hook が
transcript から現行モデルを判定して **Opus 系のときだけ** Golden Rules に注入する
（モデルは自分が何かを確実には知らないため、常時注入の自己条件付きルールは機能しない）。
判定不能時（セッション先頭で transcript に assistant message がまだ無い等）は
既定 main=Opus に合わせて**注入側に倒す**ため、non-Opus セッションの初回ターンにも
入ることがある。Sonnet/Fable 等と判定済みのセッションでこの委譲指示は注入されず、
従う必要もない。

背景メモ（モデル非依存の周辺機構）:
- **事後自動復旧**: `stop-hook` がターン終端で破損を検知し、前置きゼロで先頭から出し直すよう自動リトライ注入。
- **最終手段**: 同一破損が2連続すると stop-hook が `/model sonnet` 切替を促す（無限再破損防止）。
- **定量化**: `~/.config/claude/bin/cc-toolcall-leak-scan` でセッション transcript を走査（モデル別破損率）。
  hook の発火実績は `cc-harness-metrics` で集計。
