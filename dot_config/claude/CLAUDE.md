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

Opus 4.8/4.7 は長大な Bash（python heredoc・tmux guard・多段パイプ等）で tool-call の XML タグを
text チャネルに漏らして壊す既知バグがある（先頭が `court` に化け `antml:` 名前空間が欠落 →
`Your tool call was malformed and could not be parsed. Please retry.`）。同一セッションで Sonnet 5 は
未観測、Opus のみ多発（Bash 4倍叩いた Sonnet で0件、Opus で12件漏洩・3件 malformed）。

- shell 反復の調査ループ・長時間タスクは既定の **Sonnet 5 を維持**し、Opus に切替えない。
- Opus を使う場合は重いコマンドを必ずスクリプト化し、tool 呼び出し直前の前置きテキストを短くする。
- 破損の定量化は `~/.config/claude/bin/cc-toolcall-leak-scan` でセッション transcript を走査（モデル別破損率）。
