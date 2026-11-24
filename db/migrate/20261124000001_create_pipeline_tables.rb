# All timestamps are US Eastern wall-clock, stored as-is (Rails treats them as UTC; no DST change in the data week).
class CreatePipelineTables < ActiveRecord::Migration[8.0]
  def change
    create_table :partners, id: false do |t|
      t.string :partner_id, primary_key: true
      t.string :name, null: false
      t.string :partner_type, null: false
    end

    create_table :leads, id: false do |t|
      t.string :lead_id, primary_key: true
      t.string :publisher_id, null: false
      t.datetime :received_at, null: false
      t.string :state
      t.string :phone_hash
      t.string :consent_cert_id
      t.boolean :accepted, null: false
      t.string :reject_reason
      t.index [:publisher_id, :received_at]
      t.index :received_at
    end

    create_table :events, id: false do |t|
      t.string :event_id, primary_key: true
      t.string :lead_id, null: false
      t.string :stage, null: false
      t.string :partner_id, null: false
      t.datetime :occurred_at, null: false
      t.string :status
      t.index [:lead_id, :stage]
      t.index [:stage, :occurred_at]
    end

    create_table :calls, id: false do |t|
      t.string :call_id, primary_key: true
      t.string :publisher_id, null: false
      t.string :buyer_id, null: false
      t.datetime :started_at, null: false
      t.string :caller_state
      t.string :state_tag
      t.boolean :connected, null: false
      t.integer :duration_sec, null: false
      t.index :started_at
    end

    create_table :billing_lines, id: false do |t|
      t.string :line_id, primary_key: true
      t.string :partner_id, null: false
      t.string :direction, null: false
      t.string :unit_type, null: false
      t.integer :units, null: false
      t.decimal :unit_price, null: false
      t.decimal :amount, null: false
      t.date :period_start, null: false
      t.date :period_end, null: false
    end

    create_table :alerts do |t|
      t.string :incident_key, null: false
      t.string :check_name, null: false
      t.string :severity, null: false
      t.string :partner_id
      t.integer :affected_count, null: false
      t.json :sample_ids
      t.string :detail
      t.datetime :detected_at, null: false   # first 15-min tick that saw it
      t.datetime :last_new_at, null: false   # last tick that added a new affected id
      t.datetime :resolved_at                # nil = still open at end of replay
    end
  end
end
