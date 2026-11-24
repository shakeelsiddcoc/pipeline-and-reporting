# Part C: compares each billing line to what the data supports for the same partner and period.
# Besides the supported count, each unit type computes the usual *wrong* ways to count. If the billed
# units equal one of them, that is reported as the likely cause, instead of a bare "doesn't match".
class BillingReconciler
  PRICES = { "accepted_lead" => PipelineRules::LEAD_PRICE, "billable_call" => PipelineRules::CALL_PRICE,
             "signed_case" => PipelineRules::CASE_PRICE }.freeze

  QUERIES = {
    "accepted_lead" => <<~SQL,
      SELECT SUM(accepted) AS supported, COUNT(*) AS all_received
      FROM leads WHERE publisher_id = :p AND received_at >= :from AND received_at < :to
    SQL
    "billable_call" => <<~SQL,
      WITH #{PipelineRules.routing_cte}
      SELECT SUM(c.connected AND c.duration_sec >= :sec) AS supported,
             SUM(c.connected AND c.duration_sec >= 60) AS connected_60s,
             SUM(c.connected) AS all_connected,
             SUM(c.connected AND c.duration_sec >= :sec AND c.buyer_id IS NOT r.buyer) AS misrouted_billable
      FROM calls c LEFT JOIN routing r ON r.state = c.caller_state
      WHERE c.publisher_id = :p AND c.started_at >= :from AND c.started_at < :to
    SQL
    "signed_case" => <<~SQL
      -- one row per lead delivered to this buyer; its first delivery decides the period
      WITH d AS (SELECT lead_id, MIN(occurred_at) AS first_at, COUNT(*) AS n
                 FROM events WHERE stage = 'delivered' AND partner_id = :p GROUP BY lead_id)
      SELECT SUM(first_at >= :from AND first_at < :to) AS supported,
             SUM(first_at >= :from) AS incl_after_period,
             SUM(n) AS delivery_events
      FROM d
    SQL
  }.freeze

  CAUSES = {
    "all_received" => "billed every received lead, rejected ones included",
    "connected_60s" => "billed calls of 60 s or more; billable is 90 s or more",
    "all_connected" => "billed every connected call regardless of duration",
    "delivery_events" => "counted every delivery event: duplicate deliveries of one lead, and deliveries after the period end",
    "incl_after_period" => "includes cases delivered after the period end (belong on next period's invoice)"
  }.freeze

  def self.call = BillingLine.order(:line_id).map { |line| reconcile(line) }

  def self.reconcile(line)
    from = line.period_start.to_time(:utc)
    to = (line.period_end + 1).to_time(:utc) # period_end is inclusive
    query = QUERIES.fetch(line.unit_type)
    stats = ApplicationRecord.connection.select_one(ApplicationRecord.sanitize_sql(
      [query, { p: line.partner_id, from: from, to: to, sec: PipelineRules::BILLABLE_CALL_SEC }.select { |k, _| query.include?(":#{k}") }]
    )).transform_values(&:to_i)
    supported = stats.delete("supported")
    price = line.unit_price.to_i
    diff = line.units - supported
    decision, reason = decide(line, diff, stats, price)
    { "line_id" => line.line_id, "partner_id" => line.partner_id, "direction" => line.direction,
      "unit_type" => line.unit_type, "billed_units" => line.units, "supported_units" => supported,
      "diff_units" => diff, "unit_price" => price, "billed_amount" => line.amount.to_i,
      "supported_amount" => supported * price, "dollar_impact" => diff * price,
      "decision" => decision, "reason" => reason }
  end

  def self.decide(line, diff, stats, price)
    expected = PRICES.fetch(line.unit_type)
    if price != expected || line.amount != line.units * line.unit_price
      return ["hold", "price or amount does not match the contract ($#{expected}/unit)"]
    end
    if diff.zero?
      flagged = stats["misrouted_billable"].to_i
      return ["approve", "matches the data"] if flagged.zero?
      return ["hold", "units match, but #{flagged} billable calls went to the wrong buyer (bad state tag); " \
                      "approve #{line.units - flagged}, hold $#{(flagged * price).to_fs(:delimited)} pending a policy decision"]
    end
    cause = stats.find { |k, v| CAUSES.key?(k) && v == line.units }&.first
    why = cause ? CAUSES[cause] : unexplained(line, stats, diff)
    why = "#{why} (#{diff.abs} #{diff.positive? ? 'over' : 'under'}, $#{(diff * price).abs.to_fs(:delimited)})"
    return ["dispute", "publisher over-billed: #{why}"] if line.direction == "payable" && diff.positive?
    ["hold", line.direction == "receivable" ? "our invoice is wrong, correct before sending: #{why}" : why]
  end

  # No single wrong rule matches: explain what part of the gap the data can account for.
  def self.unexplained(line, stats, diff)
    late = stats["incl_after_period"].to_i - (line.units - diff)
    known = late.positive? && diff.positive? ? "#{late} delivered after the period end, " : ""
    "#{known}#{diff - (known.empty? ? 0 : late)} not found in the data at all"
  end
end
