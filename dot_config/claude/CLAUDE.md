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

## コーディング規律

規律の本体は `hooks/data/coding-rules.txt` にあり、userpromptsubmit-context hook が
**working tree にソースコード変更がある間だけ毎プロンプト注入**する
（PR 説明系のルールは `hooks/data/workflow-instructions.md` の「PRの作成」節）。
CLAUDE.md は user message としてセッション開始時に一度入るだけで長セッションでは
減衰するため、実装中・PR 作成時に効かせたいルールはここに置かない。

セッション開始時に効かせるものだけをここに残す:

- **repo 規約の能動確認**: 対象 repo に CLAUDE.md が無い場合ほど、周辺コードの規約
  （定数・型・命名・エラーハンドリング・ログ出力（console 直書きせず repo の logger）・
  commit 前チェックコマンド）を実装前に確認して合わせる。

## トラブルシューティング

CI/ビルド失敗時は、ワークアラウンド（空コミット、手動リラン等）を試す前に**必ず根本原因を特定**する。
ログを読み、エラーをトレースし、原因分析を提示してから修正に着手すること。

## セッション引き継ぎ

- `ai/log/sessions/` にhookが自動生成
- 手動保存: `/save-session`

## ループ運用（/goal 不使用）

自律ループは stop-hook の goal loop（`hooks/executable_stop-hook.ts`）に一本化する。
上流の `/goal` コマンド（CLI v2.1.139+。実体は session-scoped な prompt-based Stop hook +
小型モデル評価）は**使わない** — stop-hook と同じ Stop イベントで評価が二重になり、
自前の機械的ガード（ターン上限・spin/エラー stuck 検出・verify receipt による決定的停止）と
上流の継続注入が衝突しうるため。ループさせたい時は自然文の反復指示
（「テストが通るまで繰り返して」「stop after 5 tries」等）を書けば stop-hook が goal 化する。

## モデル運用（tool-call タグ破損対策）

既定 main は **Opus 4.6**（2026-07-06 時点）。Opus 4.8 は tool-call の XML タグを text チャネルに漏らして壊す
既知バグがある（先頭が `court` 等に化け `antml:` 名前空間が欠落し、未実行のまま text 漏洩）。
ローカル実測（2026-07 全 transcript 走査）: **実破損は Opus 4.8 のみ 89件（0.27%/turn）**、
Opus 4.7 は 56k turns で 0件・4.6 も 0件、Sonnet 5 は 1件のみ。**全ツールで起きる**
（Bash 55 / Edit 14 / Agent 6 / Write 6 / Read 5 / AskUserQuestion 3）— 極小の Read でも
漏れるためペイロード長は本質でなく、**コマンド単位の subagent 委譲では防げない**
（1 Bash→1 Agent の置換は Opus の tool-call 回数を減らさず、Agent 呼び出し自体も漏れる）。

**破損は連鎖する（self-poisoning）**: 壊れた XML が履歴に残るとモデルが手本として模倣し、
再発率が跳ね上がる（実測: 初回破損後は 16-19%/turn・median gap 4 turns まで悪化した
セッションあり）。upstream 多数 issue（anthropics/claude-code #64108, #64150, #65705,
#68354 等）でも同メカニズムが報告され、**2026-07 時点で公式 fix なし**。CLI 更新では直らない。
対処の核心は「汚染履歴で粘らない・毒は resume 前に抜く」: 累計3回目以降は exit →
`claude --resume` で再開する（SessionEnd hook が `cc-transcript-sanitize` で transcript の
破損 XML をマーカーに置換するため、文脈を保ったまま毒だけ抜ける。ライブセッションの
in-memory 履歴は hook から編集不能なので、この resume 経路が唯一の自動除去点）。
破損 XML の生タグを text で引用・議論することも自己汚染になる（言い換えで言及する）。

**行動ルールは Opus セッションのみ自動注入**: 破損時の再送作法・連鎖時の脱出などの
具体的な行動指示は `hooks/data/golden-rules-opus.txt` にあり、userpromptsubmit-context hook が
transcript から現行モデルを判定して **Opus 系のときだけ** Golden Rules に注入する
（モデルは自分が何かを確実には知らないため、常時注入の自己条件付きルールは機能しない）。
判定不能時（セッション先頭等）は既定 main=Opus に合わせて**注入側に倒す**ため、
non-Opus セッションの初回ターンにも入ることがある。Sonnet/Fable 等と判定済みの
セッションでは注入されず、従う必要もない。

背景メモ（モデル非依存の周辺機構）:
- **ターン内自動リトライ**: harness 組み込み（malformed 検知で retry 注入）。実測で破損の約4割を回収。
- **事後自動復旧**: `stop-hook` がターン終端の stranded 破損を検知。Bash は同一破損の初回に限り
  hook が漏洩コマンドを**代行実行**して結果を返す（再送時の再破損リスクをゼロにする。deny リスト相当を
  尊重・20s キャップ・timeout 時は部分実行の可能性を明示）。2回目以降・他ツール・deny 該当は
  前置きゼロで出し直すよう block 注入。セッション累計3回で連鎖モードと判定し「exit→resume」誘導に
  エスカレート、同一破損2連続で give-up。
- **自動デトックス**: SessionEnd hook が `cc-transcript-sanitize` を実行し、transcript 内の破損 XML を
  `[toolcall-leak redacted: <tool>]` に置換（構造・uuid 保持、`.pre-sanitize.bak` 残置、冪等）。
  resume 時にモデルへ渡る履歴から毒が消える。手動実行・`--dry-run` も可。
- **バックストップ**: userpromptsubmit-context hook が「漏洩したまま放置された直前ターン」を検知して
  警告注入（stop-hook 不発時の保険）。
- **定量化**: `~/.config/claude/bin/cc-toolcall-leak-scan`（real/mention/redacted 分類・漏洩ツール別・`--since`）。
  hook の発火実績は `cc-harness-metrics` で集計（`block:toolcall_leak[_chained]` / `giveup:toolcall_leak`）。
