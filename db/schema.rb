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

ActiveRecord::Schema[8.0].define(version: 2026_11_24_000001) do
  create_table "alerts", force: :cascade do |t|
    t.string "incident_key", null: false
    t.string "check_name", null: false
    t.string "severity", null: false
    t.string "partner_id"
    t.integer "affected_count", null: false
    t.json "sample_ids"
    t.string "detail"
    t.datetime "detected_at", null: false
    t.datetime "last_new_at", null: false
    t.datetime "resolved_at"
  end

  create_table "billing_lines", primary_key: "line_id", id: :string, force: :cascade do |t|
    t.string "partner_id", null: false
    t.string "direction", null: false
    t.string "unit_type", null: false
    t.integer "units", null: false
    t.decimal "unit_price", null: false
    t.decimal "amount", null: false
    t.date "period_start", null: false
    t.date "period_end", null: false
  end

  create_table "calls", primary_key: "call_id", id: :string, force: :cascade do |t|
    t.string "publisher_id", null: false
    t.string "buyer_id", null: false
    t.datetime "started_at", null: false
    t.string "caller_state"
    t.string "state_tag"
    t.boolean "connected", null: false
    t.integer "duration_sec", null: false
    t.index ["started_at"], name: "index_calls_on_started_at"
  end

  create_table "events", primary_key: "event_id", id: :string, force: :cascade do |t|
    t.string "lead_id", null: false
    t.string "stage", null: false
    t.string "partner_id", null: false
    t.datetime "occurred_at", null: false
    t.string "status"
    t.index ["lead_id", "stage"], name: "index_events_on_lead_id_and_stage"
    t.index ["stage", "occurred_at"], name: "index_events_on_stage_and_occurred_at"
  end

  create_table "leads", primary_key: "lead_id", id: :string, force: :cascade do |t|
    t.string "publisher_id", null: false
    t.datetime "received_at", null: false
    t.string "state"
    t.string "phone_hash"
    t.string "consent_cert_id"
    t.boolean "accepted", null: false
    t.string "reject_reason"
    t.index ["publisher_id", "received_at"], name: "index_leads_on_publisher_id_and_received_at"
    t.index ["received_at"], name: "index_leads_on_received_at"
  end

  create_table "partners", primary_key: "partner_id", id: :string, force: :cascade do |t|
    t.string "name", null: false
    t.string "partner_type", null: false
  end
end
