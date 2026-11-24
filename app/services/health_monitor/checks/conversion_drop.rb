module HealthMonitor
  module Checks
    # Intake-center stage-to-stage conversion vs its own history. A lead "converts" if it reaches
    # the next stage or any later one, so a skipped stage is left to BrokenSequence (no double alert).
    # Each cohort is only judged after `mature`, ~1.5x the slowest normal transition in the data,
    # so leads that simply have not been worked yet are not counted as lost.
    class ConversionDrop < Check
      WINDOW = 12.hours # intake volume is low (~2-3 contacts/hour per center)
      TRANSITIONS = [
        { from: "routed",        mature: 2.hours },   # observed max 90 min
        { from: "contacted",     mature: 1.hour },    # observed max 40 min
        { from: "qualified",     mature: 30.minutes }, # observed max 10 min
        { from: "retainer_sent", mature: 15.hours }   # observed max 10 h
      ].freeze

      def findings
        TRANSITIONS.flat_map do |tr|
          later = PipelineRules::STAGES.drop(PipelineRules::STAGES.index(tr[:from]) + 1)
          we = at - tr[:mature]
          stats = rows(<<~SQL, from: tr[:from], later: later, ws: we - WINDOW, we: we, at: at)
            SELECT partner_id, SUM(in_win) AS n, SUM(in_win AND conv) AS hits,
                   SUM(NOT in_win) AS base_n, SUM(NOT in_win AND conv) AS base_hits,
                   GROUP_CONCAT(CASE WHEN in_win AND NOT conv THEN lead_id END) AS lost
            FROM (SELECT a.partner_id, a.lead_id, a.occurred_at > :ws AS in_win,
                         EXISTS (SELECT 1 FROM events b WHERE b.lead_id = a.lead_id AND b.stage IN (:later)
                                 AND b.occurred_at <= :at) AS conv
                  FROM events a WHERE a.stage = :from AND a.occurred_at <= :we)
            GROUP BY partner_id
          SQL
          stats.filter_map do |s|
            key = "#{tr[:from]}:#{s['partner_id']}"
            bs = frozen[full_key(key)]
            s = s.merge(rows(<<~SQL, from: tr[:from], later: later, p: s["partner_id"], bs: bs, at: at).first) if bs
              SELECT COUNT(*) AS base_n,
                     SUM(EXISTS (SELECT 1 FROM events b WHERE b.lead_id = a.lead_id AND b.stage IN (:later)
                                 AND b.occurred_at <= :at)) AS base_hits
              FROM events a WHERE a.stage = :from AND a.partner_id = :p AND a.occurred_at <= :bs
            SQL
            d = RateDrop.drop(n: s["n"], hits: s["hits"], base_n: s["base_n"].to_i, base_hits: s["base_hits"].to_i)
            next unless d
            finding(key: key, partner_id: s["partner_id"], severity: "high", confirm: RateDrop::CONFIRM_TICKS,
                    ids: s["lost"].to_s.split(","), score: d[:base] - d[:rate], baseline_end: bs || we - WINDOW,
                    detail: RateDrop.describe("#{tr[:from]} -> #{later.first}+ conversion", s["n"], d))
          end
        end
      end
    end
  end
end
