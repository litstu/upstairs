require 'bundler/setup'
require 'base64'
require 'json'
# 本番環境では開発用Gemを固定しないよう読み込み
Bundler.require(:default, ENV['RACK_ENV'] || :development)

require 'bundler/setup'
Bundler.require(:default, ENV['RACK_ENV'] || :development)

# DB接続設定を app.rb に配置
set :database, ENV['DATABASE_URL'] || { adapter: 'sqlite3', database: 'db/development.sqlite3' }
# 👇 ここから追加
configure do
  begin
    ActiveRecord::MigrationContext.new('db/migrate', ActiveRecord::SchemaMigration).migrate
  rescue => e
    puts "マイグレーション実行エラー: #{e.message}"
  end
end
# 👆 ここまで追加
# RenderとCloud9両方のポート指定に対応
set :bind, '0.0.0.0'
set :port, ENV['PORT'] || 8080

require 'sinatra/reloader' if development?
require 'bcrypt'

require './models.rb'

# .env ファイルに書いた設定を読み込む（開発環境のみ）
Dotenv.load if development?

# セッションを有効にする（ログイン状態の管理に使う）
enable :sessions
set :session_secret, '0031df07c6cbbfd42f6d913ff3b74f531b70743405125ee6567a8a2a1e213b79b4c1d190722938b60ef8fd82187a297061fb93ffb36cc18f098ccec219ac673b'
# ============================================
# ログイン管理のヘルパーメソッド
# ============================================

# ログイン中のユーザーを取得するメソッド
def current_user
  @current_user ||= User.find_by(id: session[:user_id])
end

# 実在するユーザーが取得できたかどうかを確認するメソッド
def logged_in?
  !current_user.nil?
end

# ログインしていない（またはユーザーが存在しない）場合は
# 古いセッションを消去してトップページへリダイレクトするメソッド
def require_login
  unless logged_in?
    session.clear
    redirect '/'
  end
end

# ============================================
# AI Gateway に質問を送って回答をもらう関数（最初から用意されている道具）
# AI に問い合わせるサービスを作るときに使う。
# messages に質問を渡すと、AI の回答テキストを返してくれる。
# 接続先・アクセスキー・モデルは、セットアップ時に用意された環境変数を自動で使うので、
# .env に鍵を書く必要はない（鍵をプロジェクトに残さない＝流出防止）。
# ============================================
# ============================================
# AI Gateway に質問を送って回答をもらう関数
# ============================================
# ============================================
# Gemini API 通信の共通処理（レート制限・混雑対策付き）
# ============================================
# ============================================
# Gemini API 通信の共通処理（リトライ1回・gemini-1.5-flash指定）
# ============================================
def call_gemini_api(payload, model: 'gemini-3.6-flash')
  key = ENV['GEMINI_API_KEY']
  return { success: false, error: 'GEMINI_API_KEY未設定' } if key.nil? || key.strip.empty?

  conn = Faraday.new(url: 'https://generativelanguage.googleapis.com') do |f|
    f.request :json
    f.response :json
    f.adapter Faraday.default_adapter
  end

  # リトライ回数を1回に変更
  max_retries = 1
  response = nil

  max_retries.times do |attempt|
    response = conn.post("/v1beta/models/#{model}:generateContent?key=#{key.strip}") do |req|
      req.headers['Content-Type'] = 'application/json'
      req.options.timeout = 60
      req.body = payload
    end

    # 成功(200)したらループ脱出
    break if response.status == 200

    if [429, 503, 500, 502, 504].include?(response.status) && attempt < max_retries - 1
      sleep_time = 2 ** (attempt + 1)
      sleep(sleep_time)
    else
      break
    end
  end

  if response && response.status == 200
    text = response.body.dig('candidates', 0, 'content', 'parts', 0, 'text').to_s
    { success: true, text: text }
  else
    status = response ? response.status : 'No response'
    err_msg = response&.body.is_a?(Hash) ? response.body.dig('error', 'message') : response&.body
    { success: false, status: status, error: err_msg }
  end
