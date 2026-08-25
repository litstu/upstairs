require 'bundler/setup'
# 本番環境では開発用Gemを固定しないよう読み込み
Bundler.require(:default, ENV['RACK_ENV'] || :development)

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

# ログインしているかどうかを確認するメソッド
def logged_in?
  !session[:user_id].nil?
end

# ログイン中のユーザーを取得するメソッド
def current_user
  @current_user ||= User.find_by(id: session[:user_id])
end

# ログインしていない場合はトップページへリダイレクトするメソッド
def require_login
  redirect '/' unless logged_in?
end

# ============================================
# AI Gateway に質問を送って回答をもらう関数（最初から用意されている道具）
# AI に問い合わせるサービスを作るときに使う。
# messages に質問を渡すと、AI の回答テキストを返してくれる。
# 接続先・アクセスキー・モデルは、セットアップ時に用意された環境変数を自動で使うので、
# .env に鍵を書く必要はない（鍵をプロジェクトに残さない＝流出防止）。
# ============================================
def ask_ai(messages)
  key = ENV['GEMINI_API_KEY']
  return 'GEMINI_API_KEYが設定されていません（.envを確認してください）' if key.nil? || key.strip.empty?

  # messages からプロンプトテキストを抽出
  prompt_text = ''
  messages.each do |msg|
    contents = msg[:content] || msg['content'] || []
    if contents.is_a?(Array)
      contents.each do |c|
        prompt_text += (c[:text] || c['text'] || '') + "\n"
      end
    elsif contents.is_a?(String)
      prompt_text += contents + "\n"
    end
  end

  # Faraday 通信の設定
  conn = Faraday.new(url: 'https://generativelanguage.googleapis.com') do |f|
    f.request :json
    f.response :json
    f.adapter Faraday.default_adapter
  end

  # 利用可能一覧にあった gemini-3.5-flash を指定
  response = conn.post("/v1beta/models/gemini-3.5-flash:generateContent?key=#{key.strip}") do |req|
    req.headers['Content-Type'] = 'application/json'
    req.options.timeout = 60
    req.body = {
      contents: [
        {
          parts: [{ text: prompt_text }]
        }
      ]
    }
  end

  # 通信成功時は回答文を取得
  if response.status == 200
    data = response.body
    data.dig('candidates', 0, 'content', 'parts', 0, 'text')
  else
    # 失敗時はステータスコードとGoogleからの詳細メッセージを表示
    error_msg = response.body.is_a?(Hash) ? response.body.dig('error', 'message') : response.body
    "AI通信エラー（ステータスコード: #{response.status}）: #{error_msg}"
  end
rescue => e
  "エラーが発生しました: #{e.message}"
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
  current_user.tasks.create(
    name: params[:name],
    description: params[:description].to_s.empty? ? nil : params[:description],
    due_date: params[:due_date].to_s.empty? ? nil : params[:due_date],
    color: Task::COLORS.include?(params[:color].to_s) ? params[:color] : 'sky'
  )
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
          あなたは脳科学と学習心理学に詳しい学習伴走コーチです。
          以下のタスクを、取り組むべき大きな方針（3〜5個のスモールステップ）に分解してください。

          タスク名: #{@task.name}
          タスクの概要・詳細: #{task_desc_str}
          締め切り: #{due_date_str}
          今日の日付: #{today_str}

          【指示事項】
          ・「毎日やる」ような継続タスクの場合は、ステップ名に「【毎日】」と付けてください。
          ・アクティブリコールやファインマン・テクニックなどの効果的な学習法を盛り込んでください。
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
