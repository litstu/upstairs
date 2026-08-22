# コーディングルール

1. **余計なことをしない。** テスト、エラーハンドリング、バリデーションなどは書かない。
2. **コードは綺麗に書く。** インデントをそろえ、読みやすく。
3. **コメントを丁寧に書く。** 初心者が読んでもわかるように、日本語で「何をしているか」を細かい単位で説明する。
4. **1 つのルート（get/post）に 1 つの役割** を守る。
5. **変数名やルート名は英語でシンプルに。** ただしコメントで日本語の説明を必ずつける。

## コード内コメントの書き方（例）

```ruby
# ============================================
# トップページを表示するルート
# ブラウザで「/」にアクセスしたときに動く
# ============================================
get '/' do
  # データベースから全ての投稿を取得する
  # order で新しい順に並べている
  @posts = Post.order(created_at: :desc)

  # index.erb という画面テンプレートを表示する
  erb :index
end
```

## やってはいけないこと

- ~~テストコードを書く~~ → **下記「スモークテスト」の項を参照**（条件付きで OK に変更）
- エラーハンドリングを実装する
- 認証/ログイン機能を作る（`bcrypt` は Gemfile にあるが、初心者には複雑すぎる場合はスキップ）
- 複雑なバリデーションを入れる
- JavaScript フレームワーク（React、Vue など）を使う
- 外部 API を使う（ルール改定あり。詳細は [`tech-stack.md`](tech-stack.md) の「外部 API のルール」参照）
- 画像保存に外部サービスを使う（**ローカル保存 `public/uploads/` が基本**。詳細は [`tech-stack.md`](tech-stack.md) の「画像保存」参照）
- **生成物（spec.md / plan.md / tasks.md / views/ などのファイル中身）に絵文字を入れる**（理由は下記）

## 🧪 スモークテスト（中高生には見せない）

**テストコードは「中高生の邪魔にならない形」で書いてよい。** 目的は build / feedback 後にサービスが壊れていないことを自動確認すること。

### ルール

- テストファイルは **`test/`** ディレクトリに置く
- テストの存在をメンバーに説明しない・見せない・触らせない
- テスト対象は **「サーバーが起動するか」「主要ルートが 200 を返すか」** レベルのスモークテスト
- ユニットテスト・結合テストは書かない
- テストが落ちたらクロード / dev-agent が裏で直す。メンバーに「テスト落ちたよ」とは言わない
- テストフレームワークは `rack-test`（**Gemfile に最初から入っている**ので追加不要）
- **`/speckit-build` では完了前にこのスモークテストを必ず用意して実行する**（無ければ dev-agent が作る）。整合性チェックとスモークテストの両方がパスしてから「完了」とメンバーに伝える

### テストファイルの例

```ruby
# test/smoke_test.rb
ENV['RACK_ENV'] = 'test'
require_relative '../app'
require 'rack/test'

class SmokeTest
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def run_all
    test_top_page
    test_main_routes
    test_main_flow
    test_ai_connection
    puts "All smoke tests passed!"
  end

  def test_top_page
    get '/'
    raise "GET / failed: #{last_response.status}" unless last_response.ok?
  end

  def test_main_routes
    # app.rb の GET ルートを、できるだけ網羅的に叩く（「主要だけ」で済ませない）
    # 動的な :id 付きは seeds.rb に実在する id を使う
    # 例: get '/'; get '/posts'; get '/posts/1'; get '/search?q=test'
  end

  # メンバーが最初にエラーに当たりやすいフォーム送信（POST）を、できるだけ全部通しで確認する。
  # 各フロー（作成・更新・削除・いいね等）に妥当な値を入れて送信 → リダイレクトを追って 200 まで見る。
  def test_main_flow
    # 例（実際のルート/パラメータはアプリに合わせる。POST は全部確認する）:
    # post '/posts', title: 'テスト投稿', body: '本文テスト'
    # follow_redirect! if last_response.redirect?
    # raise "create failed: #{last_response.status}" unless last_response.ok?
    #
    # post '/posts/1/like'
    # follow_redirect! if last_response.redirect?
    # raise "like failed: #{last_response.status}" unless last_response.ok?
    #
    # post '/posts/1/delete'
    # follow_redirect! if last_response.redirect?
    # raise "delete failed: #{last_response.status}" unless last_response.ok?
  end

  # AI を使うサービスのときだけ、実際に AI Gateway と通信できるか確認する。
  # ask_ai が無い（AI を使わない）か、鍵がどこにも無い（セットアップ未実施）なら何もしない。
  # SMOKE_SKIP_AI=1 のときも実通信をスキップする（見た目だけの修正でトークンを使わないため）。
  def test_ai_connection
    return if ENV['SMOKE_SKIP_AI'] == '1'
    return unless defined?(ask_ai)
    # 鍵が無い（セットアップ未実施）ときだけスキップする。
    return if ENV['ANTHROPIC_AUTH_TOKEN'].to_s.empty?
    res = ask_ai([{ role: 'user', content: [{ text: 'テスト。「ok」とだけ返して。' }] }])
    if res.nil? || res.to_s.strip.empty? || res.include?('エラーが発生しました')
      raise "AI connection failed: #{res}"
    end
  end
end

SmokeTest.new.run_all if __FILE__ == $0
```