rescue => e
  { success: false, error: e.message }
end

# ============================================
# AI にテキスト質問を送る関数
# ============================================
def ask_ai(messages)
  prompt_text = ''
  messages.each do |msg|
    contents = msg[:content] || msg['content'] || []
    if contents.is_a?(Array)
      contents.each { |c| prompt_text += (c[:text] || c['text'] || '') + "\n" }
    elsif contents.is_a?(String)
      prompt_text += contents + "\n"
    end
  end

  payload = { contents: [{ parts: [{ text: prompt_text }] }] }
  res = call_gemini_api(payload)

  if res[:success]
    res[:text]
  else
    "エラー詳細: [#{res[:status]}] #{res[:error]}" #"ただいまAIが混み合っているか制限中です☕️\n少し時間をおいてから、もう一度試してみてください。（エラーコード: #{res[:status]}）"
  end
end

# ============================================
# トップページを表示するルート
# ログイン済みならマイページへ、未ログインならトップページを表示する
# ============================================
get '/' do
  # すでにログインしているならマイページへリダイレクト
  redirect '/mypage' if logged_in?
  erb :index
end

# ============================================
# 新規登録画面を表示するルート
# ============================================
get '/register' do
  # すでにログインしているならマイページへリダイレクト
  redirect '/mypage' if logged_in?
  erb :register
end

# ============================================
# アカウント登録を処理するルート
# フォームから送信されたユーザー名・パスワードで新規ユーザーを作成する
# ============================================
post '/register' do
  # フォームの値で新しいユーザーを作成する
  user = User.new(
    username: params[:username],
    password: params[:password],
    password_confirmation: params[:password_confirmation]
  )

  if user.save
    # 登録成功したらセッションにユーザー ID を保存してマイページへ
    session[:user_id] = user.id
    redirect '/mypage'
  else
    # 登録失敗したらエラーメッセージを表示して登録画面に戻る
    @error = user.errors.full_messages.join(', ')
    erb :register
  end
end

# ============================================
# ログインを処理するルート
# アカウント名とパスワードを確認してセッションを開始する
# ============================================
post '/login' do
  # アカウント名でユーザーを検索する
  user = User.find_by(username: params[:username])

  if user && user.authenticate(params[:password])
    # 認証成功したらセッションにユーザー ID を保存してマイページへ
    session[:user_id] = user.id
    redirect '/mypage'
  else
    # 認証失敗したらエラーメッセージを表示してトップページに戻る
    @error = 'アカウント名またはパスワードが正しくありません'
    erb :index
  end
end

# ============================================
# ログアウトを処理するルート
# セッションを削除してトップページへリダイレクトする
# ============================================
post '/logout' do
  # セッションをすべて削除してログアウト状態にする
  session.clear
  redirect '/'
end

# ============================================
# マイページ（タスク一覧）を表示するルート
# ログインしていない場合はトップページへリダイレクトする
# ============================================
get '/mypage' do
  require_login
  @user = current_user

  @parent_tasks = current_user.tasks
    .where(parent_task_id: nil)
    .order(created_at: :desc)
    .includes(:child_tasks)

  # 【変更】今日のタスク（親タスクの情報もまとめて取得）
  @today_tasks = current_user.tasks
    .where(due_date: Date.today, completed: false)
    .includes(parent_task: :parent_task)

  erb :mypage
