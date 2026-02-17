# CI品質チェック

プロジェクトのCI設定を解析し、品質チェックコマンドをローカルで実行する。

## 手順

1. CI設定ファイルを特定（`.github/workflows/`, `Makefile`, `package.json` scripts等）
2. 品質チェックコマンドを抽出（lint, format, type check, test, build）
3. 各コマンドを実行し、結果を収集
4. 失敗した項目を修正
5. 修正後に再実行して確認
6. 結果を要約報告
