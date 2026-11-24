require "test_helper"

class BillingReconcilerTest < ActiveSupport::TestCase
  test "full week: every line's decision and impact" do
    Importer.call
    got = BillingReconciler.call.to_h { |r| [r["line_id"], [r["supported_units"], r["dollar_impact"], r["decision"]]] }
    assert_equal({
      "INV001" => [698, 2660, "dispute"], "INV002" => [601, 0, "approve"], "INV003" => [560, 0, "approve"],
      "INV004" => [116, 0, "approve"], "INV005" => [144, 1980, "dispute"], "INV006" => [146, 0, "hold"],
      "INV007" => [37, 9000, "hold"], "INV008" => [16, 18000, "hold"], "INV009" => [17, 3000, "hold"]
    }, got)
  end

  def line(**attrs)
    BillingLine.new(line_id: "X", partner_id: "P1", direction: "payable", unit_type: "accepted_lead", units: 1,
                    unit_price: 35, amount: 35, period_start: Date.new(2026, 10, 5), period_end: Date.new(2026, 10, 11), **attrs)
  end

  test "wrong contract price is held even when units match" do
    assert_equal "hold", BillingReconciler.decide(line(unit_price: 40, amount: 40), 0, {}, 40).first
  end

  test "under-billing is held, not disputed or approved" do
    assert_equal "hold", BillingReconciler.decide(line, -2, {}, 35).first
  end

  test "period end is inclusive and the next day is excluded" do
    Lead.create!(lead_id: "L1", publisher_id: "P1", received_at: Time.utc(2026, 10, 11, 23, 59), accepted: true)
    Lead.create!(lead_id: "L2", publisher_id: "P1", received_at: Time.utc(2026, 10, 12, 0, 0), accepted: true)
    assert_equal 1, BillingReconciler.reconcile(line)["supported_units"]
  end

  test "a lead delivered to two buyers is billable only to the first" do
    Lead.create!(lead_id: "L1", publisher_id: "P1", received_at: Time.utc(2026, 10, 6), accepted: true)
    Event.create!(event_id: "E1", lead_id: "L1", stage: "delivered", partner_id: "B1", occurred_at: Time.utc(2026, 10, 6, 10))
    Event.create!(event_id: "E2", lead_id: "L1", stage: "delivered", partner_id: "B2", occurred_at: Time.utc(2026, 10, 6, 11))
    supported = ->(b) { BillingReconciler.reconcile(line(partner_id: b, direction: "receivable", unit_type: "signed_case", unit_price: 3000, amount: 3000))["supported_units"] }
    assert_equal [1, 0], [supported.("B1"), supported.("B2")]
  end
end
