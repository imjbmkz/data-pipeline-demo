# Hands-on Activity: NYC Taxi Data Pipeline with dlt and dbt

Oct 16, 2026 · @Josh

## Overview

You will extend a working NYC taxi pipeline: add a new data source with dlt, add a quality check, add a dimension, build a new mart, and answer business questions with SQL. Plan for about **3–4 hours**.

The starting point is [imjbmkz/data-pipeline-demo](https://github.com/imjbmkz/data-pipeline-demo). It already loads June–August Yellow Taxi trips into DuckDB with dlt, splits trips into passed and failed with dbt, and builds a star schema (`fct_trips` plus dims) and a `daily_trip_summary` mart.

**You will practice:**

- Writing a dlt resource and loading Parquet files from a public URL
- Writing row-level data quality checks and reading their results
- Modelling a dimension and wiring it into a fact table
- Building an aggregate mart and protecting it with dbt tests
- Answering business questions from a star schema

**You need:**

- Python 3.10–3.13 (3.12 recommended), git, and a GitHub account
- Comfort with SQL `GROUP BY` and joins; basic Python
- About 3 GB of free disk space

## Setup

Get the baseline running before you change anything. Setup is done when `dbt build` finishes with no errors.

1. Fork the repo on GitHub, clone your fork, and create a branch named `activity/<your-name>`.
2. Create a Python 3.12 virtual environment and install the requirements:

```bash
python3.12 -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -U pip
pip install -r requirements.txt
```

3. Load the raw data with dlt. This downloads three months of trips and takes a few minutes:

```bash
python nyc_tlc_pipeline.py
```

4. Build and test the dbt project:

```bash
cd nyc_tlc_dbt
dbt build --profiles-dir .
```

5. Open the database with `duckdb ../nyc_tlc.duckdb` and run `SELECT * FROM quality.dq_summary;` to see why trips failed. Type `.quit` before running dbt again, since DuckDB allows only one writer at a time.

Before starting the tasks, read `models/quality/trips_checked.sql` and `models/marts/fct_trips.sql`. Every task builds on patterns in those two files.

## Tasks

There are five tasks worth 20 points each, for 100 in total. Do them in order, because later tasks use earlier ones. Commit after each task.

| Task | Skill | Points |
| --- | --- | --- |
| 1. Load Green Taxi trips | dlt | 20 |
| 2. Add a quality check | Data quality | 20 |
| 3. Add a time-of-day dimension | Dimensional modelling | 20 |
| 4. Build a zone-by-day mart | dbt marts and tests | 20 |
| 5. Answer business questions | SQL analysis | 20 |

### Task 1 — Load Green Taxi trips (dlt)

Add a `green_tripdata` resource to `nyc_tlc_pipeline.py` that loads the same months as the yellow trips.

- The file URL is `https://d37ci6vzurychx.cloudfront.net/trip-data/green_tripdata_{year}-{month}.parquet`.
- Reuse the download and batching logic; don't copy-paste it. Factor out a helper that takes the URL pattern.
- Add the `source_file` column, and skip months that aren't published, just like the yellow resource.

**Done when** `nyc_tlc_data.green_tripdata` exists and has rows for all three months. Note that green trips use `lpep_` timestamps, not `tpep_`.

### Task 2 — Add a quality check (data quality)

Add a check named `tip_exceeds_fare` to `trips_checked.sql`. A trip fails it when `tip_amount` is greater than `fare_amount` × a ratio.

- Make the ratio a dbt var called `max_tip_to_fare_ratio`, with a default of `1.0`, in `dbt_project.yml`.
- Add the check to the `checks` list so it shows up in `dq_failure_reasons` and `dq_summary`.
- Write a singular test in `tests/` that fails if any row in `trips_passed` breaks the rule.

**Done when** `dq_summary` lists `tip_exceeds_fare` and `dbt build` passes. Rerun with `--vars '{max_tip_to_fare_ratio: 0.5}'` and note how the failure count changes.

### Task 3 — Add a time-of-day dimension (modelling)

Create `marts/dim_time_of_day.sql` with one row per hour, 0 to 23, and these columns:

| Column | Example |
| --- | --- |
| `hour_key` | `8` |
| `hour_label` | `08:00–08:59` |
| `time_band` | `Morning rush` |
| `is_rush_hour` | `true` |

Use these bands: Overnight (0–5), Morning rush (6–9), Midday (10–15), Evening rush (16–19), Night (20–23). Then add `pickup_hour_key` to `fct_trips`.

**Done when** `dim_time_of_day` has 24 rows, and `fct_trips.pickup_hour_key` has `not_null` and `relationships` tests that pass.

### Task 4 — Build a zone-by-day mart (dbt)

Create `marts/zone_daily_summary.sql` with one row per pickup date and pickup zone. It needs these columns:

- `date_key`, `date_day`, `location_id`, `zone_name`, `borough`
- `total_trips`, `total_revenue`, `avg_distance_miles`, `card_tip_pct_of_fare`

Build it from `fct_trips` and the dims, the same way `daily_trip_summary` is built.

**Done when** these tests pass:

- A test proving that each (`date_key`, `location_id`) pair appears only once
- A reconciliation test: for every day, `SUM(total_trips)` across zones equals `daily_trip_summary.total_trips`

### Task 5 — Answer business questions (SQL)

Write each query and its result in a file named `ANSWERS.md` at the repo root.

1. Which day of the week has the most trips on average per day?
2. What is the average card tip as a % of fare on weekends compared with weekdays?
3. Which time band from Task 3 has the longest average trip duration?
4. What are the top 5 pickup zones by revenue in August? Use Task 4's mart.
5. What % of trips failed quality checks each month, and what were the top 3 failure reasons?
6. How many green trips and how many yellow trips were there each month? Use Task 1's table.

**Done when** each answer has its SQL, the result (a small table is fine), and one sentence interpreting it.

### Stretch goals (optional, no points)

- Stage and quality-check green trips in dbt. Then union them with yellow trips into one `fct_trips` with a `taxi_type` column.
- Change the dlt load from `replace` to loading only months that haven't been loaded yet.
- Add a GitHub Actions workflow that runs `dbt build` against a small one-month sample.

## Deliverables

Submit one pull request from your `activity/<your-name>` branch to your fork's `main`, and share its link. Check off each item before you submit:

- [ ] `green_tripdata` resource added; the dlt run prints rows for June, July and August
- [ ] `tip_exceeds_fare` check, the `max_tip_to_fare_ratio` var and a singular test added
- [ ] `dim_time_of_day` built, and `pickup_hour_key` added to `fct_trips` with tests
- [ ] `zone_daily_summary` built, with uniqueness and reconciliation tests
- [ ] `ANSWERS.md` with the SQL, result and a one-line interpretation for all six questions
- [ ] `dbt build --profiles-dir .` passes with no errors (paste the last lines of its output in the PR description)
- [ ] One commit per task, each with a clear message

**Scoring:** each task is worth 20 points. Within a task, 10 points are for working code, 5 for tests, and 5 for clarity (naming, comments, and commit message).

## Hints and reviewer notes

Try each task on your own first and use a hint only when you're stuck. Reviewers can use the "What to check" column to grade.

| Task | Hint | What to check |
| --- | --- | --- |
| 1 | Turn `yellow_tripdata` into a function that takes a URL pattern, then register two resources with `dlt.resource(..., name="green_tripdata")`. | No duplicated download code; missing months are skipped with a warning; the run is still `replace`, so it's safe to rerun. |
| 2 | Follow the pattern of the existing checks: `coalesce(trips.tip_amount > trips.fare_amount * {{ var('max_tip_to_fare_ratio') }}, false)`. | The check name is in the `checks` list; the var has a default; the singular test reads `trips_passed`, not `trips_checked`. |
| 3 | `SELECT range AS hour_key FROM range(24)` gives 0–23. Use `hour(pickup_at)` in `fct_trips`. | 24 rows; the bands match the spec exactly; the new key has `relationships` to the dim. |
| 4 | For uniqueness without packages, add `date_key * 1000 + location_id AS date_zone_key` and test it `unique`. Reconcile with a `GROUP BY date_key` joined to `daily_trip_summary`, returning rows where totals differ. | Joins go through dims, not raw tables; both tests exist and pass. |
| 5 | Average trips per weekday means: count trips per date first, then average those daily counts by `day_name`. Q5 reads `quality.dq_summary`; Q6 reads `nyc_tlc_data.green_tripdata`. | Q1 averages daily counts instead of taking raw totals; Q2 uses card trips only; each answer has a one-line interpretation. |

**Common mistakes to watch for:**

- Running dbt while a `duckdb` session has the file open, which causes a lock error. Run `.quit` first.
- Grouping Q1 by `day_name` over raw trips. A month can have five Fridays and four Mondays, which skews the totals.
- Counting tips on cash trips. Cash tips aren't recorded, so they pull the tip % down.
- Copying the yellow resource for green instead of reusing it. This works, but loses the clarity points.
