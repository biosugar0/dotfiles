# Safe Commit

コミット前に以下を確認・実行する。

**注意**: 禁止ディレクトリ（ai/, .serena/）のガードはPreToolUse hookで強制されるため、このスキルでは扱わない。

## 現在の変更状況

```
!`git status --short 2>/dev/null`
```

```
!`git diff --cached --stat 2>/dev/null`
```

## コミット計画

複数の論理的変更がある場合は `/commit-plan` を実行して分割を検討。

## チェックリスト

コミット実行前:
1. [ ] 変更が論理的に分割されているか確認
2. [ ] コミットメッセージが "why" を説明しているか確認
3. [ ] git add はファイル個別指定で行う（`git add .` 禁止）
