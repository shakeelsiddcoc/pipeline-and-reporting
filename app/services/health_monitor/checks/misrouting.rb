module HealthMonitor
  module Checks
    # Leads routed/delivered, or calls sent, to a partner the state routing table does not allow.
    # Only the last LOOKBACK counts, so the incident resolves a day after the last misrouted one.
    class Misrouting < Check
      MIN_CALLS = 2 # a single odd call is noise; two from one publisher in a day is a pattern
      LOOKBACK = 24.hours

      def findings
        lead_findings + call_findings
      end

      private

      def lead_findings
        bad = rows(<<~SQL, at: at, since: at - LOOKBACK)
          WITH #{PipelineRules.routing_cte}
          SELECT e.partner_id, e.lead_id, e.stage FROM events e
          JOIN leads l ON l.lead_id = e.lead_id LEFT JOIN routing r ON r.state = l.state
          WHERE e.occurred_at <= :at AND e.occurred_at > :since
            AND ((e.stage = 'routed' AND e.partner_id IS NOT r.intake)
              OR (e.stage = 'delivered' AND e.partner_id IS NOT r.buyer))
        SQL
        per_partner(bad, id_col: "lead_id", min: 1, key: "lead", severity: "high") do |n, _|
          "#{n} leads in 24h routed/delivered to a partner not allowed for their state"
        end
      end

      # A call is misrouted when its buyer is not the one for the caller's actual state.
      # Cause is split: bad state tag from the publisher vs. our router ignoring a correct tag.
      def call_findings
        bad = rows(<<~SQL, at: at, since: at - LOOKBACK)
          WITH #{PipelineRules.routing_cte}
          SELECT c.publisher_id AS partner_id, c.call_id,
                 CASE WHEN c.state_tag IS NOT c.caller_state THEN 'state_tag' ELSE 'router' END AS cause
          FROM calls c LEFT JOIN routing rc ON rc.state = c.caller_state
          WHERE c.started_at <= :at AND c.started_at > :since AND c.buyer_id IS NOT rc.buyer
        SQL
        bad.group_by { |r| r["cause"] }.flat_map do |cause, rs|
          per_partner(rs, id_col: "call_id", min: MIN_CALLS, key: "call_#{cause}", severity: "medium") do |n, _|
            cause == "state_tag" ? "#{n} calls in 24h tagged with the wrong state and sent to the wrong buyer" :
                                   "#{n} calls in 24h sent to the wrong buyer despite a correct state tag"
          end
        end
      end
    end
  end
end
