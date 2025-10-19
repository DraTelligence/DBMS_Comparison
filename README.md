# DBMS Comparison: openGauss vs PostgreSQL (NYC Yellow Taxi 2019‑07)

> **Goal**  
> Compare openGauss and PostgreSQL under *aligned* settings using a shared NYC Yellow Taxi dataset, measuring
> - 3 `SELECT` workloads (aggregation, global sort Top‑K, grouped Top‑K), and
> - 3 `UPDATE` workloads (small‑range, mid‑range, sandbox “near full‑table”),
> across **cold/hot** runs and two profiles: **default** and **parity** (aligned `work_mem`).
>
> Results are captured as minimal, reviewable logs (timings, counts, affected rows) plus **execution plans**.

---

## Contents

- [Ethics & AI‑Assistance Disclosure](#ethics--ai-assistance-disclosure)
- [Repository Layout](#repository-layout)
- [Prerequisites](#prerequisites)
- [Dataset & Schema](#dataset--schema)
- [Secrets & Safety (do NOT leak passwords)](#secrets--safety-do-not-leak-passwords)
  - [.gitignore](#gitignore)
  - [Environment variables (`.env.sample`)](#environment-variables-envsample)
  - [Automatic redaction on commit (no local deletion)](#automatic-redaction-on-commit-no-local-deletion)
  - [Preventive scanners (block accidental commits)](#preventive-scanners-block-accidental-commits)
  - [If secrets were already committed](#if-secrets-were-already-committed)
- [Running the benchmarks](#running-the-benchmarks)
- [Outputs & Metrics](#outputs--metrics)
- [Why EXPLAIN / EXPLAIN (ANALYZE)?](#why-explain--explain-analyze)
- [Reproducibility checklist](#reproducibility-checklist)
- [Appendix: drop‑in files & hooks](#appendix-drop-in-files--hooks)

---

## Ethics & AI‑Assistance Disclosure

This project used an AI assistant (ChatGPT, *GPT‑5 Thinking*) for **scaffolding scripts**, **formatting SQL**, **writing documentation**, and **troubleshooting**.  
All experiments, parameters, and results were **designed, executed, and verified by the author(s)**.  
The AI tool did **not** generate or alter the empirical results; those are produced by the provided scripts and recorded logs.  
Citations, configuration choices, and conclusions are ultimately the responsibility of the author(s).

---

## Repository Layout

```
project-root/
├─ db/
│  ├─ bench_default.sql               # minimal-output SELECT+UPDATE with timings
│  ├─ bench_parity.sql                # same as above, aligned work_mem (via :wm)
│  ├─ bench_explain_default.sql       # EXPLAIN (ANALYZE) for SELECT / U1 / U2; safe U3
│  ├─ bench_explain_parity.sql
│  ├─ schema_all.sql                  # table & indexes for yellow_trips
│  └─ …                               # any PG-specific files you maintain
├─ scripts/
│  ├─ og/                             # openGauss runners (cold/hot; stderr merged)
│  │  ├─ bench_default.ps1
│  │  ├─ bench_parity.ps1
│  │  ├─ explain_default.ps1
│  │  └─ explain_parity.ps1
│  ├─ pg/                             # PostgreSQL runners (your versions)
│  │  ├─ bench_default.ps1
│  │  ├─ bench_parity.ps1
│  │  ├─ explain_default.ps1
│  │  └─ explain_parity.ps1
│  ├─ extract_metrics.ps1             # parse logs → results/metrics.csv
│  ├─ run_all.ps1                     # orchestrates all steps (sequential)
│  └─ git-filters/
│     └─ redact-secrets.ps1           # (optional) clean-filter to redact secrets
├─ results/                           # generated logs & metrics (ignored by git)
├─ data/                              # raw CSVs (ignored by git)
├─ .env.sample                        # env-var template (no secrets)
├─ .gitattributes                     # (optional) attach clean-filter
├─ .gitignore
└─ README.md
```

---

## Prerequisites

- **Windows + PowerShell** (WinPS 5.1 or PowerShell 7)
- **Docker** (used to run `psql/pg_isready` clients)
- Reachable DB instances:
  - openGauss (e.g., container name `opengauss`, port `8888`)
  - PostgreSQL (e.g., container name `pg18`, port `5433`)
- Adequate resources (e.g., 4 vCPU, 8 GB RAM) for cold/hot cycles

---

## Dataset & Schema

- NYC Yellow Taxi: `yellow_tripdata_2019-07.csv` (~650 MB)
- Load into both DBs as **`yellow_trips`** using `db/schema_all.sql`
- Create indexes:
  - `idx_pickup_time ON yellow_trips(tpep_pickup_datetime)`
  - `idx_pulocation  ON yellow_trips(pulocationid)`

*Note:* UPDATE workloads U1/U2 modify **non-indexed** monetary columns and ROLLBACK; U3 updates a **sandbox table** and COMMITs, then drops it—so the main table stays pristine.

---

## Secrets & Safety (do NOT leak passwords)

### `.gitignore`

Add at repo root (sample below also in [Appendix](#appendix-drop-in-files--hooks)):

```gitignore
# OS/IDE
.DS_Store
Thumbs.db
.vscode/
.idea/

# Local artifacts
data/
results/
.env
*.env
*.log
*.bak

# Archives/large
*.zip
*.7z
*.tar
*.gz
*.csv
*.parquet
```

### Environment variables (`.env.sample`)

Do **not** hardcode passwords in scripts. Use env vars:

- `OGPASS` – openGauss password
- `PGPASS` – PostgreSQL password

PowerShell (current session only):
```powershell
$env:OGPASS = "********"
$env:PGPASS = "********"
```

You may keep a local **`.env`** (ignored by git) for convenience; **never commit it**.

### Automatic redaction on commit (no local deletion)

If you *must* keep credentials inside certain tracked files locally but want them **redacted when committed**, use a **Git clean-filter**:

1) **Create filter script**: `scripts/git-filters/redact-secrets.ps1`
   ```powershell
   #! /usr/bin/env pwsh
   # Reads STDIN, writes redacted text to STDOUT
   $text = [Console]::In.ReadToEnd()

   # Basic patterns – extend as needed
   $patterns = @(
     'OGPASS\s*=\s*["'']?[^"''\r\n]+["'']?',          # OGPASS=...
     'PGPASS\s*=\s*["'']?[^"''\r\n]+["'']?',          # PGPASS=...
     'postgres:\/\/[^:\s]+:[^@\s]+@',                 # postgres://user:pass@
     'Opengauss@[^"\s]+'                              # example hardcoded token
   )

   foreach ($p in $patterns) {
     $text = [Regex]::Replace($text, $p, { param($m) 
       # replace only the secret part, keep key/structure readable
       if ($m.Value -match '^(OGPASS|PGPASS)'){
         $key = $matches[1]; return "$key=<REDACTED>"
       } else {
         return '<REDACTED>'
       }
     }, 'IgnoreCase, CultureInvariant')
   }

   [Console]::Out.Write($text)
   ```

2) **Register filter** in `.git/config` (local repo only):
   ```ini
   [filter "redact-secrets"]
     clean = pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/git-filters/redact-secrets.ps1
     smudge = cat
   ```

3) **Attach filter to selected files** via `.gitattributes`:
   ```
   # Only redact where secrets might appear
   scripts/**/*.ps1    filter=redact-secrets
   db/**/*.sql         filter=redact-secrets
   ```
   > Working tree keeps your real content. On commit, Git stores **redacted blobs**.

**Limitations:** regex‑based redaction is best‑effort. Prefer env vars + `.gitignore` whenever possible.

### Preventive scanners (block accidental commits)

Use a pre‑commit framework to **stop** commits containing secrets:

- **`pre-commit`** + `detect-secrets`:
  ```yaml
  # .pre-commit-config.yaml
  repos:
    - repo: https://github.com/Yelp/detect-secrets
      rev: v1.5.0
      hooks:
        - id: detect-secrets
          args: ['--baseline', '.secrets.baseline']
  ```
  Then:
  ```bash
  pre-commit install
  detect-secrets scan > .secrets.baseline
  ```

- **`git-secrets`** (AWS tool) also works (`git secrets --install` then add patterns).

### If secrets were already committed

Rewrite history and rotate the credential:

```bash
pip install git-filter-repo
# create replace rules:
cat > replace.txt <<'EOF'
literal: your-old-password-here
replacement: <REDACTED>
EOF

git filter-repo --replace-text replace.txt
git push --force --all
git push --force --tags
```

Then **change the password** at the source system.

---

## Running the benchmarks

**One‑stop orchestration** (sequential; unified cold/hot counts):  
```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force

.\scripts\run_all.ps1 `
  -ProjectRoot "E:\workSpace\files\project\dbms_comparison" `
  -ColdRuns 5 -HotRuns 5 `
  -RunOG:$true -RunPG:$true `
  -OGContainer "opengauss" -PGContainer "pg18" `
  -OGWorkMem "64MB" -PGWorkMem "64MB"
```

Notes:
- Runners wait for DB readiness after container restarts (`pg_isready` loop).
- Logs are written to `results/**/.../*.txt` with **stderr merged** so `Time: … ms` is preserved.

---

## Outputs & Metrics

Each run log contains:
- `=== WORK_MEM (...) ===` then one line like `64MB`
- `=== DATASET_SIZE (yellow_trips) ===` then a row count
- Sections `Q1/Q2/Q3` and `U1/U2/U3` with **`Time: … ms`** and minimal numbers (`COUNT(*)`, `UPDATE n`)
- No large result sets

Aggregate to CSV:
```powershell
.\scripts\extract_metrics.ps1 -ResultsRoot ".\results"
```
Creates `results/metrics.csv` with columns like:
```
db,profile,cache,run,ts,work_mem,dataset_rows,
q1_ms,q2_ms,q3_ms,
u1_target,u1_update_rows,u1_update_ms,
u2_target,u2_update_rows,u2_update_ms,
u3_sandbox_rows,u3_ctas_rows,u3_ctas_ms,u3_update_rows,u3_update_ms
```

---

## Why EXPLAIN / EXPLAIN (ANALYZE)?

- **EXPLAIN** shows the *planned* path (scan types, joins, cost estimates, rows, width).
- **EXPLAIN (ANALYZE, BUFFERS)** executes the query and reports **actual** timings, row counts, and IO buffer hits/reads/writes, revealing:
  - Index vs sequential scans; external sort/aggregate spills; WAL/write amplification for UPDATEs; parallelism; etc.
- We:
  - Use `(ANALYZE)` for **SELECTs** and **U1/U2** (inside a transaction with `ROLLBACK`).
  - For **U3**, only plan the **main table** (no analyze); run `(ANALYZE)` on a **sandbox table** slice to avoid heavy write‑amp on the main data.

---

## Appendix: drop‑in files & hooks

### `.gitignore` (drop‑in)

```gitignore
# OS/IDE
.DS_Store
Thumbs.db
.vscode/
.idea/

# Local artifacts
data/
results/
.env
*.env
*.log
*.bak

# Archives/large
*.zip
*.7z
*.tar
*.gz
*.csv
*.parquet
```

### `.env.sample` (drop‑in)

```dotenv
# Copy to .env (kept locally; ignored by git)
OGPASS=
PGPASS=
```

### `.gitattributes` (attach redaction filter to chosen paths)

```
scripts/**/*.ps1    filter=redact-secrets
db/**/*.sql         filter=redact-secrets
```

### `scripts/git-filters/redact-secrets.ps1` (drop‑in)

```powershell
#! /usr/bin/env pwsh
$text = [Console]::In.ReadToEnd()
$patterns = @(
  'OGPASS\s*=\s*["'']?[^"''\r\n]+["'']?',
  'PGPASS\s*=\s*["'']?[^"''\r\n]+["'']?',
  'postgres:\/\/[^:\s]+:[^@\s]+@',
  'Opengauss@[^"\s]+'
)
foreach ($p in $patterns) {
  $text = [Regex]::Replace($text, $p, { param($m)
    if ($m.Value -match '^(OGPASS|PGPASS)') {
      $key = $matches[1]; return "$key=<REDACTED>"
    } else {
      return '<REDACTED>'
    }
  }, 'IgnoreCase, CultureInvariant')
}
[Console]::Out.Write($text)
```

### `.git/config` snippet (local, registers the clean filter)

```ini
[filter "redact-secrets"]
  clean = pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/git-filters/redact-secrets.ps1
  smudge = cat
```

> After adding `.gitattributes` and the filter, **re‑add** files so Git stores redacted blobs:
> ```bash
> git rm --cached -r .
> git add .
> git commit -m "apply redaction clean-filter"
> ```

---

*Questions or suggestions?* Open an issue or discussion in the repo.

---

This README.md is completely generated by gpt, though author have briefly checked it. Contact if spot any problems :D