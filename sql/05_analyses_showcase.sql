-- Overall result-level SLA
SELECT ROUND(
  100.0 * AVG((EXTRACT(EPOCH FROM (r.verified_ts - s.received_ts))/60 <= a.tat_target_minutes)::int),2
) AS overall_result_sla_pct
FROM synth.results r
JOIN synth.specimens s USING (specimen_id)
JOIN synth.analytes  a USING (analyte_code);

-- Shift and Site (from views)
SELECT * FROM synth.sla_shift_v;
SELECT * FROM synth.sla_site_v;

-- Percentiles by analyte (p50/p90/p95 vs SLA)
WITH m AS (
  SELECT analyte_code,
         EXTRACT(EPOCH FROM (r.verified_ts - s.received_ts))/60 AS tat_min,
         a.tat_target_minutes AS sla_min
  FROM synth.results r
  JOIN synth.specimens s USING (specimen_id)
  JOIN synth.analytes  a USING (analyte_code)
)
SELECT analyte_code,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY tat_min)::numeric,1) AS p50,
       ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY tat_min)::numeric,1) AS p90,
       ROUND(PERCENTILE_CONT(0.95)WITHIN GROUP (ORDER BY tat_min)::numeric,1) AS p95,
       MAX(sla_min) AS sla_min
FROM m
GROUP BY analyte_code
ORDER BY analyte_code;

-- Pareto of misses (root-cause by analyte/shift)
WITH misses AS (
  SELECT analyte_code,
         CASE
           WHEN EXTRACT(HOUR FROM s.received_ts) BETWEEN 7 AND 14  THEN 'Day'
           WHEN EXTRACT(HOUR FROM s.received_ts) BETWEEN 15 AND 22 THEN 'Evening'
           ELSE 'Night'
         END AS shift,
         (EXTRACT(EPOCH FROM (r.verified_ts - s.received_ts))/60 <= a.tat_target_minutes) AS hit
  FROM synth.results r
  JOIN synth.specimens s USING (specimen_id)
  JOIN synth.analytes  a USING (analyte_code)
)
SELECT analyte_code, shift, COUNT(*) AS miss_ct,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (),2) AS pct_of_misses
FROM misses
WHERE NOT hit
GROUP BY analyte_code, shift
ORDER BY pct_of_misses DESC
LIMIT 10;

-- STAT vs ROUTINE performance
WITH m AS (
  SELECT s.priority,
         EXTRACT(EPOCH FROM (r.verified_ts - s.received_ts))/60 AS tat_min,
         a.tat_target_minutes AS sla_min
  FROM synth.results r
  JOIN synth.specimens s USING (specimen_id)
  JOIN synth.analytes  a USING (analyte_code)
)
SELECT priority,
       ROUND(AVG(tat_min),1) AS avg_tat,
       ROUND(100.0*AVG((tat_min <= sla_min)::int),2) AS sla_pct,
       COUNT(*) AS n
FROM m
GROUP BY priority
ORDER BY priority;

SELECT ROUND(100.0 * AVG(
  (EXTRACT(EPOCH FROM (r.verified_ts - s.received_ts))/60 <= a.tat_target_minutes)::int
),2) AS overall_result_sla_pct
FROM synth.results r
JOIN synth.specimens s USING (specimen_id)
JOIN synth.analytes  a USING (analyte_code);
