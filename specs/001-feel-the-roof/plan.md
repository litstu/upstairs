# Implementation Plan: FeelTheRoof

**Branch**: `001-feel-the-roof` | **Date**: 2026-08-07 | **Spec**: [spec.md](./spec.md)

## Summary

タスクを登録して集中タイマーで習慣化を支援するWebサービス。アカウント名＋パスワードによるログイン、BongoCat風キャラクター表示のタイマー、カレンダーによる達成履歴確認、AIによるタスクのスモールステップ分解と励ましメッセージを提供する。

## Technical Context

**Language/Version**: Ruby 3.4.1

**Primary Dependencies**: Sinatra, ActiveRecord 7.0, PostgreSQL, bcrypt, Tailwind CSS (CDN), DaisyUI (CDN), Phosphor Icons (CDN)

**Storage**: PostgreSQL

**Testing**: rack-test（スモークテストのみ）

**Target Platform**: Webブラウザ（Cloud9プレビュー）

**Project Type**: Web application（Sinatra + ERB）

**Constraints**: キャンプ4〜5日、Cloud9環境、`0.0.0.0:8080`バインド必須

## 画面設計

### 1. トップ / ログイン・新規登録画面（`/`）
- **表示する固定情報**: サービス名「FeelTheRoof」＋キャッチコピー「屋根を突き抜けるくらい集中しよう」
- 未ログインユーザーが最初に見る画面
- ログインフォームと新規登録リンクを表示
- ログイン済みのユーザーは自動的にマイページへリダイレクト

### 2. 新規登録画面（`/register`）
- アカウント名・パスワード入力フォーム

### 3. タスク一覧（マイページ）（`/mypage`）
- **表示する固定情報**: ログインユーザーのアカウント名
- 自分のタスク一覧（タスク名・締め切り日・完了状態）
- 新規タスク登録フォーム（タスク名・締め切り日）
- 各タスクに「集中開始」ボタン
- 各タスクに「AIに分解してもらう」ボタン

### 4. 集中タイマー画面（`/timer/:task_id`）
- **表示する固定情報**: 対象タスク名・タイマー時間（25分固定）
- 画面中央にBongoCat風キャラクター（CSSアニメーション）
- 大きなカウントダウン数字（signuture：ドーンと大きく、スカイブルーに光る感じ）
- スタート・停止ボタン
- タイマー完了後に達成ポップアップ（AIの励ましメッセージ付き）

### 5. カレンダー画面（`/calendar`）
- **表示する固定情報**: ログインユーザーのアカウント名
- 月間カレンダー表示
- 集中セッションが記録された日に達成マーク
- 日付クリックでその日の完了タスク一覧を表示

## AI プロンプト仕様

### ルート1: タスクのスモールステップ分解（`POST /ai/decompose`）

**AI に渡す内容**:
```
あなたはやさしい勉強・仕事の伴走コーチです。
以下のタスクを、取り掛かりやすい小さなステップに分解してください。

タスク名: [ユーザーが入力したタスク名]
締め切り: [締め切り日]

各ステップに「ステップ名」と「目安の期限（日付）」をつけて、
3〜5個のスモールステップとして提案してください。
架空・推測で構いません。実際の進め方はユーザーが自分で決めます。
```

**返してほしい内容**: ステップ名と目安期限のリスト（3〜5個）、やさしいトーンで

### ルート2: タイマー完了後の励まし（`POST /ai/encourage`）

**AI に渡す内容**:
```
あなたはやさしい勉強・仕事の伴走コーチです。
ユーザーが集中タイマーを完走しました。一言、元気が出る励ましのメッセージを送ってください。

完了したタスク: [タスク名]
集中した時間: [分数]分

短め（2〜3文）でポジティブに、具体的なタスク名に触れながら褒めてください。
```

**返してほしい内容**: 2〜3文の励ましメッセージ

## データベース設計

詳細は [data-model.md](./data-model.md) を参照。

### users テーブル
| カラム名 | 型 | 説明 |
|---------|---|------|
| id | integer | 自動で付く番号 |
| username | string | アカウント名（一意） |
| password_digest | string | bcryptでハッシュ化されたパスワード |
| created_at | datetime | 登録日時 |

### tasks テーブル
| カラム名 | 型 | 説明 |
|---------|---|------|
| id | integer | 自動で付く番号 |
| user_id | integer | どのユーザーのタスクか |
| name | string | タスク名 |
| due_date | date | 締め切り日 |
| completed | boolean | 完了フラグ（デフォルト false） |
| created_at | datetime | 登録日時 |

### focus_sessions テーブル
| カラム名 | 型 | 説明 |
|---------|---|------|
| id | integer | 自動で付く番号 |
| user_id | integer | どのユーザーか |
| task_id | integer | どのタスクで集中したか |
| duration_minutes | integer | 集中した分数 |
| focused_at | date | 集中した日付 |
| created_at | datetime | 記録日時 |

### subtasks テーブル
| カラム名 | 型 | 説明 |
|---------|---|------|
| id | integer | 自動で付く番号 |
| task_id | integer | 親タスクのID |
| name | string | スモールステップ名 |
| due_date | date | 目安期限 |
| completed | boolean | 完了フラグ（デフォルト false） |
| created_at | datetime | 作成日時 |

## URL 設計

| URL | メソッド | 何をする？ |
|-----|---------|-----------|
| `/` | GET | トップ（未ログインならログイン画面、ログイン済みならマイページへリダイレクト） |
| `/register` | GET | 新規登録画面を表示 |
| `/register` | POST | アカウントを登録してマイページへリダイレクト |
| `/login` | POST | ログインしてマイページへリダイレクト |
| `/logout` | POST | ログアウトしてトップへリダイレクト |
| `/mypage` | GET | タスク一覧（マイページ）を表示 |
| `/tasks` | POST | 新しいタスクを登録してマイページへリダイレクト |
| `/tasks/:id/complete` | POST | タスクを完了状態にする |
| `/timer/:task_id` | GET | 集中タイマー画面を表示 |
| `/sessions` | POST | 集中セッションを記録してカレンダーへリダイレクト |
| `/calendar` | GET | カレンダー（達成履歴）を表示 |
| `/ai/decompose` | POST | AIにタスク分解を依頼して結果を表示 |
| `/ai/encourage` | POST | タイマー完了後にAIの励ましメッセージを取得 |

## デザイン仕様（固定）

- テーマ（data-theme）: `night`
- 差し色: スカイブルー（`#38BDF8` / Tailwindの `sky-400` 系）/ それ以外はニュートラルダーク
- 見出しフォント: Noto Sans JP / 太め・大きめ（`text-3xl font-bold`〜`text-5xl font-black`）
- 本文フォント: Noto Sans JP / `text-base`・行間ゆったり（`leading-relaxed`）
- signature: タイマー画面の大きなカウントダウン数字（`text-8xl font-black text-sky-400`、薄いグロウ効果）
- 雰囲気の一言: 夜の宇宙みたいな深い紺ダーク × スカイブルーの輝き。かっこよく集中できる
