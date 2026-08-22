class AddLeaderboardFieldsToUsers < ActiveRecord::Migration[7.2]
  def change
    # ランキングに表示するかどうかのフラグ（デフォルト false = 非表示）
    # すでに列がある場合はスキップする（何度実行してもエラーにならないようにする）
    add_column :users, :show_in_ranking, :boolean, default: false, null: false, if_not_exists: true
    # 1000pt 達成バナーを一度表示済みかどうかのフラグ
    add_column :users, :leaderboard_notified, :boolean, default: false, null: false, if_not_exists: true
  end
end
