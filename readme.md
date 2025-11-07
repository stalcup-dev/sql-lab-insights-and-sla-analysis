# Lab Ops SQL — SLA, QC Impact & Intake Dynamics

A production-style SQL analysis for a reference lab that:
- standardizes SLA math,
- quantifies QC-fail proximity impact on TAT,
- surfaces rolling 6-hour intake spikes, and
- ships with reproducible views + a notebook.

### SLA (result level)
`SLA % = 100 × AVG( (verified_ts − received_ts) ≤ analyte.tat_target_minutes )`

---

## TL;DR (Key results)

| Slice | Finding |
|---|---|
| **Shift SLA** | **Night ~100.0%**, **Evening ~99.1%**, **Day ~91.8%** → Day is the bottleneck during peak intake. |
| **Site SLA** | Clinics ~98–100%; **ED ~93.9%** → ED drags average (mix + intake timing likely drivers). |
| **QC proximity** | Avg TAT **34.6 min** (normal) vs **73.8 min** (near QC fail) → **+39.2 min / +113%**. |
| **Percentiles vs SLA** | p95 for **A1C/CMP/LIPID/CBC/PTINR** sits below targets; **Day-shift CBC/PTINR** shows the weakest margin. |

> Numbers reflect a synthetic seed; reruns may vary slightly.

---

## Visuals

<table>
<tr>
<td><img src="visuals/fig_sla_by_shift.png" alt="SLA by Shift" width="100%"/></td>
<td><img src="visuals/fig_sla_by_site.png"  alt="SLA by Site"  width="100%"/></td>
</tr>
<tr>
<td><img src="visuals/fig_qc_fail_impact.png" alt="QC Impact on TAT" width="100%"/></td>
<td><img src="visuals/fig_rolling_6hr.png"   alt="Rolling 6-hr Intake" width="100%"/></td>
</tr>
<tr>
<td colspan="2" align="center"><img src="visuals/fig_sla_heatmap.png" alt="SLA Heatmap by Analyte × Shift" width="85%"/></td>
</tr>
</table>

### Quick reads
- **SLA by Shift**: Day underperforms; Evening/Night are near-perfect.  
- **SLA by Site**: **ED** is the outlier; clinics are consistently high.  
- **QC proximity**: Being within ±60m of a QC fail more than **doubles** TAT.  
- **Rolling intake**: Afternoon → evening surge stresses Day close + early Evening start.  
- **Heatmap**: **CBC/PTINR on Day** is the weakest SLA cell—exactly where volume peaks.

---

## Why this exists
- **Standardize** SLA math across analytes, sites, and shifts.  
- **Quantify** bottlenecks (QC, intake patterns, Day-shift congestion).  
- **Reproduce** via canonical SQL views + one notebook.  
- This is the kind of work a **Data Analyst** does for lab operations, quality, and throughput.

---

## Dataset & approach
- ~30 days synthetic ops; 5 analytes (A1C, CBC, CMP, LIPID, PTINR), 6 sites (ClinicA–E, ED), 3 shifts (Day/Evening/Night). Afternoon-heavy intake.
- **SLA math**: result-level `verified_ts − received_ts` (min) vs analyte SLA target.  
- **QC impact**: flag if a QC fail occurred on the same bench within 60m before result.  
- **Rolling intake**: 6-hour rolling sum from hourly counts.  
- Canonical views (e.g., `synth.sla_shift_v`, `synth.sla_site_v`) included for reuse.

---

## Insights → Actions

| Insight (where it leaks) | Action (what to do) |
|---|---|
| **Day shift** is the constraint: lowest SLA & highest intake pressure. | **Load-balance**: move routine **CBC/PTINR** to Evening/Night; pre-batch “easy wins” before Day peak. |
| **ED** erodes site SLA (mix + surges). | **Courier & lanes**: stagger ED drops; add pre-accession / STAT lanes during peak bands. |
| **QC proximity** adds ~**+39 min** avg TAT. | **QC scheduling**: avoid QC/maintenance near Day peak; guardrails for QC windows vs result windows. |
| Manual verification load during peaks. | **Automation**: expand auto-verify for low-risk analytes during Day (policy-permitting). |

---

## Run it

**Prereqs**: PostgreSQL, Python, Jupyter

```bash
pip install -r requirements.txt
