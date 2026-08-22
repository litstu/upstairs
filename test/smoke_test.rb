ENV['RACK_ENV'] = 'test'
require_relative '../app'
require 'rack/test'

# ============================================
# スモークテスト
# 主要ルートが正常に動くかを確認する
# `ruby test/smoke_test.rb` で実行する
# ============================================
class SmokeTest
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def run_all
    test_top_page
    test_register_page
    test_login
    test_mypage_after_login
    test_calendar_after_login
    test_timer_after_login
    test_task_create
    test_task_delete
    test_task_from_step
    test_task_complete
    test_session_record
    test_ai_connection
    puts "All smoke tests passed!"
  end

  # ============================================
  # GET / → 200 を返すか確認する
  # ============================================
  def test_top_page
    get '/'
    raise "GET / failed: #{last_response.status}" unless last_response.ok?
    puts "  [OK] GET /"
  end

  # ============================================
  # GET /register → 200 を返すか確認する
  # ============================================
  def test_register_page
    get '/register'
    raise "GET /register failed: #{last_response.status}" unless last_response.ok?
    puts "  [OK] GET /register"
  end

  # ============================================
  # POST /login（shiki/password123）→ 303 でリダイレクトするか確認する
  # ============================================
  def test_login
    post '/login', username: 'shiki', password: 'password123'
    # ログイン成功時は /mypage へのリダイレクト（303）
    unless last_response.redirect?
      raise "POST /login failed: #{last_response.status} (expected redirect)"
    end
    puts "  [OK] POST /login"
  end

  # ============================================
  # ログイン済みで GET /mypage → 200 を返すか確認する
  # ============================================
  def test_mypage_after_login
    # ログイン状態を確保する
    login_as_shiki
    get '/mypage'
    raise "GET /mypage failed: #{last_response.status}" unless last_response.ok?
    puts "  [OK] GET /mypage (logged in)"
  end

  # ============================================
  # ログイン済みで GET /calendar → 200 を返すか確認する
  # ============================================
  def test_calendar_after_login
    login_as_shiki
    get '/calendar'
    raise "GET /calendar failed: #{last_response.status}" unless last_response.ok?
    puts "  [OK] GET /calendar (logged in)"
  end

  # ============================================
  # ログイン済みで GET /timer/:task_id → 200 を返すか確認する
  # shiki の未完了タスクの ID を DB から取得して使う
  # ============================================
  def test_timer_after_login
    login_as_shiki
    # DB から shiki ユーザーの未完了タスクを 1 件取得する
    shiki = User.find_by(username: 'shiki')
    task = shiki.tasks.where(completed: false).first
    unless task
      raise "shiki の未完了タスクが見つからない（seeds.rb を確認してください）"
    end
    get "/timer/#{task.id}"
    raise "GET /timer/#{task.id} failed: #{last_response.status}" unless last_response.ok?
    puts "  [OK] GET /timer/:task_id (logged in)"
  end

  # ============================================
  # ログイン済みで POST /tasks（タスク登録）→ 303、その後 /mypage が 200
  # ============================================
  def test_task_create
    login_as_shiki
    post '/tasks', name: 'スモークテスト用タスク', due_date: '2026-09-01'
    unless last_response.redirect?
      raise "POST /tasks failed: #{last_response.status} (expected redirect)"
    end
    follow_redirect!
    raise "GET /mypage after task create failed: #{last_response.status}" unless last_response.ok?
    puts "  [OK] POST /tasks → /mypage"
  end

  # ============================================
  # ログイン済みで POST /tasks/:id/delete（タスク削除）→ 303
  # ============================================
  def test_task_delete
    login_as_shiki
    shiki = User.find_by(username: 'shiki')
    # 削除専用のタスクを作ってから削除する
    task = shiki.tasks.create(name: '削除テスト用タスク')
    post "/tasks/#{task.id}/delete"
    unless last_response.redirect?
      raise "POST /tasks/:id/delete failed: #{last_response.status} (expected redirect)"
    end
    follow_redirect!
    raise "GET /mypage after delete failed: #{last_response.status}" unless last_response.ok?
    puts "  [OK] POST /tasks/:id/delete → /mypage"
  end

  # ============================================
  # ログイン済みで POST /tasks/from_step（AI ステップ採用）→ JSON 200
  # ============================================
  def test_task_from_step
    login_as_shiki
    post '/tasks/from_step', step_name: 'スモークテスト用ステップ'
    raise "POST /tasks/from_step failed: #{last_response.status}" unless last_response.ok?
    puts "  [OK] POST /tasks/from_step → 200 JSON"
  end

  # ============================================
  # ログイン済みで POST /tasks/:id/toggle（タスク完了切り替え）→ JSON 200
  # ============================================
  def test_task_complete
    login_as_shiki
    shiki = User.find_by(username: 'shiki')
    task = shiki.tasks.where(completed: false).first
    unless task
      raise "shiki の未完了タスクが見つからない（seeds.rb を確認してください）"
    end
    post "/tasks/#{task.id}/toggle"
    raise "POST /tasks/:id/toggle failed: #{last_response.status}" unless last_response.ok?
    puts "  [OK] POST /tasks/:id/toggle → 200 JSON"
  end

  # ============================================
  # ログイン済みで POST /sessions（セッション記録）→ 303 で /calendar へ
  # ============================================
  def test_session_record
    login_as_shiki
    # DB から shiki ユーザーのタスクを 1 件取得する
    shiki = User.find_by(username: 'shiki')
    task = shiki.tasks.first
    unless task
      raise "shiki のタスクが見つからない（seeds.rb を確認してください）"
    end
    post '/sessions', task_id: task.id, duration_minutes: 25
    unless last_response.redirect?
      raise "POST /sessions failed: #{last_response.status} (expected redirect)"
    end
    follow_redirect!
    raise "GET /calendar after session record failed: #{last_response.status}" unless last_response.ok?
    puts "  [OK] POST /sessions → /calendar"
  end

  # ============================================
  # AI 接続テスト
  # SMOKE_SKIP_AI=1 または ANTHROPIC_AUTH_TOKEN が空のときはスキップする
  # ============================================
  def test_ai_connection
    # スキップ条件の確認
    if ENV['SMOKE_SKIP_AI'] == '1'
      puts "  [SKIP] AI connection test (SMOKE_SKIP_AI=1)"
      return
    end
    unless defined?(ask_ai)
      puts "  [SKIP] AI connection test (ask_ai not defined)"
      return
    end
    if ENV['ANTHROPIC_AUTH_TOKEN'].to_s.empty?
      puts "  [SKIP] AI connection test (ANTHROPIC_AUTH_TOKEN not set)"
      return
    end

    # 実際に AI Gateway に接続して動作を確認する
    res = ask_ai([{ role: 'user', content: [{ text: 'テスト。「ok」とだけ返して。' }] }])
    if res.nil? || res.to_s.strip.empty? || res.include?('エラーが発生しました')
      raise "AI connection failed: #{res}"
    end
    puts "  [OK] AI connection"
  end

  private

  # ============================================
  # shiki としてログインするヘルパーメソッド
  # ============================================
  def login_as_shiki
    post '/login', username: 'shiki', password: 'password123'
  end
end

SmokeTest.new.run_all if __FILE__ == $0
