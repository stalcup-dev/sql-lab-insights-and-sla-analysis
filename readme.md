Lab Ops SQL — SLA, QC Impact, and Intake Dynamics

What this shows: A production-style SQL analysis of a reference lab that standardizes SLA math, quantifies QC failure impact on TAT, and surfaces rolling 6-hour intake spikes. It’s reproducible (views + notebook), clear (focused visuals), and actionable (operations recommendations).

SLA definition (Result-level):
SLA % = 100 × AVG( (verified_ts − received_ts) ≤ analyte.tat_target_minutes )

TL;DR (executive highlights)

Shift SLA: Night ≈ 100.0%, Evening ≈ 99.1%, Day ≈ 91.8% → Day is the bottleneck during peak intake.

Site SLA: Clinics ≈ 98–100%; ED ≈ 93.9% → ED drags average; mix + intake timing likely drivers.

QC proximity: Avg TAT 34.6 min (normal) vs 73.8 min (near QC fail) → +39.2 min / +113%.

Percentiles vs SLA: p95 for A1C/CMP/LIPID/CBC/PTINR sits below their targets; Day-shift CBC/PTINR shows the weakest margin.

Numbers reflect the current synthetic seed; your run may vary slightly.

Visuals (generated)
<div align="center"> <img src="visuals/fig_sla_by_shift.png" width="48%" alt="SLA by Shift"> <img src="visuals/fig_sla_by_site.png" width="48%" alt="SLA by Site"> <br/> <img src="visuals/fig_qc_fail_impact.png" width="48%" alt="QC Impact on TAT"> <img src="visuals/fig_rolling_6hr.png" width="48%" alt="Rolling 6-hr Intake"> <br/> <img src="visuals/fig_sla_heatmap.png" width="70%" alt="SLA Heatmap by Analyte × Shift"> </div>

Quick reads

SLA by Shift: Day underperforms; Evening/Night are stable and near-perfect.

SLA by Site: ED is the outlier; clinics are consistently high.

QC Impact: Being within ±60m of a QC fail more than doubles TAT.

Rolling Intake: Volume is heavily afternoon → evening, stressing Day close and early Evening start.

Heatmap: CBC/PTINR on Day is the weakest SLA cell—precisely where volume peaks.

The goal

Standardize SLA math across analytes, sites, and shifts.

Quantify bottlenecks (QC, intake patterns, Day-shift congestion).

Make it reproducible via canonical SQL views + a single notebook.

This is exactly the kind of work a Data Analyst does for lab operations, quality, and throughput.

How it’s built

Dataset: ~30 days of synthetic operations; 5 analytes (A1C, CBC, CMP, LIPID, PTINR), 6 sites (ClinicA–E, ED), 3 shifts (Day/Evening/Night). Intake timing is realistic (afternoon-heavy).

SLA math: result-level verified_ts − received_ts in minutes vs analyte SLA target.
QC impact: flag if a QC fail occurred on the same bench within 60 min before the result.
Rolling intake: 6-hour rolling sum from hourly counts.

SQL spotlight (core queries)

1) SLA by Shift (Result-level)

WITH m AS (
  SELECT
    CASE
      WHEN EXTRACT(HOUR FROM s.received_ts) BETWEEN 7 AND 14  THEN 'Day'
      WHEN EXTRACT(HOUR FROM s.received_ts) BETWEEN 15 AND 22 THEN 'Evening'
      ELSE 'Night'
    END AS shift,
    EXTRACT(EPOCH FROM (r.verified_ts - s.received_ts))/60 AS tat_min,
    a.tat_target_minutes AS sla_min
  FROM synth.results  r
  JOIN synth.specimens s USING (specimen_id)
  JOIN synth.analytes  a USING (analyte_code)
)
SELECT
  shift,
  ROUND(AVG(tat_min), 1)                           AS avg_tat_min,
  ROUND(100.0 * AVG((tat_min <= sla_min)::int), 2) AS sla_hit_pct,
  COUNT(*)                                         AS n
FROM m
GROUP BY shift
ORDER BY sla_hit_pct DESC;


2) QC Fail proximity impact

