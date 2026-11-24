module HealthMonitor
  module Checks
    # A lead delivered again after its first delivery. Any occurrence is critical: it double-bills a buyer.
    # Only repeat deliveries within LOOKBACK count, so the incident resolves a day after the last one.
    class DuplicateDelivery < Check
      LOOKBACK = 24.hours # deliveries are sparse (~10/day); a shorter window would split one incident

      def findings
        repeats = rows(<<~SQL, at: at, since: at - LOOKBACK)
          SELECT e.partner_id, e.lead_id FROM events e
          WHERE e.stage = 'delivered' AND e.occurred_at <= :at AND e.occurred_at > :since
            AND EXISTS (SELECT 1 FROM events f WHERE f.lead_id = e.lead_id AND f.stage = 'delivered'
                        AND (f.occurred_at < e.occurred_at OR (f.occurred_at = e.occurred_at AND f.event_id < e.event_id)))
        SQL
        per_partner(repeats, id_col: "lead_id", min: 1, key: "delivered", severity: "critical") do |n, rs|
          "#{n} leads delivered again (#{rs.size} repeat deliveries in 24h, $#{(rs.size * PipelineRules::CASE_PRICE).to_fs(:delimited)} at risk)"
        end
      end
    end
  end
end
