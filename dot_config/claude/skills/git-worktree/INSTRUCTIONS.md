# Git Worktree Manager (git-wt)

現在の作業を中断せずに別ブランチで操作を行う。
ghq 管理下のリポジトリでも `.wt/` 内に worktree を配置するため干渉しない。

## 基本ルール

- **`git wt`** コマンドを使用（`git worktree` 直接操作は禁止）
- worktree は `.wt/` 内に自動配置（`.gitignore` 自動生成済み）
- worktree 作成後は**依存関係インストール必須**（`wt.hook` 未設定の場合）
- 完了後は `git wt -d` でクリーンアップ

## コマンド一覧

| コマンド | 用途 |
|----------|------|
| `git wt` | 一覧表示 |
| `git wt --json` | JSON で一覧 |
| `git wt <branch>` | 作成 or 切り替え |
| `git wt <branch> <start-point>` | start-point から作成 |
| `git wt -d <branch>` | 安全削除（マージ済みのみ） |
| `git wt -D <branch>` | 強制削除 |

**禁止**: shell 統合の自動 cd は Claude Code では動作しない。パス取得で対応する。

## パス取得とコマンド実行

git-wt には `run` コマンドがないため、パスを取得して実行する:

```bash
# パス取得（--nocd で cd せず最終行にパスを出力）
WT_PATH=$(git wt --nocd <branch> 2>/dev/null | tail -1)

# コマンド実行
bash -c "cd '$WT_PATH' && <command>"
```

**Read/Edit ツールでのファイル操作:**
```bash
WT_PATH=$(git wt --nocd <branch> 2>/dev/null | tail -1)
# → Read/Edit ツールで $WT_PATH/src/file.ts を操作
```

## プロジェクト初期化

worktree 作成後、依存関係をインストールする:

```bash
WT_PATH=$(git wt --nocd <branch> 2>/dev/null | tail -1)
```

| 種別 | コマンド |
|------|----------|
| Node.js | `bash -c "cd '$WT_PATH' && npm ci"` |
| Python (uv) | `bash -c "cd '$WT_PATH' && uv sync"` |
| Python (poetry) | `bash -c "cd '$WT_PATH' && poetry install"` |
| Go | `bash -c "cd '$WT_PATH' && go mod download"` |
| Rust | `bash -c "cd '$WT_PATH' && cargo fetch"` |

**推奨**: `wt.hook` でプロジェクトごとに自動化する:
```bash
git config --local --add wt.hook "npm ci"
```

## ファイルコピー設定

worktree 作成時に .gitignore 対象ファイル等を自動コピーできる:

```bash
# .env などの gitignore 対象ファイルをコピー
git config --local wt.copyignored true

# 特定ファイルを常にコピー
git config --local --add wt.copy ".env.local"
git config --local --add wt.copy ".claude/settings.local.json"

# コピー除外
git config --local --add wt.nocopy "*.log"
```

## ユースケース

### 別ブランチでテスト/ビルド
```bash
git wt --nocd main
WT_PATH=$(git wt --nocd main 2>/dev/null | tail -1)
bash -c "cd '$WT_PATH' && npm test"
```

### PR 確認
```bash
# リモートブランチから worktree 作成
git fetch origin pull/123/head:pr-123
git wt --nocd pr-123
WT_PATH=$(git wt --nocd pr-123 2>/dev/null | tail -1)
bash -c "cd '$WT_PATH' && npm ci && npm test"

# 確認後クリーンアップ
git wt -D pr-123
```

### 並列テスト (subagent 活用)
```bash
# worktree 作成
git wt --nocd feat-a origin/feat-a
git wt --nocd feat-b origin/feat-b
```
Task ツールで並列 subagent 起動 → 各 worktree でテスト → 結果集約 → `git wt -d`

### 並列開発
```bash
# 新ブランチで worktree 作成
git wt --nocd feature/new-api
WT_PATH=$(git wt --nocd feature/new-api 2>/dev/null | tail -1)
# → Agent ツールで $WT_PATH を作業ディレクトリとして使用
```

## トラブルシューティング

| 問題 | 対処 |
|------|------|
| worktree が残っている | `git wt` で確認、`git wt -D <branch>` |
| basedir の旧デフォルト警告 | `git config wt.basedir .wt` で明示設定 |
| linter が .wt/ を読む | `.wt/.gitignore` が `*` になっているか確認 |
| ファイルコピーされない | `wt.copy`, `wt.copyignored` の設定確認 |
| hook 失敗で作成中断 | hook コマンドの動作を単独で確認 |
| main/master 削除拒否 | デフォルトブランチ保護。`--allow-delete-default` で解除可 |

## 注意

- worktree は `.git` を共有 → コミットは即座に全 worktree で参照可能
- `.wt/` 内は自動で `.gitignore` される → ghq list に混入しない
- macOS では APFS clonefile でファイルコピーが高速
