class CreateTables < ActiveRecord::Migration[7.2]
  def change
    # ============================================
    # users テーブル
    # アプリを使うユーザーを保存する
    # ============================================
    create_table :users, if_not_exists: true do |t|
      t.string  :username,        null: false
      t.string  :password_digest, null: false
      t.integer :points,          null: false, default: 150
      t.timestamps

      # ユーザー名は重複できないようにする
      t.index :username, unique: true
    end

    # ============================================
    # tasks テーブル
    # ユーザーが登録するタスク（やること）を保存する
    # parent_task_id が入っているものは「子タスク（AI が分解した小タスク）」
    # ============================================
    create_table :tasks, if_not_exists: true do |t|
      t.integer :user_id,        null: false
      t.string  :name,           null: false
      t.text    :description
      t.date    :due_date
      t.boolean :completed,      null: false, default: false
      t.integer :parent_task_id
      t.string  :color,          null: false, default: 'sky'
      t.timestamps

      t.index :user_id
      t.index :parent_task_id
    end

    # ============================================
    # focus_sessions テーブル
    # 集中タイマーを完走した記録を保存する
    # ============================================
    create_table :focus_sessions, if_not_exists: true do |t|
      t.integer :user_id,          null: false
      t.integer :task_id,          null: false
      t.integer :duration_minutes, null: false
      t.date    :focused_at,       null: false
      t.timestamps

      t.index :user_id
      t.index :task_id
    end

    # ============================================
    # subtasks テーブル
    # タスクをさらに細かく分けたサブタスクを保存する
    # ============================================
    create_table :subtasks, if_not_exists: true do |t|
      t.integer :task_id,   null: false
      t.string  :name,      null: false
      t.date    :due_date
      t.boolean :completed, null: false, default: false
      t.timestamps

      t.index :task_id
    end

    # ============================================
    # ai_decompose_logs テーブル
    # AI にタスクを分解してもらった結果を履歴として保存する
    # ============================================
    create_table :ai_decompose_logs, if_not_exists: true do |t|
      t.integer :task_id, null: false
      t.integer :user_id, null: false
      t.text    :result,  null: false
      t.timestamps

      t.index :task_id
      t.index :user_id
    end
  end
end
