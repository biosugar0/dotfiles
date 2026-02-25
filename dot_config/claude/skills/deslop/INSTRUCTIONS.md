現在のブランチでベースブランチとのdiffをチェックし、AI生成のslopを削除する。

前提:
- 呼び出し元の会話コンテキストからcwd（作業ディレクトリ）を把握し、そのディレクトリで全コマンドを実行すること
- worktree内で実行される場合があるため、パスを仮定しない

対象:
- ファイル内の他のコメントと一貫性がない余計なコメント
- そのコード領域では異常な防御的チェックやtry/catch（信頼済みコードパスから呼ばれる場合）
- ファイル全体のスタイルと合わないコード

手順:
1. `git rev-parse --abbrev-ref HEAD` で現在のブランチ名を取得
2. ベースブランチを検出: `git merge-base --fork-point main HEAD 2>/dev/null || git merge-base origin/main HEAD 2>/dev/null || git merge-base master HEAD 2>/dev/null`。失敗する場合は `git log --oneline main..HEAD` で差分コミットを確認
3. `git diff <base>...HEAD` でこのブランチの変更を取得。差分がない場合はその旨報告して終了
4. 各変更ファイルの全体を読み、既存スタイルを把握
5. slopを特定して削除（機能的な変更は行わない）
6. 不明な場合は削除しない（保守的に判断）
7. 変更内容を1-3文で要約報告
