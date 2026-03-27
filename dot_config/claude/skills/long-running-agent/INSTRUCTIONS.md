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

## Context Reset 戦略

### Compaction vs Context Reset

| 手法 | メリット | デメリット | 適用場面 |
|------|---------|-----------|---------|
| Compaction (`/compact`) | 自動、連続性維持 | context anxiety残存、要約劣化 | 中規模タスク |
| Fork Session (`--fork-session`) | クリーンスレート、履歴保持 | セッション権限の再承認が必要 | 大規模タスク |

### Context Reset の実行方法

compaction が2回以上発生した場合、または品質低下の兆候がある場合に検討する。

**品質低下の兆候:**
- 以前決めた設計方針を忘れている
- 同じファイルを何度も読み直している
- 回答が冗長・反復的になっている
- タスクの完了を急ぎ始めている（context anxiety）

**手順:**

1. **セッション保存**: `/save-session context-reset` で詳細な引き継ぎを保存

2. **ユーザーへの提案** — 以下のいずれかを提案:

**方法A: Fork Session（推奨）**
```
Context reset を推奨する。以下を実行してほしい:
claude --continue --fork-session
```
- 既存の会話履歴を保持しつつ新しいコンテキストで再開

**方法B: Branch（UI操作）**
```
/branch context-reset
```
- 現在のセッションから分岐して新しいパスで作業を継続

**方法C: 新規セッション + 手動読み込み**
```
新しいセッションを開始し、/load-session latest で引き継ぎ情報を読み込んでほしい。
```

### 補助: handoff.json（オプション）

構造化されたハンドオフが必要な場合（特に feature_list.json を使う大規模プロジェクト）、
`/save-session` に加えて以下のファイルを作成する:

```json
{
  "schema_version": 1,
  "created_at": "ISO timestamp",
  "task": {
    "original_prompt": "ユーザーの元のリクエスト",
    "spec_path": "plan ファイルパス（あれば）",
    "feature_list_path": "feature_list.json（あれば）"
  },
  "progress": {
    "completed": ["完了した機能/タスクのリスト"],
    "in_progress": "現在取り組んでいること",
    "remaining": ["未着手のタスクリスト"],
    "current_branch": "ブランチ名",
    "last_commit": "SHA"
  },
  "decisions": [
    {
      "what": "決定内容",
      "why": "理由",
      "alternatives_rejected": ["却下した代替案"]
    }
  ],
  "context": {
    "key_files": ["重要なファイルパス"],
    "gotchas": ["注意点、罠、特殊な事情"],
    "next_steps": ["具体的な次のアクション"]
  }
}
```

SessionStart hook は `ai/state/handoff.json` を自動検出し、存在する場合はコンテキストに注入する。
SessionEnd hook は軽量な git 状態スナップショットのみ生成する（補助的手段）。

## 関連コマンド

- `/save-session` - 詳細な引き継ぎ情報を手動保存
- `/load-session` - 過去のセッション情報を読み込み
- `/orc` - 複雑タスクの並列分解・実行
