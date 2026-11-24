require "test_helper"

# Pins the report to totals verified independently with raw SQL against the CSVs.
class FunnelReportTest < ActiveSupport::TestCase
  setup { Importer.call }

  def row(section, day, partner) = FunnelReport.rows(section).find { |r| r["day"] == day && r["partner_id"] == partner }
  def week(section, partner, col) = FunnelReport.rows(section).select { |r| r["partner_id"] == partner }.sum { |r| r[col] }

  test "leads by reason" do
    assert_equal [46, 0.5], row("leads", "2026-10-07", "P3").values_at("rejected_missing_consent", "acceptance_rate")
    assert_equal 2104, week("leads", "ALL", "received")
    assert_equal 1859, week("leads", "ALL", "accepted")
  end

  test "stage counts and conversion" do
    assert_equal [83, 60], row("stages", "2026-10-08", "P2").values_at("verified", "routed")
    assert_equal [0, 9, nil], row("stages", "2026-10-10", "I1").values_at("qualified", "retainer_sent", "qualified_to_retainer_sent")
  end

  test "deliveries count each lead once and show duplicates" do
    assert_equal({ "B1" => 38, "B2" => 17, "B3" => 18 }, %w[B1 B2 B3].to_h { |b| [b, week("deliveries", b, "cases_delivered")] })
    assert_equal 5, week("deliveries", "B2", "duplicate_deliveries")
  end

  test "billable calls use the 90s rule" do
    assert_equal({ "P1" => 116, "P2" => 144, "P3" => 146 }, %w[P1 P2 P3].to_h { |p| [p, week("calls", p, "billable")] })
  end
end
