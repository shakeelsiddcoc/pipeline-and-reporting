-- Inbound calls per day and publisher. Billable = connected AND duration >= :billable_sec.
SELECT date(started_at) AS day,
       CASE WHEN g.total THEN 'ALL' ELSE publisher_id END AS partner_id,
       COUNT(*) AS received,
       SUM(connected) AS connected,
       SUM(connected AND duration_sec >= :billable_sec) AS billable,
       ROUND(1.0 * SUM(connected) / COUNT(*), 3) AS connect_rate,
       ROUND(1.0 * SUM(connected AND duration_sec >= :billable_sec) / NULLIF(SUM(connected), 0), 3) AS billable_rate,
       SUM(connected AND duration_sec >= :billable_sec) * :call_price AS payable
FROM calls CROSS JOIN (SELECT 0 AS total UNION ALL SELECT 1) g
GROUP BY 1, 2
ORDER BY day, partner_id = 'ALL', partner_id;
