-- Signed cases delivered, per day and buyer, each lead counted once (on its first delivery).
-- Extra delivery events for the same lead are shown separately as duplicates; they are not revenue.
WITH per_lead AS (
  -- SQLite: with MIN(), bare columns come from the row holding the minimum, i.e. the first delivery.
  SELECT lead_id, partner_id AS buyer_id, MIN(occurred_at) AS first_at, COUNT(*) AS deliveries
  FROM events WHERE stage = 'delivered'
  GROUP BY lead_id
)
SELECT date(first_at) AS day,
       CASE WHEN g.total THEN 'ALL' ELSE buyer_id END AS partner_id,
       COUNT(*) AS cases_delivered,
       SUM(deliveries) - COUNT(*) AS duplicate_deliveries,
       COUNT(*) * :case_price AS receivable
FROM per_lead CROSS JOIN (SELECT 0 AS total UNION ALL SELECT 1) g
GROUP BY 1, 2
ORDER BY day, partner_id = 'ALL', partner_id;
