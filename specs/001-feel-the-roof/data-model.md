# Data Model: FeelTheRoof

## エンティティ一覧

### User（ユーザー）
アカウント名とパスワードで管理。自分のタスクのみ閲覧・操作できる。

| フィールド | 型 | 制約 |
|---|---|---|
| id | integer | PK, auto |
| username | string | NOT NULL, UNIQUE |
| password_digest | string | NOT NULL（bcryptハッシュ） |
| created_at | datetime | auto |

### Task（タスク）
ユーザーが登録するタスク。締め切り日と完了フラグを持つ。

| フィールド | 型 | 制約 |
|---|---|---|
| id | integer | PK, auto |
| user_id | integer | FK → users.id, NOT NULL |
| name | string | NOT NULL |
| due_date | date | nullable |
| completed | boolean | NOT NULL, default false |
| created_at | datetime | auto |

### FocusSession（集中セッション）
タイマー完了ごとに記録。カレンダー表示に使う。

| フィールド | 型 | 制約 |
|---|---|---|
| id | integer | PK, auto |
| user_id | integer | FK → users.id, NOT NULL |
| task_id | integer | FK → tasks.id, NOT NULL |
| duration_minutes | integer | NOT NULL |
| focused_at | date | NOT NULL |
| created_at | datetime | auto |

### Subtask（サブタスク）
AIが分解したスモールステップ。親タスクに紐づく。

| フィールド | 型 | 制約 |
|---|---|---|
| id | integer | PK, auto |
| task_id | integer | FK → tasks.id, NOT NULL |
| name | string | NOT NULL |
| due_date | date | nullable |
| completed | boolean | NOT NULL, default false |
| created_at | datetime | auto |

## リレーション

```
User ─── has_many ──→ Task
User ─── has_many ──→ FocusSession
Task ─── has_many ──→ FocusSession
Task ─── has_many ──→ Subtask
```
