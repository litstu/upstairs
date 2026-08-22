require 'bundler/setup'
Bundler.require

ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: 'db/development.sqlite3'
)

Time.zone = 'Tokyo'
ActiveRecord.default_timezone = :local

# ============================================
# User モデル
# アプリを使うユーザーを管理する
# has_secure_password で bcrypt によるパスワードハッシュ化を有効にする
# ============================================
class User < ActiveRecord::Base
  # bcrypt でパスワードを安全にハッシュ化する
  has_secure_password

  # ユーザー名は必須かつ一意であることを保証する
  validates :username, presence: true, uniqueness: true

  # 1 人のユーザーは複数のタスクを持てる
  # dependent: :destroy = ユーザーを消したら、そのユーザーのタスクも一緒に消す
  has_many :tasks, dependent: :destroy

  # 1 人のユーザーは複数の集中セッションを持てる
  has_many :focus_sessions, dependent: :destroy

  # 1 人のユーザーは複数の AI 分解ログを持てる
  has_many :ai_decompose_logs, dependent: :destroy

  # ポイントを加算して保存するメソッド
  def add_points(amount)
    increment!(:points, amount)
  end
end

# ============================================
# Task モデル
# ユーザーが登録するタスク（やること）を管理する
# ============================================
class Task < ActiveRecord::Base
  # タスクは必ずどこかのユーザーに属する
  belongs_to :user

  # 1 つのタスクは複数の集中セッションを持てる
  # dependent: :destroy = タスクを消したら、そのタスクの記録も一緒に消す
  # （これをしないと「消えたタスクの記録」が残ってカレンダーでエラーになる）
  has_many :focus_sessions, dependent: :destroy

  # 1 つのタスクは複数のサブタスクを持てる
  has_many :subtasks, dependent: :destroy

  # 子タスク（AIに分解で生成された小タスク）
  # 親タスクを消したら子タスクも一緒に消す
  has_many :child_tasks, class_name: 'Task', foreign_key: 'parent_task_id', dependent: :destroy

  # 親タスク（子タスクの場合にセットされる）
  belongs_to :parent_task, class_name: 'Task', optional: true

  # AI分解のログ
  has_many :ai_decompose_logs, dependent: :destroy

  # 使用できる色の一覧（Tailwindのカラー名）
  COLORS = %w[sky violet rose amber emerald orange].freeze

  # 子タスクが使う実際の色（親がいれば親の色を使う）
  def effective_color
    parent_task ? parent_task.color : color
  end
end

# ============================================
# AiDecomposeLog モデル
# AIに分解した際の会話ログを保存する
# ============================================
class AiDecomposeLog < ActiveRecord::Base
  belongs_to :task
  belongs_to :user
end

# ============================================
# FocusSession モデル
# ユーザーがタスクに集中した記録を管理する
# ============================================
class FocusSession < ActiveRecord::Base
  # 集中セッションは必ずどこかのユーザーに属する
  belongs_to :user

  # 集中セッションは必ずどこかのタスクに属する
  belongs_to :task
end

# ============================================
# Subtask モデル
# タスクをさらに細かく分けたサブタスクを管理する
# ============================================
class Subtask < ActiveRecord::Base
  # サブタスクは必ずどこかのタスクに属する
  belongs_to :task
end
