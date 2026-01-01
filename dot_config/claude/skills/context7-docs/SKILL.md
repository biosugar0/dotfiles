---
name: context7-docs
description: ライブラリやフレームワークのドキュメントが必要な場合に自動発動。Context7 MCPを使用して最新の公式ドキュメントを取得する。
---

# Context7 ドキュメント参照

ライブラリ使用方法について回答する際は、自分の知識だけに頼らず最新ドキュメントを確認する。

## 手順

### 1. ライブラリIDの解決

```
mcp__context7__resolve-library-id
```

- ライブラリ名からContext7互換のIDを取得
- ユーザーが `/org/project` 形式で指定した場合はスキップ可

### 2. ドキュメント取得

```
mcp__context7__get-library-docs
```

- `topic` パラメータで特定トピックに焦点を当てる
- バージョン固有の情報が必要な場合は適切なバージョンを指定

## 例

```
# React Hooksについて調べる
1. resolve-library-id("react")
2. get-library-docs(library_id, topic="hooks")

# Next.js App Routerについて調べる
1. resolve-library-id("next.js")
2. get-library-docs(library_id, topic="app router")
```

## 原則

- **常に最新情報を確認**: 古い知識で誤った回答をしない
- **公式ドキュメント優先**: Stack Overflow等より公式を信頼
- **バージョン意識**: 破壊的変更がある場合は特に注意