end
# ============================================
# 新しいタスクを登録するルート
# フォームから送信されたタスク名・期限日を保存してマイページへリダイレクトする
# ============================================
post '/tasks' do
  require_login

  # 1. 親タスクの作成
  task = current_user.tasks.create(
    name: params[:name],
    description: params[:description],
    due_date: params[:due_date].present? ? params[:due_date] : nil,
    color: params[:color] || 'sky'
  )

  files = params[:files] # 複数ファイルを受け取る

  # 2. 写真が添付されている場合、共通処理を呼び出してAIで解析
  if files && files.is_a?(Array) && task.persisted?
    parts = []

    files.each do |file|
      next unless file[:tempfile]
      base64_data = Base64.strict_encode64(file[:tempfile].read)
      parts << { inline_data: { mime_type: file[:type], data: base64_data } }
    end

    if parts.any?
      prompt = <<~PROMPT
        添付されたすべての画像の向きを補正して目次を読み取ってください。
        単元名やSection名を順に抽出し、必ず以下のJSON配列形式のみで返してください。
        [
          {"name": "Part 1 Section 1 形容詞句", "description": "p.16〜"},
          {"name": "Part 1 Section 2 動詞句", "description": "p.20〜"}
        ]
      PROMPT

      parts << { text: prompt }
      payload = {
        contents: [{ parts: parts }],
        generationConfig: { response_mime_type: "application/json" }
      }

      # 共通AI呼び出し関数を使用
      res = call_gemini_api(payload)

      if res[:success]
        begin
          tasks_data = JSON.parse(res[:text])
          tasks_data.each do |t|
            next if t['name'].nil? || t['name'].empty?
            current_user.tasks.create(
              name: t['name'],
              description: t['description'] || '',
              due_date: task.due_date,
              parent_task_id: task.id
            )
          end
        rescue JSON::ParserError => e
          puts "JSON解析エラー: #{e.message}"
        end
      else
        puts "AI処理失敗: #{res[:error]}"
      end
    end
  end

  redirect '/mypage'
end

post '/tasks/upload_ai' do
  require_login

  file = params[:file]
  redirect '/mypage' unless file && file[:tempfile]

  base64_data = Base64.strict_encode64(file[:tempfile].read)
  mime_type = file[:type]

  prompt = <<~PROMPT
    画像の向きが横向きや逆さになっている場合は正しく補正して読み取ってください。
    この画像またはPDFから、学習すべき「Part」「Section」「章」「単元名」などの目次項目を抽出してください。

    以下のキーを持つJSON配列形式で出力してください：
    - "name": 単元名やSection名（例: "Part 1 Section 1 形容詞句・副詞句"）
    - "description": 補足説明やページ数など（例: "p.16〜"）
  PROMPT

  payload = {
    contents: [{
      parts: [
        { inline_data: { mime_type: mime_type, data: base64_data } },
        { text: prompt }
      ]
    }],
    generationConfig: {
      response_mime_type: "application/json"
    }
  }

  # 共通AI呼び出し関数を使用
  res = call_gemini_api(payload)

  if res[:success]
    begin
      tasks_data = JSON.parse(res[:text])
      
      tasks_data.each do |t|
        next if t['name'].nil? || t['name'].empty?
        
        current_user.tasks.create(
          name: t['name'],
          description: t['description'] || '',
          due_date: Date.today + 7
        )
      end
    rescue JSON::ParserError => e
      puts "JSONパースエラー: #{e.message}"
      puts "AI応答内容: #{res[:text]}"
    end
  else
    puts "APIエラー: #{res[:error]}"
  end

  redirect '/mypage'
end

# ============================================
# タスクを編集するルート
# 対象タスクの名前・説明・期限日を更新してマイページへリダイレクトする
# ============================================
post '/tasks/:id/edit' do
  require_login
  # ログインユーザーのタスクのみ更新できるようにする
  task = current_user.tasks.find_by(id: params[:id])
  if task
    attrs = {
      name: params[:name],
      description: params[:description].to_s.empty? ? nil : params[:description],
      due_date: params[:due_date].to_s.empty? ? nil : params[:due_date]
    }
    # 色の変更は親タスクのみ受け付ける（子タスクは親の色を継承するので変更しない）
    if task.parent_task_id.nil? && Task::COLORS.include?(params[:color].to_s)
      attrs[:color] = params[:color]
      # 子タスクにも同じ色を伝播させる
      task.child_tasks.update_all(color: params[:color])
    end
    task.update(attrs)
  end
  redirect '/mypage'
