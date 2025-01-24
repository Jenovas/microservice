class CreatePushResults < ActiveRecord::Migration[8.0]
  def change
    create_table :push_results do |t|
      t.string :campaign_guid, null: false
      t.string :user_token, null: false
      t.string :platform, null: false
      t.boolean :was_success, null: false, default: false
      t.string :error
      t.datetime :processed_at, null: false

      t.timestamps
    end

    add_index :push_results, [:campaign_guid, :user_token], unique: true
    add_index :push_results, :campaign_guid
    add_index :push_results, :user_token
    add_index :push_results, :processed_at
  end
end 