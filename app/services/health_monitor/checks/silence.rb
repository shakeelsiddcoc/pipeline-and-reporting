module HealthMonitor
  module Checks
    # A publisher's leads or calls going to zero at a time of day that normally has volume.
    # Rate checks can't see this: with no rows there is no rate.
    class Silence < Check
      WINDOW = 2.hours
      MIN_EXPECTED = 6 # judge only windows where earlier days averaged 6+; overnight (≈0) never fires
      SOURCES = { "leads" => "received_at", "calls" => "started_at" }.freeze

      def findings
        ws = at - WINDOW
        # shortcut: windows that cross midnight are skipped; volume there is ~0 so they could never fire
        return [] if ws.to_date != at.to_date
        first = Lead.minimum(:received_at)
        days = first ? (at.to_date - first.to_date).to_i : 0
        return [] if days < 1

        SOURCES.flat_map do |table, ts|
          # The export stops at its last row; past it there is no data, not silence. Live, "now" is that edge.
          edge = ApplicationRecord.connection.select_value("SELECT MAX(#{ts}) FROM #{table}")
          next [] if edge.nil? || at > Time.zone.parse(edge)
          rows(<<~SQL, ws: ws, at: at, day_start: at.beginning_of_day).filter_map do |r|
            SELECT p.partner_id,
                   COALESCE(SUM(t.#{ts} > :ws), 0) AS actual,
                   COALESCE(SUM(t.#{ts} < :day_start AND time(t.#{ts}) > time(:ws) AND time(t.#{ts}) <= time(:at)), 0) AS prior
            FROM partners p LEFT JOIN #{table} t ON t.publisher_id = p.partner_id AND t.#{ts} <= :at
            WHERE p.partner_type = 'publisher'
            GROUP BY p.partner_id
          SQL
            expected = r["prior"].fdiv(days)
            next if r["actual"].positive? || expected < MIN_EXPECTED
            finding(key: "#{table}:#{r['partner_id']}", partner_id: r["partner_id"], severity: "high", ids: [],
                    score: expected, detail: format("no %s in the last %d h (this time of day averages %.0f)", table, WINDOW / 1.hour, expected))
          end
        end
      end
    end
  end
end
