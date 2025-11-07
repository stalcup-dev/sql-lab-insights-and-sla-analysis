-- No clock skew
SELECT
  SUM((received_ts < collected_ts)::int) AS bad_received,
  SUM((reported_ts < received_ts)::int)  AS bad_reported
FROM synth.specimens;

-- Evening receipts ≈ 75%
SELECT ROUND(100.0 * AVG((EXTRACT(HOUR FROM received_ts) BETWEEN 16 AND 23)::int),2) AS pct_evening_receipts
FROM synth.specimens;

-- QC proximity share in 60m window (sanity ~5–15%)
WITH j AS (
  SELECT EXISTS (
         SELECT 1 FROM synth.qc_events q
         JOIN synth.analytes a2 ON a2.analyte_code=r.analyte_code
         WHERE q.bench=a2.bench AND q.severity='fail'
           AND q.event_ts BETWEEN r.verified_ts - interval '60 min' AND r.verified_ts
       ) AS near_fail
  FROM synth.results r
)
SELECT ROUND(100.0 * AVG(near_fail::int),2) AS pct_results_near_fail FROM j;

SELECT COUNT(*) bad_rows
FROM synth.results r JOIN synth.specimens s USING (specimen_id)
WHERE r.verified_ts < s.received_ts;

WITH m AS (
  SELECT a.analyte_code,
         AVG((EXTRACT(EPOCH FROM (r.verified_ts - s.received_ts))/60 <= a.tat_target_minutes)::int) AS hit
  FROM synth.results r JOIN synth.specimens s USING (specimen_id) JOIN synth.analytes a USING (analyte_code)
  GROUP BY a.analyte_code
)
SELECT * FROM m WHERE hit NOT BETWEEN 0.80 AND 0.99;
