BEGIN;

-- Reference analytes + SLAs
INSERT INTO synth.analytes VALUES
  ('CMP','Comprehensive Metabolic Panel','chem',45),
  ('LIPID','Lipid Panel','chem',60),
  ('A1C','Hemoglobin A1c','chem',90),
  ('CBC','Complete Blood Count','heme',30),
  ('PTINR','Prothrombin Time / INR','coag',25);

-- QC events: ~3 per bench per day; some 'fail'
INSERT INTO synth.qc_events (event_ts, bench, severity)
SELECT d + (i || ' hours')::interval + (floor(random()*60) || ' minutes')::interval,
       b,
       (ARRAY['info','info','info','warn','warn','fail'])[ceil(random()*6)]
FROM generate_series(date_trunc('day', now()) - interval '29 days',
                     date_trunc('day', now()),
                     interval '1 day') d,
     unnest(ARRAY['chem','heme','coag']) AS b,
     generate_series(9,21,6) AS i;

-- Volume + logistics: 5k specimens, 75% of receipts 16:00–23:59
WITH site_params(site, courier_min, is_hospital) AS (
  VALUES ('ClinicA',30,false),('ClinicB',45,false),('ClinicC',60,false),
         ('ClinicD',80,false),('ClinicE',90,false),('ED',15,true)
),
seed AS (
  SELECT
    gs AS row_id,
    date_trunc('day', now()) - interval '29 days'
      + (floor(random()*30) || ' days')::interval
      + ((CASE WHEN random()<0.75 THEN 8 + floor(random()*10) ELSE floor(random()*24) END) || ' hours')::interval
      + (floor(random()*60) || ' minutes')::interval                                AS collected_ts,
    (ARRAY['ClinicA','ClinicB','ClinicC','ClinicD','ClinicE','ED'])[1+floor(random()*6)] AS site,
    CASE WHEN random()<0.10 THEN 'STAT' ELSE 'ROUTINE' END AS priority
  FROM generate_series(1,5000) gs
),
spec_rows AS (
  SELECT
    encode(digest(row_id::text || clock_timestamp()::text,'sha1'),'hex') AS patient_id,
    s.collected_ts,
    CASE WHEN sp.is_hospital THEN
      s.collected_ts + ((sp.courier_min + floor(random()*10)) || ' minutes')::interval
    ELSE
      GREATEST(
        s.collected_ts + ((sp.courier_min + floor(random()*10)) || ' minutes')::interval,
        date_trunc('day', s.collected_ts) + interval '18 hours'
          + ((floor(random()*121)-60) || ' minutes')::interval
          + (sp.courier_min || ' minutes')::interval
      )
    END AS received_ts,
    s.site, s.priority
  FROM seed s
  JOIN site_params sp ON sp.site=s.site
),
ins_specs AS (
  INSERT INTO synth.specimens(patient_id, collected_ts, received_ts, reported_ts, source_site, priority)
  SELECT patient_id, collected_ts, received_ts, collected_ts + interval '1 minute', site, priority
  FROM spec_rows
  RETURNING specimen_id, received_ts, collected_ts, priority
),
result_plan AS (
  SELECT
    i.specimen_id, i.received_ts, i.priority,
    a.analyte_code, a.bench, a.tat_target_minutes,
    -- Processing factor tuned for ~90–96% result-level SLA before calibration
    (CASE WHEN a.analyte_code IN ('A1C','LIPID') THEN 0.40 + (random()*0.10) ELSE 0.60 + (random()*0.12) END)
    * (CASE
        WHEN (extract(hour from i.received_ts) >= 23 OR extract(hour from i.received_ts) <= 6) THEN 0.90
        WHEN extract(hour from i.received_ts) BETWEEN 15 AND 22 THEN 0.95
        ELSE 1.05 END)
    * (CASE WHEN extract(isodow from i.received_ts) IN (6,7) THEN 1.03 ELSE 1.00 END)
    * (CASE WHEN i.priority='STAT' THEN 0.50 ELSE 1.00 END) AS proc_factor,
    CASE WHEN a.analyte_code IN ('A1C','LIPID')
         THEN (60 - extract(minute from i.received_ts))::int % 60
         ELSE 0 END AS batch_wait_min
  FROM ins_specs i
  JOIN synth.analytes a ON random() < 0.48  -- ~2 results/specimen
),
result_times AS (
  SELECT specimen_id, analyte_code, bench,
         (tat_target_minutes * proc_factor) + batch_wait_min AS base_min,
         received_ts
  FROM result_plan
),
result_verified AS (
  SELECT
    rt.specimen_id, rt.analyte_code, rt.bench,
    CASE WHEN EXISTS (
           SELECT 1 FROM synth.qc_events q
           WHERE q.bench=rt.bench AND q.severity='fail'
             AND q.event_ts BETWEEN (rt.received_ts + (rt.base_min || ' minutes')::interval) - interval '60 min'
                                 AND (rt.received_ts + (rt.base_min || ' minutes')::interval)
         )
         THEN rt.received_ts + (rt.base_min || ' minutes')::interval
              + ((45 + floor(random()*31)) || ' minutes')::interval  -- +45–75 min
         ELSE rt.received_ts + (rt.base_min || ' minutes')::interval
    END AS verified_ts
  FROM result_times rt
)
INSERT INTO synth.results (specimen_id, analyte_code, result_value, result_unit, abnormal_flag, verified_ts)
SELECT specimen_id, analyte_code,
       50 + random()*50, 'mg/dL',
       (ARRAY['N','L','H'])[ceil(random()*3)],
       verified_ts
FROM result_verified;

-- reported_ts = max verified per specimen
UPDATE synth.specimens s
SET reported_ts = v.maxv
FROM (SELECT specimen_id, max(verified_ts) AS maxv FROM synth.results GROUP BY 1) v
WHERE s.specimen_id=v.specimen_id;

COMMIT;
