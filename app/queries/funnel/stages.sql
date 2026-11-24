-- Pipeline funnel for accepted leads, cohorted by the day the lead was received.
-- Each lead counts once per stage it reached. Shown per publisher, per intake center (the one it
-- was routed to) and as a daily ALL row. Conversion = this stage / previous stage.
WITH reached AS (
  SELECT l.lead_id, date(l.received_at) AS day, l.publisher_id,
         MAX(CASE WHEN e.stage = 'routed' THEN e.partner_id END) AS intake_id,
         MAX(e.stage = 'verified') AS verified, MAX(e.stage = 'routed') AS routed,
         MAX(e.stage = 'contacted') AS contacted, MAX(e.stage = 'qualified') AS qualified,
         MAX(e.stage = 'retainer_sent') AS retainer_sent, MAX(e.stage = 'signed') AS signed,
         MAX(e.stage = 'delivered') AS delivered
  FROM leads l LEFT JOIN events e ON e.lead_id = l.lead_id
  WHERE l.accepted
  GROUP BY l.lead_id
), counts AS (
  SELECT r.day, g.partner_type,
         CASE g.partner_type WHEN 'publisher' THEN r.publisher_id
                             WHEN 'intake_center' THEN r.intake_id ELSE 'ALL' END AS partner_id,
         COUNT(*) AS accepted, SUM(verified) AS verified, SUM(routed) AS routed, SUM(contacted) AS contacted,
         SUM(qualified) AS qualified, SUM(retainer_sent) AS retainer_sent, SUM(signed) AS signed,
         SUM(delivered) AS delivered
  FROM reached r
  CROSS JOIN (SELECT 'publisher' AS partner_type UNION ALL SELECT 'intake_center' UNION ALL SELECT 'all') g
  GROUP BY 1, 2, 3
)
SELECT day, partner_type, partner_id, accepted, verified, routed, contacted, qualified, retainer_sent, signed, delivered,
       ROUND(1.0 * verified / NULLIF(accepted, 0), 3)           AS accepted_to_verified,
       ROUND(1.0 * routed / NULLIF(verified, 0), 3)             AS verified_to_routed,
       ROUND(1.0 * contacted / NULLIF(routed, 0), 3)            AS routed_to_contacted,
       ROUND(1.0 * qualified / NULLIF(contacted, 0), 3)         AS contacted_to_qualified,
       ROUND(1.0 * retainer_sent / NULLIF(qualified, 0), 3)     AS qualified_to_retainer_sent,
       ROUND(1.0 * signed / NULLIF(retainer_sent, 0), 3)        AS retainer_sent_to_signed,
       ROUND(1.0 * delivered / NULLIF(signed, 0), 3)            AS signed_to_delivered
FROM counts
WHERE partner_id IS NOT NULL -- leads never routed have no intake center
ORDER BY day, partner_type = 'all', partner_type DESC, partner_id;
