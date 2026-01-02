---
name: git-worktree
description: Git worktreeを使った並列開発を支援。別ブランチでテスト実行、PRレビュー用にコード取得、複数ブランチ間でコマンド実行が必要な場合に使用。git gtr run でworktree内コマンドを実行。
---

# Git Worktree Manager (for Claude Code)

git worktree と git gtr を使い、現在の作業を中断せずに別ブランチで操作を行う。

## 重要: Claude Code での使い方

**使うべきコマンド:**
- `git gtr list` - worktree 一覧
- `git gtr new` - worktree 作成
- `git gtr run <branch> <command>` - worktree 内でコマンド実行
- `git gtr go <branch>` - パス取得
- `git gtr rm` - worktree 削除

**使ってはいけないコマンド:**
- `git gtr ai` - 対話的 AI セッションを起動するため不適切
- `git gtr editor` - エディタを起動するため不適切

## 典型的なユースケース

### 1. 現在の作業を中断せずに main でテスト

```bash
# "1" は メインリポジトリを指す
git gtr run 1 npm test
git gtr run 1 npm run build
```

### 2. PR/別ブランチのコードを確認

```bash
# worktree 作成
git gtr new pr-review --from origin/feature-branch

# コード確認
git gtr run pr-review cat src/main.ts
git gtr run pr-review git diff main...HEAD --stat

# 確認後に削除
git gtr rm pr-review --yes
```

### 3. 複数ブランチで並列テスト

```bash
# 各ブランチ用の worktree
git gtr new feature-a --from origin/feature-a
git gtr new feature-b --from origin/feature-b

# 並列でテスト実行
git gtr run feature-a npm test &
git gtr run feature-b npm test &
wait

# 結果を比較
```

### 4. 別ブランチでビルド確認

```bash
git gtr new build-check --from main
git gtr run build-check npm ci
git gtr run build-check npm run build
git gtr rm build-check --yes
```

## コマンドリファレンス

### 一覧表示
```bash
git gtr list              # 人間向け
git gtr list --porcelain  # スクリプト向け (TAB区切り: path, name, branch)
```

### 作成
```bash
git gtr new <branch>                    # 新ブランチで作成
git gtr new <branch> --from <ref>       # 特定 ref から作成
git gtr new <branch> --from-current     # 現在のブランチから派生
git gtr new <branch> --yes --no-copy    # 非対話・ファイルコピーなし
```

### コマンド実行 (最重要)
```bash
git gtr run <branch> <command...>

# 例
git gtr run main git status
git gtr run feature npm test
git gtr run 1 cat package.json        # "1" = メインリポジトリ
```

### パス取得
```bash
git gtr go <branch>                   # パスを出力
# 例: /Users/user/project-worktrees/feature
```

### 削除
```bash
git gtr rm <branch>                   # 削除
git gtr rm <branch> --yes             # 確認なし
git gtr rm <branch> --delete-branch   # ブランチも削除
```

## ファイル読み書き

worktree 内のファイルを直接操作する場合:

```bash
# パスを取得して Read/Edit ツールで操作
WORKTREE_PATH=$(git gtr go feature)
# → Read/Edit ツールで $WORKTREE_PATH/src/file.ts を操作
```

または:

```bash
# git gtr run 経由で cat/操作
git gtr run feature cat src/file.ts
git gtr run feature git diff
```

## 注意事項

- worktree は `.git` を共有するため、コミットは即座に反映される
- `git gtr run` は worktree ディレクトリで `cd` してからコマンドを実行する
- worktree 作成時に依存関係は自動インストールされない (hooks で設定可能)
- 作業完了後は `git gtr rm` でクリーンアップ推奨
