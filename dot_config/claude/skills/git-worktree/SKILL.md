---
name: git-worktree
description: |
  Git worktreeを使った並列開発を支援。git gtr コマンドで worktree 操作を行う。

  【必須発動キーワード】以下を含む発言時は必ずこのスキルを呼び出すこと:
  - 「worktree」「ワークツリー」
  - 「別ブランチで作業」「別リポジトリで」
  - 「mainでテスト」「mainで確認」「mainでビルド」
  - 「PR #XXX を見て」「PRのコードを確認」
  - 「並列でテスト」「複数ブランチで」
  - 「git gtr」

  重要: git worktree コマンドではなく git gtr コマンドを使用すること。
---

# Git Worktree Manager

現在の作業を中断せずに別ブランチで操作を行う。

## 基本ルール

- **`"1"`** = メインリポジトリ（元のgitリポジトリ、worktreeではない）
- worktree作成後は**依存関係インストール必須**
- 完了後は `git gtr rm` でクリーンアップ

## コマンド一覧

| コマンド | 用途 |
|----------|------|
| `git gtr list` | 一覧表示 |
| `git gtr new <name> [--from <ref>] [--yes]` | 作成 |
| `git gtr run <name> <cmd>` | コマンド実行 |
| `git gtr go <name>` | パス取得 |
| `git gtr rm <name> [--yes]` | 削除 |

**禁止**: `git gtr ai`, `git gtr editor` (対話的操作のため)

## プロジェクト初期化

| 種別 | コマンド |
|------|----------|
| Node.js | `git gtr run <name> npm ci` |
| Python (uv) | `git gtr run <name> uv sync` |
| Python (poetry) | `git gtr run <name> poetry install` |
| Go | `git gtr run <name> go mod download` |
| Rust | `git gtr run <name> cargo fetch` |

## ユースケース

### mainでテスト/ビルド
```bash
git gtr run 1 npm test
git gtr run 1 npm run build
```

### PR確認
```bash
git gtr new pr-123 --from origin/feature --yes
git gtr run pr-123 npm ci
git gtr run pr-123 npm test
git gtr rm pr-123 --yes
```

### 並列テスト (subagent活用)
```bash
# worktree作成
git gtr new feat-a --from origin/feat-a --yes
git gtr new feat-b --from origin/feat-b --yes
```
Taskツールで並列subagent起動 → 各worktreeでテスト → 結果集約 → `git gtr rm`

## ファイル操作

```bash
# パス取得してRead/Editツールで操作
WORKTREE_PATH=$(git gtr go feature)
# または
git gtr run feature cat src/file.ts
```

## トラブルシューティング

| 問題 | 対処 |
|------|------|
| 未コミット変更で作成失敗 | `git stash` してから作成、または `--from-current` |
| worktreeが残っている | `git gtr list` で確認、`git gtr rm <name> --yes` |
| ブランチも削除したい | `git gtr rm <name> --delete-branch --yes` |
| 依存関係エラー | lockファイル差分確認、`npm ci --force` 等 |

## 注意

- worktreeは `.git` を共有 → コミットは即座に全worktreeで参照可能
- `git gtr run` はworktreeディレクトリで実行される
