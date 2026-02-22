# Git Worktree Strategy Router

現在の作業を中断せずに別ブランチで操作を行う。目的に応じて最適な手法を選択する。

## 方式選択

迷ったら: 使い捨て・subagent完結 → built-in、それ以外 → gtr

| ユースケース | 方式 |
|---|---|
| worktreeで修正→commit→PR | **built-in** `isolation: "worktree"` |
| 並列subagentでテスト/修正 | **built-in** `isolation: "worktree"` |
| 読み取り専用の一時確認 | **built-in** `isolation: "worktree"` |
| mainでテスト/ビルド | **gtr** `git gtr run 1` |
| 特定refをcheckout | **gtr** `git gtr new --from` |
| 既存の名前付きworktreeを再利用 | **gtr** `git gtr run <name>` |
| 長期保持するworktree（dev server等） | **gtr** `git gtr new` |

## 方式1: Built-in Worktree Isolation

Taskツールで `isolation: "worktree"` を指定。subagentが独立worktreeで動作する。

### 主要パターン: worktreeで修正してPR

Taskツール（`isolation: "worktree"`）でsubagentに依頼:
1. `git checkout -b <branch-name>`
2. コード修正（通常のRead/Edit/Write）
3. `git add` & `git commit`
4. `git push -u origin <branch-name>`
5. `gh pr create`

push/PR作成が失敗した場合: コミットまで完了し、ブランチ名を報告。

### 並列実行

複数Taskを並列起動（各 `isolation: "worktree"`）。
ブランチ名の衝突に注意（各subagentに一意な名前を指定）。

### クリーンアップ

自動管理。変更なし→即削除、変更あり→保持。手動介入不要。

## 方式2: git gtr

名前付きworktreeの作成・管理、メインリポジトリ操作に使用。

### コマンド

| コマンド | 用途 |
|----------|------|
| `git gtr list` | 一覧表示 |
| `git gtr new <name> [--from <ref>] [--yes]` | 作成 |
| `git gtr run <name> <cmd>` | コマンド実行 |
| `git gtr go <name>` | パス取得 |
| `git gtr rm <name> [--yes]` | 削除 |

- **`"1"`** = メインリポジトリ（worktreeではない）
- **禁止**: `git gtr ai`, `git gtr editor`（対話的操作）
- worktree作成後は**依存関係インストール必須**

### 依存関係インストール

| 種別 | コマンド |
|------|----------|
| Node.js | `git gtr run <name> npm ci` |
| Python (uv) | `git gtr run <name> uv sync` |
| Python (poetry) | `git gtr run <name> poetry install` |
| Go | `git gtr run <name> go mod download` |
| Rust | `git gtr run <name> cargo fetch` |

### mainでテスト/ビルド

```bash
git gtr run 1 npm test
git gtr run 1 npm run build
```

### 特定refのcheckout

```bash
git gtr new pr-123 --from origin/feature --yes
git gtr run pr-123 npm ci
git gtr run pr-123 npm test
git gtr rm pr-123 --yes
```

### ファイル操作

```bash
WORKTREE_PATH=$(git gtr go <name>)
git gtr run <name> cat src/file.ts
```

### クリーンアップ

手動 `git gtr rm <name> --yes`（ブランチも: `--delete-branch`）

## 事前定義agent（任意）

頻繁に使うパターンは `.claude/agents/` にagentファイルとして定義可能:

```yaml
---
name: worktree-fixer
description: worktreeで修正してPRを作成する
isolation: worktree
---
指定された修正を行い、commit、push、PR作成まで完了する。
```

Taskツールでインライン指定（`isolation: "worktree"`）でも同等の動作。

## 共通ルール

- **所有権**: built-in worktreeはClaude Codeが自動管理。gtr worktreeは作成者が`git gtr rm`で片付ける。混在させない。
- worktreeは `.git` を共有 → コミットは即座に全worktreeで参照可能
- `git gtr run` はworktreeディレクトリで実行される
- `.claude/worktrees/` を `.gitignore` に追加推奨（built-in worktreeの作成先）

## トラブルシューティング

| 問題 | 対処 |
|------|------|
| 未コミット変更で作成失敗 | `git status` で状況確認 → 必要に応じて `git stash` |
| gtr worktreeが残っている | `git gtr list` → `git gtr rm <name> --yes` |
| ブランチも削除したい | `git gtr rm <name> --delete-branch --yes` |
| 依存関係エラー | lockファイル差分確認、`npm ci --force` 等 |
| 名前衝突 | 既存worktree確認: `git gtr list` |
