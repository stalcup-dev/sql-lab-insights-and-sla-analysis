BEGIN;

DROP SCHEMA IF EXISTS synth CASCADE;
CREATE SCHEMA synth;

CREATE TABLE synth.analytes (
  analyte_code TEXT PRIMARY KEY,
  analyte_name TEXT NOT NULL,
  bench        TEXT NOT NULL CHECK (bench IN ('chem','heme','coag')),
  tat_target_minutes INT NOT NULL CHECK (tat_target_minutes > 0)
);

CREATE TABLE synth.specimens (
  specimen_id   BIGSERIAL PRIMARY KEY,
  patient_id    TEXT NOT NULL,
  collected_ts  TIMESTAMPTZ NOT NULL,
  received_ts   TIMESTAMPTZ NOT NULL,
  reported_ts   TIMESTAMPTZ NOT NULL,
  source_site   TEXT NOT NULL,
  priority      TEXT NOT NULL CHECK (priority IN ('STAT','ROUTINE')),
  CHECK (received_ts >= collected_ts),
  CHECK (reported_ts >= received_ts)
);

CREATE TABLE synth.results (
  result_id     BIGSERIAL PRIMARY KEY,
  specimen_id   BIGINT NOT NULL REFERENCES synth.specimens(specimen_id),
  analyte_code  TEXT   NOT NULL REFERENCES synth.analytes(analyte_code),
  result_value  NUMERIC,
  result_unit   TEXT,
  abnormal_flag CHAR(1) CHECK (abnormal_flag IN ('N','L','H')),
  verified_ts   TIMESTAMPTZ NOT NULL
);

CREATE TABLE synth.qc_events (
  qc_id     BIGSERIAL PRIMARY KEY,
  event_ts  TIMESTAMPTZ NOT NULL,
  bench     TEXT NOT NULL CHECK (bench IN ('chem','heme','coag')),
  severity  TEXT NOT NULL CHECK (severity IN ('info','warn','fail')),
  analyte_code TEXT REFERENCES synth.analytes(analyte_code)
);

-- Helpful indexes for analysis performance
CREATE INDEX IF NOT EXISTS idx_spec_received ON synth.specimens(received_ts);
CREATE INDEX IF NOT EXISTS idx_res_spec     ON synth.results(specimen_id);
CREATE INDEX IF NOT EXISTS idx_res_anl_time ON synth.results(analyte_code, verified_ts);
CREATE INDEX IF NOT EXISTS idx_qc_bench_time ON synth.qc_events(bench, event_ts);

COMMIT;
