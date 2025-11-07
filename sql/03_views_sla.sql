BEGIN;

CREATE OR REPLACE VIEW synth.sla_result_v AS
SELECT
  r.result_id,
  s.specimen_id,
  s.source_site,
  CASE
    WHEN EXTRACT(HOUR FROM s.received_ts) BETWEEN 7  AND 14 THEN 'Day'
    WHEN EXTRACT(HOUR FROM s.received_ts) BETWEEN 15 AND 22 THEN 'Evening'
    ELSE 'Night'
  END AS shift,
  a.analyte_code,
  a.tat_target_minutes AS sla_min,
  EXTRACT(EPOCH FROM (r.verified_ts - s.received_ts))/60.0 AS tat_min,
  (EXTRACT(EPOCH FROM (r.verified_ts - s.received_ts))/60.0 <= a.tat_target_minutes) AS hit,
  s.received_ts, r.verified_ts
FROM synth.results r
JOIN synth.specimens s USING (specimen_id)
JOIN synth.analytes  a USING (analyte_code);

CREATE OR REPLACE VIEW synth.sla_shift_v AS
SELECT shift,
       ROUND(AVG(tat_min),1)          AS avg_tat_min,
       ROUND(100.0 * AVG(hit::int),2) AS sla_hit_pct,
       COUNT(*)                       AS n
FROM synth.sla_result_v
GROUP BY shift
ORDER BY sla_hit_pct DESC;

CREATE OR REPLACE VIEW synth.sla_site_v AS
SELECT source_site,
       ROUND(AVG(tat_min),1)          AS avg_tat_min,
       ROUND(100.0 * AVG(hit::int),2) AS sla_hit_pct,
       COUNT(*)                       AS n
FROM synth.sla_result_v
GROUP BY source_site
ORDER BY sla_hit_pct DESC;

-- (Optional) order-level strictness
CREATE OR REPLACE VIEW synth.sla_order_shift_v AS
SELECT shift,
       ROUND(100.0 * AVG(all_hit::int),2) AS order_sla_pct,
       COUNT(*) AS orders
FROM (
  SELECT specimen_id, shift, BOOL_AND(hit) AS all_hit
  FROM synth.sla_result_v
  GROUP BY specimen_id, shift
) t
GROUP BY shift
ORDER BY order_sla_pct DESC;

COMMIT;
