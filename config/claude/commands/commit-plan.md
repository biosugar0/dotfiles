---
description: AI専用：Git変更を分析し、論理的なコミット計画を作成（人間の判断が必要な箇所を明示）
---

# コミット計画作成（AI専用版）: $ARGUMENTS

## 重要：AIの制約事項

**AIができること**：
- ファイルの読み書き、静的な操作
- diffパッチの作成・編集・適用
- git status, git diffなどの情報取得コマンド
- 計画の作成と提案

**AIができないこと**：
- 対話的操作（git add --patch, expect）
- リアルタイムの判断・応答
- エディタの起動・操作

**人間に委ねること**：
- 複雑な行選択の最終判断
- 対話的操作が必要な場合の実行
- コミット計画の最終承認

## 引数（ARGUMENTS）

自然言語で指示を与えることができます：

```bash
# 例
"機能追加だけまとめて"
"テストとコードを分けて"
"自動で実行"
```

## 実行手順（AI用）

### 1. 変更内容の分析

```bash
# 現在の状態を確認
git status --porcelain
git diff --stat

# 変更内容を詳細に確認
git diff > all_changes.diff
```

### 2. コミット計画の作成と提示

変更を分析し、以下の形式で計画を作成：

```
【コミット計画】

[1] feat: ユーザー認証機能を追加
- src/auth.ts (新規)
- src/api.ts [部分] L45-L89
- src/types.ts [部分] L12-L25

[2] fix: バリデーションエラーを修正
- src/validation.ts [部分] L120-L145
- tests/validation.test.ts (全体)

【人間への確認事項】
1. 上記の行番号範囲は適切ですか？
2. コミットの分割方法に問題はありませんか？
3. 実行を続けてよろしいですか？ [Y/n]
```

### 3. 人間の承認待ち

ここで一旦停止し、人間の判断を待ちます。

### 4. 部分的ステージングの実行（diffパッチ方式）

人間の承認後、各コミットを実行：

#### 4.1 新規ファイルの処理
```bash
git add src/auth.ts
```

#### 4.2 部分的変更の処理（例：src/api.ts）

```bash
# 1. 変更内容を保存
git diff src/api.ts > src/api.ts.full.patch

# 2. ファイルをバックアップ
cp src/api.ts src/api.ts.backup

# 3. ファイルを元の状態に戻す
git checkout HEAD -- src/api.ts

# 4. パッチファイルを作成
cp src/api.ts.full.patch src/api.ts.partial.patch
```

**【人間への依頼】**
```
src/api.ts.partial.patch を編集して、L45-L89の変更のみを残してください。
編集が完了したら、実行を続けます。

編集のガイド：
1. 不要な変更部分を削除
2. @@で始まるハンクヘッダーの行数を調整
3. コンテキスト行（スペースで始まる行）は維持

編集完了後、「続行」と入力してください。
```

#### 4.3 編集されたパッチの適用

```bash
# パッチの検証
git apply --check src/api.ts.partial.patch
if [ $? -ne 0 ]; then
    echo "エラー: パッチの適用に失敗しました"
    echo "【人間への依頼】パッチファイルを修正してください"
    exit 1
fi

# パッチを適用
git apply src/api.ts.partial.patch
git add src/api.ts

# 元の変更を復元
cp src/api.ts.backup src/api.ts
```

#### 4.4 コミットの実行

```bash
# コミットメッセージを作成
cat > commit_message.txt << 'EOF'
feat: ユーザー認証機能を追加

- JWTベースの認証システムを実装
- ログイン/ログアウトAPIエンドポイントを追加
- 認証用の型とインターフェースを定義
- トークンの検証と更新処理を実装
EOF

git commit -F commit_message.txt
```

### 5. 次のコミットへ

同様の手順で残りのコミットを処理。

### 6. エラー時の対処

エラーが発生した場合：

```bash
# 現在の状態を保存
git status > error_state.txt
git diff --cached > staged_changes.diff

echo "【エラーが発生しました】"
echo "現在の状態："
cat error_state.txt
echo ""
echo "【人間への引き継ぎ】"
echo "1. error_state.txt に現在の状態が保存されています"
echo "2. staged_changes.diff にステージング済みの変更があります"
echo "3. 以下のコマンドで状態をリセットできます："
echo "   git reset HEAD"
echo "   git checkout -- ."
```

## 実行例（AI視点）

```bash
# 1. 変更を分析
$ git diff --stat
 src/api.ts   | 120 ++++++++++++++++++++++++++++
 src/auth.ts  |  85 ++++++++++++++++++++
 src/types.ts |  45 +++++++++++

# 2. 計画を作成して提示
echo "【コミット計画を作成しました】"
echo "[1] feat: 認証機能の実装"
echo "  - src/auth.ts (新規)"
echo "  - src/api.ts L45-L89"
echo "  - src/types.ts L12-L25"
echo ""
echo "この計画で進めてよろしいですか？ [Y/n]"

# 3. 人間の承認を待つ
read confirmation

# 4. 承認後、diffパッチ方式で実行
# （上記の手順に従って実行）
```

## ベストプラクティス（AI実行時）

1. **常にバックアップを作成**
   - ファイル操作前に必ず `.backup` を作成
   - エラー時の復旧を容易にする

2. **人間への確認ポイントを明確に**
   - 複雑な判断が必要な箇所で停止
   - 具体的な指示を提示

3. **エラー処理を丁寧に**
   - 各ステップで成功/失敗を確認
   - 失敗時は人間が介入しやすい状態で停止

4. **状態の可視化**
   - 各ステップの前後で `git status` を実行
   - 進捗を明確に報告

## 完了報告

すべてのコミットが完了したら：

```bash
echo "【コミット作業が完了しました】"
git log --oneline -n 5
echo ""
echo "【作成されたコミット】"
echo "- $(git log -1 --format='%h %s')"
echo ""
echo "【次のアクション】"
echo "1. git push でリモートに反映"
echo "2. 追加の変更を続ける"
echo "3. PRを作成する"
```

## 注意事項

- AIは対話的操作ができないため、必ずdiffパッチアプローチを使用
- 複雑なケースでは人間の判断を仰ぐ
- エラー時は安全に停止し、人間に引き継ぐ