end

# ============================================
# タスクを削除するルート
# 対象のタスクをデータベースから削除してマイページへリダイレクトする
# ============================================
post '/tasks/:id/delete' do
  require_login
  # ログインユーザーのタスクのみ削除できるようにする
  task = current_user.tasks.find_by(id: params[:id])
  task.destroy if task
  redirect '/mypage'
end

# ============================================
# タスクの完了/未完了を切り替えるルート
# チェックを入れると完了（+10pt）、外すと未完了（-10pt）
# ============================================
post '/tasks/:id/toggle' do
  require_login
  task = current_user.tasks.find_by(id: params[:id])
  if task
    new_completed = !task.completed
    task.update(completed: new_completed)

    # 完了にしたとき +10pt、未完了に戻したとき -10pt（0以下にはしない）
    if new_completed
      current_user.add_points(10)

      # ----------------------------------------------------
      # 【分散学習】1日後・3日後・7日後の復習タスクを自動生成
      # ----------------------------------------------------
      # 復習タスク自体の完了時に再生成されないよう「【復習】」から始まらないものだけ対象にする
      unless task.name.start_with?('【復習】')
        [1, 3, 7].each do |days|
          current_user.tasks.create(
            name: "【復習】#{task.name}（#{days}日目）",
            description: "忘却曲線に基づいた復習です。何も見ずに内容を思い出す（アクティブリコール）を試してみましょう！\n元タスク: #{task.name}",
            due_date: Date.today + days,
            parent_task_id: task.id,
            color: task.color
          )
        end
      end
      # ----------------------------------------------------

    else
      current_user.update(points: [current_user.points - 10, 0].max)
    end
  end
  content_type :json
  { completed: task&.completed, points: current_user.points }.to_json
end

# ============================================
# 集中タイマー画面を表示するルート
# ログインしていない場合はトップページへリダイレクトする
# ============================================
get '/timer/:task_id' do
  require_login
  # ログインユーザーのタスクのみ表示できるようにする
  @task = current_user.tasks.find_by(id: params[:task_id])
  # タスクが見つからない場合はマイページへリダイレクト
  redirect '/mypage' unless @task
  erb :timer
end

# ============================================
# 集中セッションを記録してマイページへリダイレクトするルート
# タイマー完了時にフォームから呼び出される
# ============================================
post '/sessions' do
  require_login
  # ログインユーザーのタスクのみ操作できるようにする
  task = current_user.tasks.find_by(id: params[:task_id])
  if task
    # 集中セッションをデータベースに記録する
    FocusSession.create(
      user_id: current_user.id,
      task_id: task.id,
      duration_minutes: params[:duration_minutes].to_i,
      focused_at: Date.today
    )
    # タイマー完走で +100pt
    current_user.add_points(100)
    # タスクをまだ未完了なら完了済みにして追加で +100pt
    unless task.completed
      task.update(completed: true)
      current_user.add_points(100)
    end
  end
  # カレンダーで今日の達成マークが確認できるようにカレンダーへリダイレクト
  redirect '/calendar'
end

