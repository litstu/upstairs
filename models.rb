require 'bundler/setup'
require 'sinatra/activerecord'
Bundler.require

# 本番（Render）と開発（Cloud9）の設定を Sinatra に直接指定

class User < ActiveRecord::Base
  has_secure_password
  validates :username, presence: true, uniqueness: true

  has_many :tasks, dependent: :destroy
  has_many :focus_sessions, dependent: :destroy
  has_many :ai_decompose_logs, dependent: :destroy

  def add_points(amount)
    increment!(:points, amount)
  end
  
  # models.rb の class User < ActiveRecord::Base 内に追加
def current_streak
    # 学習記録のある日付（降順・重複なし）を取得
    dates = focus_sessions.pluck(:focused_at).compact.map(&:to_date).uniq.sort.reverse
    return 1 if dates.empty? # 記録がない場合の初期値を 1 に設定

    today = Date.today
    yesterday = today - 1

    # 今日・昨日に記録がない場合も 1 を返す
    return 1 unless dates.include?(today) || dates.include?(yesterday)

    streak = 0
    check_date = dates.include?(today) ? today : yesterday

    while dates.include?(check_date)
      streak += 1
      check_date -= 1
    end

    [streak, 1].max # 最低でも 1 を保証
  end
  
end

class Task < ActiveRecord::Base
  belongs_to :user
  has_many :focus_sessions, dependent: :destroy
  has_many :subtasks, dependent: :destroy
  has_many :child_tasks, class_name: 'Task', foreign_key: 'parent_task_id', dependent: :destroy
  belongs_to :parent_task, class_name: 'Task', optional: true
  has_many :ai_decompose_logs, dependent: :destroy

  COLORS = %w[sky violet rose amber emerald orange].freeze

  def effective_color
    parent_task ? parent_task.color : color
  end
end

class AiDecomposeLog < ActiveRecord::Base
  belongs_to :task
  belongs_to :user
end

class FocusSession < ActiveRecord::Base
  belongs_to :user
  belongs_to :task
end

class Subtask < ActiveRecord::Base
  belongs_to :task
end