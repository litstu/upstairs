# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 4) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "ai_decompose_logs", force: :cascade do |t|
    t.integer "task_id", null: false
    t.integer "user_id", null: false
    t.text "result", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["task_id"], name: "index_ai_decompose_logs_on_task_id"
    t.index ["user_id"], name: "index_ai_decompose_logs_on_user_id"
  end

  create_table "focus_sessions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "task_id", null: false
    t.integer "duration_minutes", null: false
    t.date "focused_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["task_id"], name: "index_focus_sessions_on_task_id"
    t.index ["user_id"], name: "index_focus_sessions_on_user_id"
  end

  create_table "subtasks", force: :cascade do |t|
    t.integer "task_id", null: false
    t.string "name", null: false
    t.date "due_date"
    t.boolean "completed", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["task_id"], name: "index_subtasks_on_task_id"
  end

  create_table "tasks", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "name", null: false
    t.text "description"
    t.date "due_date"
    t.boolean "completed", default: false, null: false
    t.integer "parent_task_id"
    t.string "color", default: "sky", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["parent_task_id"], name: "index_tasks_on_parent_task_id"
    t.index ["user_id"], name: "index_tasks_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "username", null: false
    t.string "password_digest", null: false
    t.integer "points", default: 150, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "show_in_ranking", default: false, null: false
    t.boolean "leaderboard_notified", default: false, null: false
    t.index ["username"], name: "index_users_on_username", unique: true
  end
end