# ============================================
# カレンダー（達成履歴）を表示するルート
# ログインユーザーの集中セッションを月ごとに集計して渡す
# ============================================
get '/calendar' do
  require_login
  @user = current_user

  # 表示する年月を決める（クエリパラメータがあればそれを使う、なければ今月）
  @year  = (params[:year]  || Date.today.year).to_i
  @month = (params[:month] || Date.today.month).to_i

  # 前の月・次の月の Date オブジェクトを作る（ナビゲーションリンク用）
  first_of_month = Date.new(@year, @month, 1)
  @prev_month = first_of_month << 1
  @next_month = first_of_month >> 1

  # ログインユーザーのその月の集中セッションを取得して日付ごとにまとめる
  # { Date => [FocusSession, ...] } の形にする
  # joins(:task) を付けて「タスクがもう無い記録」は最初から除外する
  # （タスクを消した後に残った記録を表示しようとすると画面がエラーになるため）
  sessions = current_user.focus_sessions
    .joins(:task)
    .where(focused_at: first_of_month..first_of_month.end_of_month)
    .includes(:task)
  @calendar = sessions.group_by(&:focused_at)

  # その月の各日に締め切りのあるタスクを日付ごとにまとめる
  # 子タスクは parent_task を preload して effective_color を使えるようにする
  # { Date => [Task, ...] } の形にする
  due_tasks = current_user.tasks
    .where(due_date: first_of_month..first_of_month.end_of_month, completed: false)
    .includes(:parent_task)
  @due_tasks_by_date = due_tasks.group_by(&:due_date)

  erb :calendar
end

# ============================================
# AI にタスクのスモールステップ分解を依頼するルート
# ask_ai を使ってタスクを3〜5個のステップに分解して表示する
# ============================================
# ============================================
# AI にタスクのスモールステップ分解を依頼するルート
# ask_ai を使ってタスクを3〜5個のステップに分解して表示する
# ============================================
post '/ai/decompose' do
  require_login
  @task = current_user.tasks.find_by(id: params[:task_id])
  redirect '/mypage' unless @task

  due_date_str = @task.due_date ? @task.due_date.strftime('%Y年%m月%d日') : '未設定'
  today_str = Date.today.strftime('%Y年%m月%d日')
  task_desc_str = @task.description.to_s.strip.empty? ? '特に記載なし' : @task.description

  messages = [
    {
      role: 'user',
      content: [{
        text: <<~PROMPT
          あなたは脳科学と学習心理学に詳しい学習伴走コーチ兼仕事マネージャーです。
          以下のタスクを、取り組むべき大きな方針（3〜5個のスモールステップ）に分解してください。

          タスク名: #{@task.name}
          タスクの概要・詳細: #{task_desc_str}
          締め切り: #{due_date_str}
          今日の日付: #{today_str}

          【指示事項】
          ・「毎日やる」ような継続タスクの場合は、ステップ名に「【毎日】」と付けてください。
          ・アクティブリコールやファインマン・テクニックなどの効果的な学習法を盛り込んでください。
          ・タスクが思考を要する場合、例えば数学の問題を解き進める、などの時は朝や午前中に、
          　タスクが「覚える」という類の場合は、例えば英単語を覚える、などは、昼食・夜食・就寝の前に
          　やったほうがいい、という趣旨を説明に加えてください。
          ・3〜5個の分かりやすいステップを提案してください。

          【出力フォーマット】
          ### ステップ1: 【毎日】1〜25語のアクティブリコール
          **期限:** 2026年09月10日
          毎日25語ずつ進め、前日分を何も見ずに思い出すテストを行う。

          ### ステップ2: ファインマン・テクニックで弱点補強
          **期限:** 2026年09月20日
          苦手な概念を自分の言葉で平易に説明する。
        PROMPT
      }]
    }
  ]

  @result = ask_ai(messages)

  AiDecomposeLog.create(
    task_id: @task.id,
    user_id: current_user.id,
    result: @result.to_s
  )

  @logs = AiDecomposeLog.where(task_id: @task.id).order(created_at: :desc)

  erb :ai_decompose
end
# ============================================
# AI分解の過去ログを表示するルート
# 特定タスクの過去の分解ログをすべて取得して表示する
# ============================================
get '/ai/decompose/:task_id/logs' do
  require_login
  @task = current_user.tasks.find_by(id: params[:task_id])
  redirect '/mypage' unless @task

  # 過去のログを新しい順に取得する
  @logs = AiDecomposeLog.where(task_id: @task.id).order(created_at: :desc)

  erb :ai_decompose_logs
