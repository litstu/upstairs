# Quickstart: FeelTheRoof

## 動作確認の手順

1. `bundle install` で gem を入れる
2. `bundle exec rake db:create db:migrate db:seed` でDBを準備
3. `ruby app.rb` でサーバー起動
4. Cloud9の「Preview → Preview Running Application」で確認
5. プレビュー右上のポップアウトボタンで別タブで開く

## MVP チェックポイント

- [ ] トップページが表示される
- [ ] 新規登録→ログインができる
- [ ] タスクを登録するとマイページ一覧に表示される
- [ ] タイマー画面でBongoCat風キャラクターが表示される
- [ ] タイマー完了後にカレンダーへ記録される
- [ ] カレンダーで達成マークが確認できる
