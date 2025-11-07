WITH m AS (
  SELECT
    CASE
      WHEN EXTRACT(HOUR FROM s.received_ts) BETWEEN 7 AND 14  THEN 'Day'
      WHEN EXTRACT(HOUR FROM s.received_ts) BETWEEN 15 AND 22 THEN 'Evening'
      ELSE 'Night'
    END AS shift,
    a.analyte_code,
    EXTRACT(EPOCH FROM (r.verified_ts - s.received_ts))/60 AS tat_min,
    a.tat_target_minutes AS sla_min
  FROM synth.results r
  JOIN synth.specimens s USING (specimen_id)
  JOIN synth.analytes  a USING (analyte_code)
)
SELECT
  analyte_code,
  shift,
  ROUND(AVG(tat_min),1)                           AS avg_tat_min,
  ROUND(100.0 * AVG((tat_min <= sla_min)::int),2) AS sla_hit_pct,
  COUNT(*)                                        AS n
FROM m
GROUP BY analyte_code, shift
ORDER BY analyte_code, shift;