end

# ============================================
# AI 分解画面から「採用」ボタンで新規タスクを登録するルート
# スモールステップのテキストと、分解元のタスクIDを受け取って子タスクとして保存する
# ============================================
# ============================================
# AI 分割画面から「採用」ボタンで子タスクを登録するルート（JSON API）
# ページ遷移なしで裏で保存する。採用後も AI 分割画面に留まる
# ============================================
# ============================================
# AI 分割画面から「採用」ボタンで子タスクを登録するルート（JSON API）
# 直前のステップの期限日の「翌日」を開始日にして順次タスクを展開する
# ============================================
post '/tasks/from_step' do
  require_login
  content_type :json

  step_name      = params[:step_name].to_s.strip
  step_desc      = params[:step_description].to_s.strip
  parent_task_id = params[:parent_task_id].to_s.strip
  due_date_str   = params[:due_date].to_s.strip

  if step_name.empty?
    halt 400, { error: 'step_name is required' }.to_json
  end

  parent_task = parent_task_id.empty? ? nil : current_user.tasks.find_by(id: parent_task_id)

  due_date = nil
  unless due_date_str.empty?
    begin
      due_date = Date.parse(due_date_str)
    rescue ArgumentError
      due_date = nil
    end
  end
  due_date ||= parent_task&.due_date

  # ----------------------------------------------------
  # 開始日の自動計算（既存ステップの「最も遅い期限日 + 1日」から開始）
  # ----------------------------------------------------
  start_date = Date.today

  if parent_task
    # 親タスク直下にある既存のステップ（子タスク）の最大期限日を取得
    latest_due = parent_task.child_tasks.where.not(due_date: nil).maximum(:due_date)

    # すでにステップが存在し、その期限が今日以降なら「翌日」を開始日にする
    if latest_due && latest_due >= Date.today
      start_date = latest_due + 1
    end
  end

  # 1. 親ステップのタスクを作成
  task = current_user.tasks.create(
    name: step_name,
    description: step_desc.empty? ? nil : step_desc,
    parent_task_id: parent_task ? parent_task.id : nil,
    due_date: due_date,
    color: parent_task ? parent_task.color : 'sky'
  )

  # 2. 「毎日」が含まれる場合、開始日〜期限日までの毎日のタスクを自動展開
  is_daily = step_name.include?('毎日') || step_desc.include?('毎日')
  if is_daily && due_date && due_date >= start_date
    end_date = [due_date, start_date + 60].min

    (start_date..end_date).each do |date|
      current_user.tasks.create(
        name: "#{step_name.gsub('【毎日】', '').strip} (#{date.strftime('%m/%d')})",
        description: step_desc.empty? ? nil : step_desc,
        parent_task_id: task.id,
        due_date: date,
        color: task.color
      )
    end
  end

  { id: task.id, name: task.name }.to_json
end

# ============================================
# タイマー完了後に AI の励ましメッセージを取得するルート
# JavaScript からフェッチされて JSON を返す
# ============================================
get '/ranking' do
  require_login
  @user = current_user
  # ランキング参加者：1000pt 以上かつ show_in_ranking が true のユーザーのみ
  @ranking = User.where(show_in_ranking: true).where('points >= ?', 1000).order(points: :desc).limit(10)
  erb :ranking
end

# ============================================
# ランキング参加/非参加を切り替えるルート
# ============================================
post '/ranking/toggle' do
  require_login
  user = current_user
  # 1000pt 未満は参加不可
  if user.points >= 1000
    user.update(show_in_ranking: !user.show_in_ranking)
  end
  redirect '/ranking'
end

# ============================================
# 1000pt 達成バナーを「見た」としてフラグを立てるルート
# JavaScript から呼ばれる（ページ遷移なし）
# ============================================
post '/leaderboard/notified' do
  require_login
  current_user.update(leaderboard_notified: true)
  content_type :json
  { ok: true }.to_json
