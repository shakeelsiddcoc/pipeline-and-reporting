module HealthMonitor
  module Checks
    # A lead showing a stage without the stage before it, or a rejected lead in the pipeline.
    # Events get GRACE to let an out-of-order predecessor land before we call it broken.
    class BrokenSequence < Check
      GRACE = 15.minutes

      def findings
        stages = PipelineRules::STAGES
        prev_case = stages.each_cons(2).map { |a, b| "WHEN '#{b}' THEN '#{a}'" }.join(" ")
        broken = rows(<<~SQL, cutoff: at - GRACE, at: at)
          SELECT e.partner_id, e.lead_id, CASE e.stage #{prev_case} END AS missing
          FROM events e
          WHERE e.stage <> 'verified' AND e.occurred_at <= :cutoff
            AND NOT EXISTS (SELECT 1 FROM events p WHERE p.lead_id = e.lead_id
                            AND p.stage = CASE e.stage #{prev_case} END AND p.occurred_at <= :at)
          UNION ALL
          SELECT e.partner_id, e.lead_id, 'accepted' AS missing
          FROM events e JOIN leads l ON l.lead_id = e.lead_id
          WHERE NOT l.accepted AND e.occurred_at <= :cutoff
        SQL
        broken.group_by { |r| r["missing"] }.flat_map do |missing, rs|
          per_partner(rs, id_col: "lead_id", min: 1, key: "no_#{missing}", severity: "high") do |n, _|
            missing == "accepted" ? "#{n} rejected leads have pipeline events" : "#{n} leads skipped the #{missing} stage"
          end
        end
      end
    end
  end
end