WITH j AS (
  SELECT a.bench,
         EXTRACT(EPOCH FROM (r.verified_ts - s.received_ts))/60 AS tat_min,
         EXISTS (
           SELECT 1
           FROM synth.qc_events q
           WHERE q.bench = a.bench
             AND q.severity = 'fail'
             AND q.event_ts BETWEEN r.verified_ts - INTERVAL '60 minutes' AND r.verified_ts
         ) AS near_fail
  FROM synth.results r
  JOIN synth.specimens s USING (specimen_id)
  JOIN synth.analytes  a USING (analyte_code)
)
SELECT near_fail, ROUND(AVG(tat_min),1) AS avg_tat, COUNT(*) AS n
FROM j
GROUP BY near_fail
ORDER BY near_fail;


3) Rolling 6-hour intake

WITH timeline AS (
  SELECT generate_series(
           date_trunc('hour', MIN(received_ts)),
           date_trunc('hour', MAX(received_ts)),
           interval '1 hour') AS hr
  FROM synth.specimens
),
counts AS (
  SELECT t.hr, COUNT(*) AS received_count
  FROM timeline t
  JOIN synth.specimens s
    ON s.received_ts >= t.hr AND s.received_ts < t.hr + interval '1 hour'
  GROUP BY t.hr
)
SELECT hr,
       received_count,
       SUM(received_count) OVER (ORDER BY hr ROWS BETWEEN 5 PRECEDING AND CURRENT ROW)
         AS rolling_6hr_total
FROM counts
ORDER BY hr;


(Canonical views like synth.sla_shift_v and synth.sla_site_v are included for clean reuse.)

Insights → Actions

Where the system leaks

Day shift is the constraint: lowest SLA and highest intake pressure.

ED erodes site-level SLA: likely specimen mix, arrival bursts, or transport timing.

QC events create a measurable TAT penalty (~+39 min, +113%).

What to do about it

Load-balancing: Move CBC/PTINR routine from Day to Evening/Night; pre-batch “easy wins” before Day peak.

QC scheduling: Avoid QC/maintenance near Day peak; add guardrails for QC windows vs. result verification.

ED pipeline: Stagger courier drops; add pre-accession or STAT lanes for ED during peak bands.

Automation: Where policy allows, expand auto-verification for low-risk analytes during Day.

Reproduce the analysis

Prereqs: PostgreSQL, Python, Jupyter

Install

pip install -r requirements.txt


Create DB + seed + views

psql -U postgres -d Lab -f sql/01_schema.sql
psql -U postgres -d Lab -f sql/02_seed_reference_lab.sql
psql -U postgres -d Lab -f sql/03_views_sla.sql
psql -U postgres -d Lab -f sql/04_calibrate_p95.sql


Configure env (never commit secrets)

# .env.example → copy to .env and set your values
PG_HOST=localhost
PG_PORT=5432
PG_DB=Lab
PG_USER=postgres
PG_PASSWORD=changeme


Run the notebook

notebooks/01_SLA_Analyst_Report.ipynb  → Run All


Outputs are saved to visuals/ and rendered inline in the notebook.

Project structure
lab-sql/
├─ README.md
├─ requirements.txt
├─ .gitignore
├─ .env.example
├─ notebooks/
│  └─ 01_SLA_Analyst_Report.ipynb
├─ sql/
│  ├─ 01_schema.sql
│  ├─ 02_seed_reference_lab.sql
│  ├─ 03_views_sla.sql
│  ├─ 04_calibrate_p95.sql
│  └─ sla_by_analyte_shift.sql
└─ visuals/
   ├─ fig_sla_by_shift.png
   ├─ fig_sla_by_site.png
   ├─ fig_qc_fail_impact.png
   ├─ fig_rolling_6hr.png
   └─ fig_sla_heatmap.png

Tech

PostgreSQL (window functions, percentiles, time bucketing)

Python + Jupyter (Matplotlib visuals, .env for DB config)

Reproducible views for standardized metrics

License

MIT

Notes

If you re-seed data, the visuals regenerate and numbers may vary slightly; insights and actions still hold.

All data are synthetic; no PHI, no real client information.