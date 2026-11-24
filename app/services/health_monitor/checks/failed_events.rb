module HealthMonitor
  module Checks
    # Pipeline events whose status isn't success: usually the first sign of a partner integration failing.
    class FailedEvents < Check
      LOOKBACK = 1.hour
      MIN = 3 # one failed event is a retry; three in an hour from one partner is an outage

      def findings
        failed = rows(<<~SQL, at: at, since: at - LOOKBACK)
          SELECT partner_id, lead_id, stage FROM events
          WHERE status IS NOT 'success' AND occurred_at <= :at AND occurred_at > :since
        SQL
        per_partner(failed, id_col: "lead_id", min: MIN, key: "status", severity: "high") do |n, rs|
          "#{n} leads with non-success events in the last hour (#{rs.map { |r| r['stage'] }.tally.map { |s, c| "#{s} #{c}" }.join(', ')})"
        end
      end
    end
  end
end