### いつ実行するか

- `/speckit-build` の全タスク完了後、サーバー起動前
- `/speckit-feedback` でバグ修正・機能追加した後
- バイブコーディングで変更を加えた後

## 📦 Seed Data のルール

**データベースを使うプロジェクトでは、`db/seeds.rb` に十分なダミーデータを必ず入れる。**

### 量の目安

| サービスの種類 | 最低データ件数 | 理由 |
|---|---|---|
| CRUD 系（投稿・日記・メモ） | 10〜20 件 | 画面に「ある程度」データが並んでる状態にする |
| 情報サイト・検索系（グルメ検索、ランキング、図鑑） | **50〜100 件** | 検索・絞り込み・ページネーションが意味を持つ量 |
| マスタデータあり（カテゴリ、タグ、エリア） | マスタ: 全件 / コンテンツ: 50 件以上 | 絞り込みの選択肢が全部揃っている状態 |

### データの質

- **テーマに合ったリアルなデータ** にする（「テスト1」「テスト2」は NG）
- 例: 球場グルメ検索なら、実在の球場名＋架空のメニュー名＋価格＋カテゴリ
- 例: 推し活サイトなら、架空のグループ名＋メンバー名＋イベント名
- 画像パスが必要な場合は `/img/placeholder.png` などプレースホルダで OK
- **日本語で書く**（中高生が見て「おー、ちゃんとデータ入ってる！」と思える内容）

#### 🚨 実在が主役のサービスは「識別情報」を架空にしない（ダミーデータ事故の最頻出パターン）

**実在の特定の対象（実在の人・チーム・作品・イベント・店・場所）を主役にするサービスでは、その対象の“識別情報”を架空データで埋めてはいけない。** 実在の代表チームの予想サイトなのに選手名が架空、実在イベントの案内なのに日程が架空、はプロダクトとして「嘘」になり、機能が完璧でも一発で台無しになる。

- **実在が主役なら → 名前・日付・対戦相手・イベント名などの識別情報は実在のものを seed に入れる。** 架空にしてよいのは「特徴文」「紹介コメント」など、事実でなくても成立する“飾り”のフィールドだけ
- **架空でよいのは、対象そのものが架空・創作のとき**（オリジナル世界観、創作キャラ、サンプルカタログ）
- **実在の“今の事実”（正確さが命の営業時間・時刻表・在庫・混雑）は seed で捏造しない**（`spec-workflow.md` の危険ファミリー E / A の通り立て直す）

> 実在が主役かどうかは要件定義の「実在 or 架空」ゲート（`spec-workflow.md` ステップ 1）で決まっているはず。spec / plan にその判断が書かれているので、seed 生成時は必ずそれに従う。書かれていなければ実在寄りに倒して確認する。

### seed で“作っていい”データ／“作っちゃダメ”なデータ（重要）

- ✅ **静的カタログ**（紹介・図鑑・まとめ系の、現実が刻々変わらない情報）は、テーマに合った架空データを量産して OK（例：球場グルメ紹介の店名＋架空メニュー＋価格）。
- ❌ **今の現実の状態**（混雑度・在庫・待ち時間・現在地・リアルタイム価格など）を seed で固定値として捏造しない。それは「動くフリ」になる。こういうデータは **ユーザーが投稿する形** か **AI の“予想”と明示** に変える。
- ❌ **正確さが命の実データ**（実在店の本当の営業時間・正確な時刻表など）を、それっぽく捏造して“事実”として出さない。サンプルなら「サンプル」と明示する。
- そもそもこういうアイデアは **要件定義の段階で立て直す**のが正解。判断基準と立て直し方は `spec-workflow.md` の「そのアイデア、本当に作れる？」を参照。

### seeds.rb の書き方

```ruby
# db/seeds.rb
# ============================================
# ダミーデータの投入
# `bundle exec rake db:seed` で実行される
# ============================================

# 既存データを削除してから入れ直す（何度実行しても同じ状態になる）
Post.destroy_all

posts_data = [
  { title: "甲子園カレー", stadium: "阪神甲子園球場", price: 800, category: "カレー" },
  { title: "ドームドッグ", stadium: "東京ドーム", price: 600, category: "ホットドッグ" },
  # ... 50件以上
]

posts_data.each { |data| Post.create!(data) }
puts "#{Post.count} 件のデータを投入しました"
```

### tasks.md での扱い

speckit-tasks がタスクリストを生成するとき、**必ず seed data 生成のタスクを含める**。情報サイト系（Read がメイン機能）の場合は特に強調する。

## 🚫 絵文字ルール（重要）

