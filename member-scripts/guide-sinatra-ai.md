# Sinatra アプリから AI Gateway を使う

Sinatra（Ruby）のアプリから AI Gateway 経由で Claude を呼ぶ方法。

## 1. 接続情報は自動でセット済み（`.env` は基本いらない）

AI につなぐための **URL とアクセスキーは、セットアップスクリプト（`source .../lit-webs-ai.sh`）が
このパソコンの全ターミナルに自動でセット済み**。だからサービス側で URL やキーを書く必要はないよ。

- 別のターミナルを開いても、**同じ環境（同じパソコン）なら接続情報は自動で読み込まれる**
  （`ANTHROPIC_BASE_URL` / `ANTHROPIC_AUTH_TOKEN` という名前で入ってる）。
- **サービス用のモデル名（Haiku）も、セットアップで入れた値が `AI_GATEWAY_MODEL` として自動でセット済み**
  なので、ふつうは何も書かなくて OK。
- もしまだセットアップしてなかったら、先に `source <配布パス>/lit-webs-ai.sh` を 1 回やってね。

> 💡 サービスのモデルをあえて別のものに変えたい人だけ、プロジェクトのルートに `.env` を作って
> `AI_GATEWAY_MODEL=...` を書けば上書きできる（任意）。その場合は `.env` を `.gitignore` に追加してね。

## 2. 必要な gem を入れる（多くの場合は自動で済んでる）

このプロジェクトの `Gemfile` に次があれば OK:

```ruby
gem 'dotenv'   # .env でモデルを変えたい人向け（無くても動くけど、入れておくと安心）
gem 'faraday'
```

> ✨ セットアップスクリプト（`source .../lit-webs-ai.sh`）を実行済みなら、**`bundle install` は自動で
> 走ってる**（プロジェクト直下に `Gemfile` がある場合）。だから普通はこの手順を自分でやる必要はないよ。

自動インストールに失敗した／`Gemfile` を後から書き換えたときだけ、手動で:

```bash
bundle install
```

## 3. AI を呼ぶコードを書く

```ruby
require 'dotenv/load'
require 'faraday'
require 'json'

# AI Gateway に質問を送って回答をもらう
def ask_ai(question)
  # 接続先とキーは、セットアップスクリプトが用意した環境変数をそのまま使う。
  # （.env に AI_GATEWAY_URL / AI_GATEWAY_KEY を書いていれば、そちらが優先される）
  url = ENV['AI_GATEWAY_URL'] || ENV['ANTHROPIC_BASE_URL']
  key = ENV['AI_GATEWAY_KEY'] || ENV['ANTHROPIC_AUTH_TOKEN']
  # サービスで使うモデルは軽くて速い Haiku を既定にする（変えたい人は .env で AI_GATEWAY_MODEL を指定）。
  model = ENV['AI_GATEWAY_MODEL'] || 'global.anthropic.claude-haiku-4-5-20251001-v1:0'

  # 接続情報が見つからないとき（セットアップ前など）は、わかりやすく知らせる。
  if url.nil? || key.nil?
    return 'AI の接続情報が見つからないよ。セットアップした環境と同じパソコンで動かしてるか確認してね（まだなら lit-webs-ai.sh を 1 回 source してね）'
  end

  conn = Faraday.new do |f|
    f.request :json
    f.response :json
    f.adapter Faraday.default_adapter
  end

  # URL は末尾スラッシュを正規化し、フル URL を指定する（/prod を取りこぼさないため）。
  endpoint = "#{url.chomp('/')}/v1/chat/completions"
  response = conn.post(endpoint) do |req|
    req.headers['Authorization'] = "Bearer #{key}"
    req.body = {
      model: model,
      messages: [
        { role: 'user', content: [{ text: question }] }
      ],
      inferenceConfig: { maxTokens: 1024 }
    }
  end

  if response.status == 200
    data = response.body
    # Converse API 形式のレスポンス
    data.dig('output', 'message', 'content', 0, 'text')
  else
    "エラーが発生しました（#{response.status}）"
  end
end
```

## 4. Sinatra のルートから使う

```ruby
require 'sinatra'

get '/' do
  erb :index
end

post '/ask' do
  question = params[:question]
  @answer = ask_ai(question)
  erb :answer
end
```

## API のポイント

| 項目 | 値 |
|---|---|
| エンドポイント | `POST /v1/chat/completions` |
| 認証 | `Authorization: Bearer sk-aipf-...` |
| モデル | `global.anthropic.claude-haiku-4-5-20251001-v1:0` |
| 形式 | Amazon Bedrock Converse API 形式 |

## レスポンス例

```json
{
  "output": {
    "message": {
      "role": "assistant",
      "content": [{ "text": "こんにちは！何かお手伝いできることはありますか？" }]
    }
  },
  "stopReason": "end_turn",
  "usage": {
    "inputTokens": 8,
    "outputTokens": 15,
    "totalTokens": 23
  }
}
```

## 困ったとき

- **「AI の接続情報が見つからない」と出る** → セットアップしたのと同じパソコンで動かしてるか確認。まだなら `source <配布パス>/lit-webs-ai.sh` を 1 回実行してね
- **401 エラー** → アクセスキーが間違っている or 失効している（もう一度 `source ...` でログインし直す）
- **403 エラー** → そのモデルが許可されていない（メンターに確認）
- **接続できない** → セットアップ済みのターミナルか確認（`echo $ANTHROPIC_BASE_URL` で空じゃないか見てみる）
