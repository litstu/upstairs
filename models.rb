require 'bundler/setup'
Bundler.require

# 本番（Render）と開発（Cloud9）でデータベース接続を分岐
if ENV['DATABASE_URL']
  ActiveRecord::Base.establish_connection(ENV['DATABASE_URL'])
else
  ActiveRecord::Base.establish_connection(
    adapter: 'sqlite3',
    database: 'db/development.sqlite3'
  )
end

Time.zone = 'Tokyo'
ActiveRecord.default_timezone = :local

class User < ActiveRecord::Base
  has_secure_password
  validates :username, presence: true, uniqueness: true

  has_many :tasks, dependent: :destroy
  has_many :focus_sessions, dependent: :destroy
  has_many :ai_decompose_logs, dependent: :destroy

  def add_points(amount)
    increment!(:points, amount)
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