end

post '/ai/encourage' do
  require_login
  # ログインユーザーのタスクのみ操作できるようにする
  task = current_user.tasks.find_by(id: params[:task_id])

  # タスク名と集中時間を取得する（パラメータがなければデフォルト値を使う）
  task_name = task ? task.name : 'タスク'
  duration  = params[:duration_minutes].to_i

  # AI に渡すプロンプトを組み立てる
  messages = [
    {
      role: 'user',
      content: [{
        text: <<~PROMPT
          あなたはやさしい勉強・仕事の伴走コーチです。
          ユーザーが集中タイマーを完走しました。一言、元気が出る励ましのメッセージを送ってください。

          完了したタスク: #{task_name}
          集中した時間: #{duration}分

          短め（2〜3文）でポジティブに、具体的なタスク名に触れながら褒めてください。
        PROMPT
      }]
    }
  ]

  # AI Gateway に問い合わせて励ましメッセージを取得する
  message = ask_ai(messages) || '集中タイマー完走おめでとう！よく頑張ったね！'

  # JSON 形式で返す（JavaScript がフェッチして画面に表示する）
  content_type :json
  { message: message }.to_json
end

# ============================================
# ゆるキャラAIリマインダー（動画終了時の声かけメッセージ生成）
# ============================================
post '/ai/yuru_reminder' do
  require_login
  duration = params[:duration_minutes].to_i

  messages = [
    {
      role: 'user',
      content: [{
        text: <<~PROMPT
          あなたはやさしくて語尾が「〜」「だよ〜」な、かわいくてゆるいマスコットキャラクター（ゆるキャラ）です。
          ユーザーが「動画（YouTubeなど）を#{duration}分見る」という約束の時間を終えました。
          動画で楽しくリフレッシュできたことを優しくねぎらいつつ、
          「そろそろ今日の勉強のノートを開いてみない〜？応援してるよ〜！」と、机に向かうきっかけを優しく促すメッセージを提示してください。
          
          条件:
          - 親しみやすく優しく声をかけること
          - 長さは60文字程度の短く読みやすい文章にすること
          - 説教くさくならず、癒されるトーンにすること
        PROMPT
      }]
    }
  ]

  ai_text = ask_ai(messages)
  content_type :json
  { message: ai_text }.to_json
end



# ============================================
# 過去7日間の学習時間を取得するJSON API
# ============================================
get '/api/stats' do
  require_login
  content_type :json

  # 過去7日分の日付配列を作成 (例: ["08/22", "08/23", ...])
  past_7_days = (6.days.ago.to_date..Date.today).to_a

  # ログインユーザーの過去7日間のセッションを取得して日付ごとに集計
  sessions = current_user.focus_sessions
    .where(focused_at: past_7_days.first..past_7_days.last)
    .group(:focused_at)
    .sum(:duration_minutes)

  labels = past_7_days.map { |d| d.strftime('%m/%d') }
  data = past_7_days.map { |d| sessions[d] || 0 }

  { labels: labels, data: data }.to_json
end


post '/ai/schedule' do
  require_login
  content_type :json
  available_hours = params[:available_hours].to_f

  # 本日の未完了タスクを取得
  today_tasks = current_user.tasks.where(completed: false)
  task_list = today_tasks.map { |t| "- #{t.name} (説明: #{t.description})" }.join("\n")

  prompt = <<~TEXT
    ユーザーの今日使える学習時間は #{available_hours} 時間です。
    以下のタスクリストから、時間内に収まる最適な優先順位と時間配分スケジュール（分単位）を作成してください。

    【本日のタスク】
    #{task_list.empty? ? '（タスクはありません。復習や自由学習を提案してください）' : task_list}
  TEXT

  messages = [
    {
      role: 'user',
      content: [{ text: prompt }]
    }
  ]

  ai_response = ask_ai(messages)

  { schedule: ai_response }.to_json
end