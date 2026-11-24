module HealthMonitor
  module Checks
    # Publisher acceptance rate in the last WINDOW vs its own history.
    class AcceptanceDrop < Check
      WINDOW = 4.hours # ~22 leads per publisher: clears MIN_WINDOW_N, still catches an outage the same morning

      def findings
        stats = rows(<<~SQL, ws: at - WINDOW, at: at)
          SELECT publisher_id AS partner_id,
                 SUM(received_at > :ws) AS n, SUM(received_at > :ws AND accepted) AS hits,
                 SUM(received_at <= :ws) AS base_n, SUM(received_at <= :ws AND accepted) AS base_hits
          FROM leads WHERE received_at <= :at GROUP BY publisher_id
        SQL
        stats.filter_map do |s|
          d = RateDrop.drop(n: s["n"], hits: s["hits"], base_n: s["base_n"], base_hits: s["base_hits"])
          next unless d
          rejected = rows(<<~SQL, ws: at - WINDOW, at: at, p: s["partner_id"])
            SELECT lead_id, reject_reason FROM leads
            WHERE publisher_id = :p AND NOT accepted AND received_at > :ws AND received_at <= :at
          SQL
          top = rejected.map { |r| r["reject_reason"] }.tally.max_by(&:last)
          finding(key: s["partner_id"], partner_id: s["partner_id"], severity: "high", confirm: RateDrop::CONFIRM_TICKS,
                  ids: rejected.map { |r| r["lead_id"] },
                  detail: "#{RateDrop.describe('acceptance', s['n'], d)}; top reject reason #{top[0]} (#{top[1]})")
        end
      end
    end
  end
end
