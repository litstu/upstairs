# db/seeds.rb
# ============================================
# ダミーデータの投入
# `bundle exec rake db:seed` で実行される
# 何度実行しても同じ状態になるよう、先頭で既存データを削除する
# ============================================

# 依存関係がある順番で削除する（子テーブルから先に）
AiDecomposeLog.destroy_all
Subtask.destroy_all
FocusSession.destroy_all
Task.destroy_all
User.destroy_all

# ============================================
# テスト用ユーザーを2件作成する
# has_secure_password が password を password_digest に変換する
# ============================================
shiki = User.create!(
  username: "shiki",
  password: "password123"
)

testuser = User.create!(
  username: "testuser",
  password: "test123"
)

# ============================================
# shiki のタスクを作成する（12件）
# due_date は 2026-08-01〜2026-08-31 の範囲で設定
# completed が true のものを 4 件含める
# ============================================
tasks_data = [
  # 完了済みタスク（completed: true）
  {
    name: "数学のレポートを完成させる",
    due_date: Date.new(2026, 8, 5),
    completed: true
  },
  {
    name: "英語の単語を50個暗記する",
    due_date: Date.new(2026, 8, 8),
    completed: true
  },
  {
    name: "プログラミング入門の第3章を読む",
    due_date: Date.new(2026, 8, 10),
    completed: true
  },
  {
    name: "週次のタスク振り返りをまとめる",
    due_date: Date.new(2026, 8, 3),
    completed: true
  },

  # 未完了タスク（completed: false）
  {
    name: "物理の問題集を10問解く",
    due_date: Date.new(2026, 8, 12),
    completed: false
  },
  {
    name: "読書感想文の下書きを書く",
    due_date: Date.new(2026, 8, 15),
    completed: false
  },
  {
    name: "Ruby on Rails の基礎チュートリアルを進める",
    due_date: Date.new(2026, 8, 18),
    completed: false
  },
  {
    name: "化学の実験レポートを仕上げる",
    due_date: Date.new(2026, 8, 20),
    completed: false
  },
  {
    name: "模擬試験の過去問を3年分解く",
    due_date: Date.new(2026, 8, 25),
    completed: false
  },
  {
    name: "英語のリスニング練習を30分する",
    due_date: Date.new(2026, 8, 22),
    completed: false
  },
  {
    name: "歴史の年表をノートにまとめる",
    due_date: Date.new(2026, 8, 28),
    completed: false
  },
  {
    name: "夏休みの自由研究のテーマを決める",
    due_date: Date.new(2026, 8, 31),
    completed: false
  }
]

# タスクを一件ずつ作成してリストに保存する（FocusSession 作成時に参照するため）
created_tasks = tasks_data.map do |data|
  Task.create!(data.merge(user_id: shiki.id))
end

# ============================================
# shiki の集中セッションを作成する（7件）
# focused_at は 2026-07-20〜2026-08-07 の範囲で設定
# ============================================
focus_sessions_data = [
  {
    task: created_tasks[0],  # 数学のレポートを完成させる
    duration_minutes: 45,
    focused_at: Date.new(2026, 7, 20)
  },
  {
    task: created_tasks[1],  # 英語の単語を50個暗記する
    duration_minutes: 25,
    focused_at: Date.new(2026, 7, 25)
  },
  {
    task: created_tasks[0],  # 数学のレポートを完成させる（2回目）
    duration_minutes: 50,
    focused_at: Date.new(2026, 7, 28)
  },
  {
    task: created_tasks[2],  # プログラミング入門の第3章を読む
    duration_minutes: 30,
    focused_at: Date.new(2026, 8, 1)
  },
  {
    task: created_tasks[4],  # 物理の問題集を10問解く
    duration_minutes: 60,
    focused_at: Date.new(2026, 8, 3)
  },
  {
    task: created_tasks[6],  # Ruby on Rails の基礎チュートリアルを進める
    duration_minutes: 45,
    focused_at: Date.new(2026, 8, 5)
  },
  {
    task: created_tasks[5],  # 読書感想文の下書きを書く
    duration_minutes: 25,
    focused_at: Date.new(2026, 8, 7)
  }
]

focus_sessions_data.each do |data|
  FocusSession.create!(
    user_id: shiki.id,
    task_id: data[:task].id,
    duration_minutes: data[:duration_minutes],
    focused_at: data[:focused_at]
  )
end

# ============================================
# testuser のタスクを2件だけ作成する（動作確認用）
# ============================================
Task.create!(
  user_id: testuser.id,
  name: "Git の基本操作を練習する",
  due_date: Date.new(2026, 8, 15),
  completed: false
)

Task.create!(
  user_id: testuser.id,
  name: "ポートフォリオのデザインを考える",
  due_date: Date.new(2026, 8, 20),
  completed: false
)

# 投入結果を出力する
puts "ユーザー: #{User.count} 件"
puts "タスク: #{Task.count} 件"
puts "集中セッション: #{FocusSession.count} 件"
puts "ダミーデータの投入が完了しました"
