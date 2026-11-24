require "test_helper"

class HealthMonitorTest < ActiveSupport::TestCase
  T0 = Time.utc(2026, 10, 5, 9)

  def lead(id, state: "TX", pub: "P1", at: T0, accepted: true, reason: nil)
    Lead.create!(lead_id: id, publisher_id: pub, received_at: at, state: state, accepted: accepted, reject_reason: reason)
  end

  def event(lead_id, stage, partner, at)
    Event.create!(event_id: "E#{Event.count + 1}", lead_id: lead_id, stage: stage, partner_id: partner, occurred_at: at)
  end

  def call(id, tag:, actual:, buyer:, at: T0)
    Call.create!(call_id: id, publisher_id: "P3", buyer_id: buyer, started_at: at, caller_state: actual,
                 state_tag: tag, connected: true, duration_sec: 120)
  end

  def findings(check, at) = check.new(at).findings

  test "stall fires at 3 unrouted leads after SLA, not at 2 or before SLA" do
    3.times { |i| lead("L#{i}"); event("L#{i}", "verified", "P1", T0) }
    assert_empty findings(HealthMonitor::Checks::Stall, T0 + 4.minutes)
    f = findings(HealthMonitor::Checks::Stall, T0 + 6.minutes).sole
    assert_equal ["stall:routed:P1", 3], [f.key, f.ids.size]

    event("L0", "routed", "I1", T0 + 1.minute)
    assert_empty findings(HealthMonitor::Checks::Stall, T0 + 6.minutes)
  end

  test "duplicate delivery fires on second delivery only" do
    lead("L1"); event("L1", "delivered", "B1", T0)
    assert_empty findings(HealthMonitor::Checks::DuplicateDelivery, T0 + 1.hour)
    event("L1", "delivered", "B1", T0 + 10.minutes)
    assert_equal ["L1"], findings(HealthMonitor::Checks::DuplicateDelivery, T0 + 1.hour).sole.ids
  end

  test "acceptance drop needs a big, significant drop on enough volume" do
    100.times { |i| lead("B#{i}", at: T0 - 1.day, accepted: i >= 10, reason: (i < 10 ? "invalid_phone" : nil)) } # 90% normal
    20.times { |i| lead("W#{i}", at: T0 - 1.hour, accepted: i >= 4, reason: (i < 4 ? "dnc_match" : nil)) }        # 80%: noise
    assert_empty findings(HealthMonitor::Checks::AcceptanceDrop, T0)

    10.times { |i| lead("X#{i}", at: T0 - 30.minutes, accepted: false, reason: "missing_consent") }              # 53%
    f = findings(HealthMonitor::Checks::AcceptanceDrop, T0).sole
    assert_equal "P1", f.partner_id
    assert_match "missing_consent", f.detail
  end

  test "broken sequence flags a skipped stage after grace" do
    lead("L1"); event("L1", "contacted", "I1", T0)
    assert_empty findings(HealthMonitor::Checks::BrokenSequence, T0 + 10.minutes)
    f = findings(HealthMonitor::Checks::BrokenSequence, T0 + 20.minutes).sole
    assert_equal "broken_sequence:no_routed:I1", f.key
  end

  test "misrouting: wrong intake for lead state; calls only when buyer is wrong for caller's state" do
    lead("L1", state: "FL"); event("L1", "routed", "I1", T0)
    call("C1", tag: "GA", actual: "TX", buyer: "B1") # wrong tag but same buyer: not misrouted
    call("C2", tag: "CA", actual: "TX", buyer: "B3")
    call("C3", tag: "FL", actual: "GA", buyer: "B2")
    keys = findings(HealthMonitor::Checks::Misrouting, T0 + 1.minute).to_h { |f| [f.key, f.ids.sort] }
    assert_equal({ "misrouting:lead:I1" => ["L1"], "misrouting:call_state_tag:P3" => %w[C2 C3] }, keys)
  end

  test "full week replay finds exactly the known incidents" do
    Importer.call
    got = HealthMonitor::Runner.call.to_h { |a| [a.incident_key, a.affected_count] }
    assert_equal({
      "misrouting:call_state_tag:P3" => 25,
      "acceptance_drop:P3" => 49,
      "stall:routed:P2" => 23,
      "duplicate_delivery:delivered:B2" => 5,
      "broken_sequence:no_qualified:I1" => 18,
      "conversion_drop:contacted:I1" => 30
    }, got)
  end
end
