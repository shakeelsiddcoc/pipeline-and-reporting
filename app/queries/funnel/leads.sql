-- Leads received / accepted / rejected by reason, per day (received date) and publisher, plus a daily ALL row.
-- The CROSS JOIN with (0, 1) emits every lead twice: once for its publisher, once for the ALL total.
SELECT date(l.received_at) AS day,
       CASE WHEN g.total THEN 'ALL' ELSE l.publisher_id END AS partner_id,
       COUNT(*) AS received,
       SUM(l.accepted) AS accepted,
       SUM(NOT l.accepted) AS rejected,
       SUM(l.reject_reason = 'missing_consent') AS rejected_missing_consent,
       SUM(l.reject_reason = 'invalid_phone') AS rejected_invalid_phone,
       SUM(l.reject_reason = 'dnc_match') AS rejected_dnc_match,
       ROUND(1.0 * SUM(l.accepted) / COUNT(*), 3) AS acceptance_rate
FROM leads l CROSS JOIN (SELECT 0 AS total UNION ALL SELECT 1) g
GROUP BY 1, 2
ORDER BY day, partner_id = 'ALL', partner_id;
