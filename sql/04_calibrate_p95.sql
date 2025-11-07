BEGIN;

-- Choose a per-analyte p95 target band (as a fraction of SLA)
-- For overall 87–96% result-level SLA, 0.90–0.96 works well.
WITH params AS (
  SELECT 0.90::double precision AS tgt_lo, 0.96::double precision AS tgt_hi
),
base AS (
  SELECT a.analyte_code,
         a.tat_target_minutes::double precision AS sla_min,
         percentile_cont(0.95) WITHIN GROUP (
           ORDER BY EXTRACT(EPOCH FROM (r.verified_ts - s.received_ts))/60
         )::double precision AS p95_min
  FROM synth.results r
  JOIN synth.specimens s USING (specimen_id)
  JOIN synth.analytes  a USING (analyte_code)
  GROUP BY a.analyte_code, a.tat_target_minutes
),
targets AS (
  SELECT b.analyte_code,
         b.sla_min,
         (b.sla_min * (SELECT tgt_lo FROM params)
          + b.sla_min * ((SELECT tgt_hi FROM params) - (SELECT tgt_lo FROM params)) * random()
         ) AS target_p95,
         p95_min
  FROM base b
),
scales AS (
  SELECT analyte_code,
         GREATEST(0.70, LEAST(1.30, target_p95 / NULLIF(p95_min,0)))::double precision AS scale_factor
  FROM targets
),
calc AS (
  SELECT r.result_id,
         s.received_ts + (r.verified_ts - s.received_ts) * sc.scale_factor AS new_verified_ts
  FROM synth.results   r
  JOIN synth.specimens s USING (specimen_id)
  JOIN scales          sc ON sc.analyte_code = r.analyte_code
)
UPDATE synth.results r
SET verified_ts = c.new_verified_ts
FROM calc c
WHERE r.result_id = c.result_id;

COMMIT;
