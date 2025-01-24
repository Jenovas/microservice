class CreateCampaigns < ActiveRecord::Migration[8.0]
  def change
    create_table :campaigns do |t|
      t.string :campaign_guid, null: false
      t.string :token, null: false
      t.string :device_type, null: false
      t.jsonb :credentials, default: {}, null: false
      t.string :campaign_type, null: false
      t.jsonb :payload, default: {}, null: false
      t.datetime :processed_at
      t.timestamps
    end

    add_index :campaigns, :campaign_guid  # Non-unique index for faster lookups
    add_index :campaigns, [ :campaign_guid, :token ], unique: true  # Ensure same token doesn't get same campaign twice
    add_check_constraint :campaigns, "device_type IN ('android', 'ios')", name: 'valid_device_type'
    add_check_constraint :campaigns, "campaign_type IN ('push', 'in_app', 'feed')", name: 'valid_campaign_type'
  end
end
