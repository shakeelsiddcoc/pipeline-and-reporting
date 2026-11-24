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

  test "point-in-time checks only look back, so incidents can resolve; the residue is the backlog" do
    3.times { |i| lead("L#{i}"); event("L#{i}", "verified", "P1", T0) }
    assert findings(HealthMonitor::Checks::Stall, T0 + 6.minutes).any?
    assert_empty findings(HealthMonitor::Checks::Stall, T0 + 2.hours)            # nothing newly stuck
    assert_equal 3, HealthMonitor::Runner.backlog(T0 + 2.hours).sole.ids.size     # but still unworked

    lead("D1"); event("D1", "delivered", "B1", T0); event("D1", "delivered", "B1", T0 + 1.minute)
    assert findings(HealthMonitor::Checks::DuplicateDelivery, T0 + 1.hour).any?
    assert_empty findings(HealthMonitor::Checks::DuplicateDelivery, T0 + 25.hours)
  end

  test "frozen baseline keeps a long incident open instead of learning it as normal" do
    60.times { |i| lead("G#{i}", at: T0 - 3.days, accepted: i >= 6, reason: (i < 6 ? "dnc_match" : nil)) }   # 90% normal
    200.times { |i| lead("S#{i}", at: T0 - 1.day, accepted: i.even?, reason: (i.odd? ? "missing_consent" : nil)) } # long 50% stretch
    20.times { |i| lead("W#{i}", at: T0 - 1.hour, accepted: i.even?, reason: (i.odd? ? "missing_consent" : nil)) }  # still 50%
    assert_empty findings(HealthMonitor::Checks::AcceptanceDrop, T0) # rolling baseline has drifted to ~59%
    frozen = { "acceptance_drop:P1" => T0 - 2.days }                  # baseline from when the incident opened
    f = HealthMonitor::Checks::AcceptanceDrop.new(T0, frozen: frozen).findings.sole
    assert_match "normal 90%", f.detail
    assert_equal 10, f.ids.size # only the missing_consent rejects in the window
  end

  # A stand-in check that fires on the ticks we choose.
  class FlappingCheck < HealthMonitor::Check
    cattr_accessor :fire_at, default: []
    def findings
      return [] unless fire_at.include?(at)
      [finding(key: "x:P1", partner_id: "P1", severity: "high", ids: ["L#{at.to_i}"], confirm: 2,
               score: fire_at.index(at), detail: "tick #{at.strftime('%H:%M')}")]
    end
  end

  test "rate findings confirm on 2 of the last 3 ticks, and the alert keeps the worst tick's detail" do
    FlappingCheck.fire_at = [T0, T0 + 30.minutes, T0 + 60.minutes].reverse # fires, misses, fires...; worst first
    alerts = HealthMonitor::Runner.call(from: T0, to: T0 + 3.hours, checks: [FlappingCheck])
    a = alerts.sole
    assert_equal T0 + 30.minutes, a.detected_at # 2 of 3, despite never two in a row
    assert_equal "tick 09:00", a.detail         # highest score was the first tick, not the last one seen (10:00)
    assert_equal T0 + 2.hours, a.resolved_at
  end

  test "silence fires when an hour that normally has volume goes quiet, never overnight" do
    Partner.create!(partner_id: "P1", name: "Pub", partner_type: "publisher") # silence is judged per registered publisher
    3.times { |d| 8.times { |i| lead("H#{d}#{i}", at: T0 - (d + 1).days - 30.minutes - i.minutes) } } # 8 leads/day at ~08:20-08:30
    lead("NOW", at: T0 + 3.hours) # data continues later today, so 10:00 is inside the data
    f = findings(HealthMonitor::Checks::Silence, T0).find { |x| x.key == "silence:leads:P1" }
    assert_match "averages 8", f.detail
    lead("ONE", at: T0 - 20.minutes)
    assert_nil findings(HealthMonitor::Checks::Silence, T0).find { |x| x.key == "silence:leads:P1" }
    assert_empty findings(HealthMonitor::Checks::Silence, T0.change(hour: 1)) # crosses midnight / no volume
  end

  test "failed events: three non-success events from one partner in an hour" do
    3.times { |i| lead("F#{i}"); Event.create!(event_id: "X#{i}", lead_id: "F#{i}", stage: "routed", partner_id: "I1", occurred_at: T0, status: "error") }
    assert_equal "failed_events:status:I1", findings(HealthMonitor::Checks::FailedEvents, T0 + 5.minutes).sole.key
    assert_empty findings(HealthMonitor::Checks::FailedEvents, T0 + 2.hours)
  end

  test "full week replay finds exactly the known incidents, and the finished ones resolve" do
    Importer.call
    alerts = HealthMonitor::Runner.call.index_by(&:incident_key)
    assert_equal({
      "misrouting:call_state_tag:P3" => 25,
      "acceptance_drop:P3" => 46,          # missing_consent only
      "silence:calls:P1" => 0,             # Wed 08:40-11:10, no P1 calls
      "stall:routed:P2" => 23,
      "duplicate_delivery:delivered:B2" => 5,
      "broken_sequence:no_qualified:I1" => 18,
      "conversion_drop:contacted:I1" => 30
    }, alerts.transform_values(&:affected_count))
    assert_equal Time.utc(2026, 10, 8, 19, 15), alerts["stall:routed:P2"].resolved_at
    assert alerts["duplicate_delivery:delivered:B2"].resolved_at
    assert_nil alerts["broken_sequence:no_qualified:I1"].resolved_at # still happening at end of data
    assert_match "z=12.7", alerts["acceptance_drop:P3"].detail       # worst tick, not the tail
    assert_equal 23, HealthMonitor::Runner.backlog.sole.ids.size
  end
end
