module HealthMonitor
  module Checks
    # Same lead delivered more than once. Any occurrence is critical: it double-bills a buyer.
    class DuplicateDelivery < Check
      def findings
        dupes = rows(<<~SQL, at: at)
          SELECT e.partner_id, e.lead_id FROM events e
          WHERE e.stage = 'delivered' AND e.occurred_at <= :at
            AND e.lead_id IN (SELECT lead_id FROM events WHERE stage = 'delivered' AND occurred_at <= :at
                              GROUP BY lead_id HAVING COUNT(*) > 1)
        SQL
        per_partner(dupes, id_col: "lead_id", min: 1, key: "delivered", severity: "critical") do |n, rs|
          extra = rs.size - n
          "#{n} leads delivered more than once (#{extra} extra deliveries, $#{extra * PipelineRules::CASE_PRICE} at risk)"
        end
      end
    end
  end
end
