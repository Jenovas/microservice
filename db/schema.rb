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

ActiveRecord::Schema[8.0].define(version: 2024_03_20_000002) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "campaigns", force: :cascade do |t|
    t.string "campaign_guid", null: false
    t.string "token", null: false
    t.string "device_type", null: false
    t.jsonb "credentials", default: {}, null: false
    t.string "campaign_type", null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "processed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_guid", "token"], name: "index_campaigns_on_campaign_guid_and_token", unique: true
    t.index ["campaign_guid"], name: "index_campaigns_on_campaign_guid"
    t.check_constraint "campaign_type::text = ANY (ARRAY['push'::character varying, 'in_app'::character varying, 'feed'::character varying]::text[])", name: "valid_campaign_type"
    t.check_constraint "device_type::text = ANY (ARRAY['android'::character varying, 'ios'::character varying]::text[])", name: "valid_device_type"
  end

  create_table "push_results", force: :cascade do |t|
    t.string "campaign_guid", null: false
    t.string "user_token", null: false
    t.string "platform", null: false
    t.boolean "was_success", default: false, null: false
    t.string "error"
    t.datetime "processed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_guid", "user_token"], name: "index_push_results_on_campaign_guid_and_user_token", unique: true
    t.index ["campaign_guid"], name: "index_push_results_on_campaign_guid"
    t.index ["processed_at"], name: "index_push_results_on_processed_at"
    t.index ["user_token"], name: "index_push_results_on_user_token"
  end
end
