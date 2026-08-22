# Tasks: FeelTheRoof

**Input**: Design documents from `/specs/001-feel-the-roof/`

---

## Phase 1: セットアップ（共通インフラ）

**Purpose**: DBスキーマ・モデル・ログイン基盤の準備

- [X] T001 db/schema.rb に users・tasks・focus_sessions・subtasks テーブルを定義する
- [X] T002 models.rb に User・Task・FocusSession・Subtask モデルとアソシエーションを定義する（bcrypt の has_secure_password を含む）
- [X] T003 db/seeds.rb にテスト用ユーザー2件とタスク10件以上のダミーデータを入れる（タスク名はリアルな学習・仕事のタスク名にする）
- [X] T004 app.rb にセッション管理の設定とログイン確認ヘルパーメソッドを追加する

---

## Phase 2: ログイン機能（基盤）

**Purpose**: 全機能のベースとなるユーザー認証

- [X] T005 [US1] views/index.erb にトップ（未ログイン時のログインフォーム＋新規登録リンク）を作る
- [X] T006 [US1] views/register.erb に新規登録フォームを作る
- [X] T007 [US1] app.rb に `GET /`・`GET /register`・`POST /register`・`POST /login`・`POST /logout` のルートを追加する

---

## Phase 3: US1 - タスク登録と集中タイマー（P1・MVPコア）

**Goal**: タスク登録 → 集中タイマー開始 → BongoCat風キャラ表示 → タイマー完了 → 達成記録

**Independent Test**: ログイン後にタスクを1件登録し、集中開始ボタンを押してタイマーが動き、完了後にカレンダーに記録されていることを確認

- [X] T008 [US1] views/mypage.erb にタスク一覧と新規タスク登録フォームを作る（タスク名・締め切り日・集中開始ボタン）
- [X] T009 [US1] app.rb に `GET /mypage`・`POST /tasks`・`POST /tasks/:id/complete` のルートを追加する
- [X] T010 [US1] views/timer.erb に集中タイマー画面を作る（BongoCat風CSSアニメーション・大きなカウントダウン数字・スタート/停止ボタン）
- [X] T011 [US1] public/css/style.css に BongoCat風キャラクターのCSSアニメーションとタイマー数字のグロウ効果を追加する
- [X] T012 [US1] public/js/timer.js に JavaScript のカウントダウンタイマーロジックを書く（25分・カウントダウン・完了検知）
- [X] T013 [US1] app.rb に `GET /timer/:task_id`・`POST /sessions` のルートを追加する
- [X] T014 [US1] views/timer_complete.erb に達成ポップアップ画面を作る（完了タスク名・AI励ましメッセージ表示エリア・カレンダーへのリンク）

---

## Phase 4: US2 - 締め切り設定とカレンダー（P2）

**Goal**: タスクの締め切りが設定でき、カレンダーで達成履歴を振り返れる

**Independent Test**: 締め切りを設定したタスクがタスク一覧に締め切り日付きで表示され、タイマー完了後にカレンダーで達成マークが確認できること

- [X] T015 [US2] views/calendar.erb にカレンダー画面を作る（月間表示・達成マーク付き・日付クリックで完了タスク表示）
- [X] T016 [US2] app.rb に `GET /calendar` のルートを追加する（ログインユーザーの focus_sessions を月ごとに集計して渡す）

---

## Phase 5: US3 - AIによるスモールステップ分解と励まし（P3）

**Goal**: AIがタスクをスモールステップに分解してくれる、タイマー完了後にAIが励ましてくれる

**Independent Test**: タスク詳細でAI分解ボタンを押すとステップが表示され、タイマー完了後にAIの励ましメッセージが表示されること

- [X] T017 [US3] views/ai_decompose.erb にAI分解結果表示画面を作る（スモールステップのリスト・各ステップの採用ボタン）
- [X] T018 [US3] app.rb に `POST /ai/decompose` のルートを追加する（ask_ai でタスク分解プロンプトを送り結果を表示）
- [X] T019 [US3] app.rb に `POST /ai/encourage` のルートを追加する（ask_ai で励ましメッセージを取得してJSONで返す）
- [X] T020 [US3] public/js/timer.js のタイマー完了時の処理に `/ai/encourage` を呼び出して達成ポップアップにメッセージを表示する処理を追加する

---

## Phase 6: ポリッシュ・仕上げ

**Purpose**: 全画面の見た目をデザイン仕様に合わせ、整合性を確認する

- [X] T021 views/layout.erb のタイトルを「FeelTheRoof」に変更し、data-theme が `night` になっていることを確認する
- [X] T022 [P] 全ビュー（index・register・mypage・timer・calendar・ai_decompose）のデザインを plan.md のデザイン仕様（nightテーマ・スカイブルー差し色）に統一する
- [X] T023 test/smoke_test.rb を作成して主要ルートのスモークテストを書き、全テストがパスすることを確認する
- [X] T024 全体の整合性を確認し、サーバーが正常に起動することを検証する（bundle install → rake db:create db:migrate db:seed → smoke test 実行）

---

## 依存関係と実行順

- **Phase 1**: すぐ始められる（基盤）
- **Phase 2**: Phase 1 完了後
- **Phase 3（US1）**: Phase 2 完了後 ── これが動けば MVP！
- **Phase 4（US2）**: Phase 3 完了後
- **Phase 5（US3）**: Phase 3 完了後（ask_ai が使える状態が必要）
- **Phase 6**: 全フェーズ完了後

## タスク数まとめ

| フェーズ | タスク数 |
|---|---|
| Phase 1: セットアップ | 4 |
| Phase 2: ログイン基盤 | 3 |
| Phase 3: US1 タイマーコア | 7 |
| Phase 4: US2 カレンダー | 2 |
| Phase 5: US3 AI機能 | 4 |
| Phase 6: ポリッシュ | 4 |
| **合計** | **24** |