### 生成物（コード・spec ドキュメント・views）には絵文字を使わない

下記のファイルに絵文字（😊🎉🍵🌸 など）を**書き込まない**：

- `views/*.erb` の HTML 中身
- `app.rb`, `models.rb` のコード/コメント
- `spec.md`, `plan.md`, `tasks.md`, `data-model.md` などの仕様書
- `db/schema.rb`, `db/seeds.rb`

理由：絵文字は **明らかに「生成 AI で作った感」が出る** から。プロのサービスは絵文字に頼らず、文字組とレイアウトとアイコンで魅せる。代わりに **Phosphor Icons**（`<i class="ph ph-heart"></i>` など）を使う。

### ただし会話の中では絵文字 OK

メンバーとのチャット会話、`persona.md` / `spec-workflow.md` / SKILL.md のクロード自身の声かけテンプレでは絵文字を使ってよい。**生成物（メンバーのサービス側に出るもの）と、会話（クロードの中の人キャラ）は別物として扱う。**

具体例（サービス名は一例）：
- ✅ 会話: 「やっほー！動かしてみてどうだった〜？😊」
- ❌ views/index.erb: `<h1>ひみつ日記 📔✨</h1>` ← これは禁止
- ✅ views/index.erb: `<h1 class="text-3xl font-bold flex items-center gap-2"><i class="ph-fill ph-pencil"></i> ひみつ日記</h1>`

## デザインに関するガイド

> **このセクションは「クラスの使い方（how）」担当。** 「何が良い見た目か（方向性の判断）」は `.claude/skills/web-design/SKILL.md` が担当する。**ビューを実装するときは必ず `plan.md` の「デザイン仕様（固定）」に従い**、迷ったら web-design スキルを Read すること。DaisyUI のデフォルト `light` のまま・中央寄せ一辺倒・多色づかいは「AI が作った感」の原因なので避ける。

### 基本：Tailwind CSS + DaisyUI のクラスを使う

`views/layout.erb` で **Tailwind CSS（CDN 版）と DaisyUI（CDN 版）を読み込み済み**。各 erb ファイルでは Tailwind / DaisyUI の class を使ってスタイリングする。

例：

```erb
<%# 投稿カード %>
<article class="card bg-base-100 shadow-md mb-4">
  <div class="card-body">
    <h2 class="card-title text-pink-600">
      <i class="ph-fill ph-heart"></i>
      <%= @post.title %>
    </h2>
    <p class="text-gray-700"><%= @post.body %></p>
    <div class="card-actions justify-end">
      <button class="btn btn-primary btn-sm">いいね</button>
    </div>
  </div>
</article>
```

### Tailwind の主要なクラス（よく使うやつ）

| やりたいこと | class 例 |
|---|---|
| 色 | `bg-pink-100`, `text-blue-600`, `border-gray-300` |
| 余白 | `p-4`（内側）, `m-2`（外側）, `gap-4`（要素間） |
| 配置 | `flex`, `items-center`, `justify-between` |
| 文字 | `text-2xl`, `font-bold`, `text-center` |
| サイズ | `w-full`, `max-w-md`, `h-32` |
| 角丸・影 | `rounded-lg`, `shadow-md`, `shadow-lg` |
| ホバー | `hover:bg-pink-200`, `hover:scale-105`, `transition` |

### DaisyUI の主要コンポーネント

| 用途 | class |
|---|---|
| ボタン | `btn`, `btn-primary`, `btn-ghost`, `btn-sm/lg` |
| カード | `card`, `card-body`, `card-title`, `card-actions` |
| 入力欄 | `input`, `input-bordered`, `textarea`, `select` |
| バッジ・タグ | `badge`, `badge-primary`, `badge-outline` |
| ナビ | `navbar`, `menu` |
| アラート | `alert`, `alert-success`, `alert-info` |

### Phosphor Icons の使い方

```erb
<%# 線画版 %>
<i class="ph ph-heart"></i>

<%# 塗りつぶし版 %>
<i class="ph-fill ph-heart"></i>

<%# サイズはCSSで（Tailwind の text-3xl などで） %>
<i class="ph-fill ph-heart text-3xl text-pink-500"></i>
```

利用可能なアイコンは https://phosphoricons.com で検索。

### CSS フレームワークを差し替える場合

サービスのテーマに対して Tailwind+DaisyUI が合わないとクロードが判断したら（レトロゲーム系、Win98 風など）、`views/layout.erb` の CDN を切り替える。詳細は `.claude/tech-stack.md` を参照。

### style.css の使い分け

- **基本**：`views/*.erb` に Tailwind クラスを直書き
- **`public/css/style.css`** は Tailwind / DaisyUI で表現できないとき（独自アニメーション、特殊な疑似要素など）にだけ使う。あまり書かなくて済むはず

### その他

- レスポンシブ対応は必須ではない（できたらすごい！と褒める）
- 色使いやレイアウトはメンバーの好みを尊重する
