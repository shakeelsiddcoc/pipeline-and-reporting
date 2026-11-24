module HealthMonitor
  module Checks
    # Leads newly stuck at a stage with a hard SLA. Later stages (contacted, qualified, ...) are not
    # checked here because most leads normally stop there; their health is ConversionDrop's job.
    # Only leads that crossed the SLA within LOOKBACK count, so the alert resolves once new leads flow
    # again. Leads left stuck are the backlog (`backlog: true`, no lower bound): a different question.
    class Stall < Check
      LOOKBACK = 1.hour # leads arrive every few minutes, so an hour without new stuck ones means it stopped
      # sla = brief's SLA plus grace for ingestion lag; observed max in the data is far below it.
      RULES = [
        { from: "received", to: "verified",  sla: 5.minutes,  min: 3 },  # observed max 6s
        { from: "verified", to: "routed",    sla: 5.minutes,  min: 3 },  # brief: 1 min; observed max 12s
        { from: "signed",   to: "delivered", sla: 30.minutes, min: 1 }   # observed max 6.4 min; $3,000 each
      ].freeze

      def initialize(at, backlog: false, **)
        super(at, **)
        @backlog = backlog
      end

      def findings
        RULES.flat_map do |r|
          stuck = r[:from] == "received" ? unverified(r) : stuck_at(r)
          per_partner(stuck, id_col: "lead_id", min: @backlog ? 1 : r[:min], key: r[:to],
                      # 5+ newly stuck in an hour is about all of one publisher's traffic (~5 leads/h)
                      severity: ->(n) { n >= 5 || r[:to] == "delivered" ? "critical" : "high" }) do |n, _|
            @backlog ? "#{n} leads #{r[:from]} with no #{r[:to]} event" :
                       "#{n} leads #{r[:from]} > #{r[:sla].inspect} ago with no #{r[:to]} event"
          end
        end
      end

      private

      def window(r) = { cutoff: at - r[:sla], since: @backlog ? Time.utc(1970) : at - r[:sla] - LOOKBACK, at: at, to: r[:to] }

      def unverified(r)
        rows(<<~SQL, **window(r))
          SELECT l.publisher_id AS partner_id, l.lead_id FROM leads l
          WHERE l.accepted AND l.received_at <= :cutoff AND l.received_at > :since
            AND NOT EXISTS (SELECT 1 FROM events e WHERE e.lead_id = l.lead_id AND e.stage = :to AND e.occurred_at <= :at)
        SQL
      end

      def stuck_at(r)
        rows(<<~SQL, **window(r), from: r[:from])
          SELECT e.partner_id, e.lead_id FROM events e
          WHERE e.stage = :from AND e.occurred_at <= :cutoff AND e.occurred_at > :since
            AND NOT EXISTS (SELECT 1 FROM events n WHERE n.lead_id = e.lead_id AND n.stage = :to AND n.occurred_at <= :at)
        SQL
      end
    end
  end
end
