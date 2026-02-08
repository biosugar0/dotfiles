---
name: long-running-agent
description: 複数のコンテキストウィンドウにまたがる大規模タスクを検出した際に自動発動。セッション分割、進捗保存、引き継ぎの最適パターンを適用する。
user-invocable: false
---

# 長期実行エージェントパターン

複数セッションにまたがる作業での最適なコンテキスト管理手法。

## コア原則

### 1. インクリメンタル作業
- **1セッション1機能**: 明確な完了条件を持つ単位で区切る
- **one-shot禁止**: 大きなタスクを一度に完了しようとしない
- **検証してからマーク**: 機能完了時はテストで確認後にTodoを完了

### 2. セッション境界の設計

```
[セッション開始]
     ↓
SessionStart hook が自動注入:
- git履歴
- 直近のセッション引き継ぎ
- feature_list.json状態
     ↓
[作業実行]
     ↓
コンテキスト満杯 or 手動compact
     ↓
PreCompact hook が自動保存:
- ai/log/sessions/YYYY-MM-DD-HHMM-compact-{trigger}.md
     ↓
[セッション継続 or 終了]
```

## セッション終了時のベストプラクティス

### 必須アクション
1. **git commit**: 進捗を必ずコミット
2. **クリーンな状態**: マージ可能な状態で残す
3. **TodoList更新**: 完了/未完了を正確に反映

### 推奨アクション
- 重要な決定事項がある場合: `/save-session` で詳細記録
- 次のタスクが明確な場合: TodoListに残す

## コンテキスト効率化テクニック

### 情報の階層化
```
[常駐] CLAUDE.md → 最小限の指示のみ
[自動発動] skills → 必要時のみロード
[明示呼出] commands → ユーザー判断でロード
[独立実行] agents → コンテキスト分離
```

### サブエージェント活用
- **試行錯誤タスク**: ci-quality-checker等で独立実行
- **探索的調査**: 結果のみ親に返す
- **並列処理**: /orc で複数サブタスクを同時実行

## 機能追跡（大規模プロジェクト向け）

`feature_list.json` で状態管理:

```json
{
  "features": [
    {
      "id": "auth-001",
      "description": "ユーザーがログインできる",
      "priority": 1,
      "passes": false
    }
  ]
}
```

SessionStart hookがこのファイルを自動検出し、未完了機能を注入する。

## セッション引き継ぎファイル

### 自動生成（PreCompact hook）
- 場所: `ai/log/sessions/YYYY-MM-DD-HHMM-compact-{trigger}.md`
- 内容: git状態、使用ツール、触れたファイル
- トリガー: コンテキスト満杯時、手動compact時

### 手動生成（/save-session）
- 場所: `ai/log/sessions/YYYY-MM-DD-HH-{suffix}.md`
- 内容: 詳細な作業記録、決定事項、次のアクション
- 用途: 重要な引き継ぎが必要な場合

## 関連コマンド

- `/save-session` - 詳細な引き継ぎ情報を手動保存
- `/load-session` - 過去のセッション情報を読み込み
- `/orc` - 複雑タスクの並列分解・実行
