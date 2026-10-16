# data-pipeline-demo

A simple [dlt](https://dlthub.com) pipeline that loads NYC TLC data into DuckDB:

| Table | Source | Notes |
|---|---|---|
| `taxi_zone_lookup` | `taxi_zone_lookup.csv` | Zone ID → borough, zone, service zone |
| `taxi_zones` | `taxi_zones.zip` (shapefile) | Zone polygons as GeoJSON text, in EPSG:2263 (NY State Plane, feet) |
| `yellow_tripdata` | `yellow_tripdata_{year}-{month}.parquet` | Yellow Taxi trips, June–August by default, plus a `source_file` column |

All three tables use `replace`, so re-running the pipeline never duplicates rows.

## Run it

Use **Python 3.10–3.13**. dbt doesn't support newer Python yet, and pip would otherwise backtrack to ancient dbt releases that fail to build (`dbt-core-experimental-parser`).

```bash
python -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r requirements.txt

python nyc_tlc_pipeline.py                  # June–August 2026
python nyc_tlc_pipeline.py --year 2025      # June–August 2025
python nyc_tlc_pipeline.py --months 6 7     # pick months
```

Output lands in `nyc_tlc.duckdb`, dataset (schema) `nyc_tlc_data`. The dataset name must differ from the database file name, or DuckDB reports an ambiguous catalog/schema reference. Months the TLC hasn't published yet are skipped with a warning.

Trip files are streamed to disk and read in 250k-row Arrow batches, so a 3-month load stays light on memory.

## Query it

```bash
duckdb nyc_tlc.duckdb
```

```sql
SELECT z.borough, t.source_file, COUNT(*) AS trips, ROUND(AVG(t.total_amount), 2) AS avg_fare
FROM nyc_tlc_data.yellow_tripdata t
JOIN nyc_tlc_data.taxi_zone_lookup z ON t.pu_location_id = z.location_id
GROUP BY ALL
ORDER BY z.borough, t.source_file;
```

dlt normalizes column names to snake_case, so `VendorID` becomes `vendor_id` and `PULocationID` becomes `pu_location_id`.

## Other destinations

Pass any dlt destination, e.g. `--destination bigquery` or `--destination motherduck`, and put its credentials in `.dlt/secrets.toml`.

## Transform it with dbt

The `nyc_tlc_dbt/` project reads the tables dlt loaded into `nyc_tlc.duckdb` and builds four layers, each in its own schema:

| Schema | Models | Purpose |
|---|---|---|
| `staging` | `stg_yellow_tripdata`, `stg_taxi_zone_lookup`, `stg_taxi_zones` | Clean names and types; adds a hashed `trip_id` (views) |
| `quality` | `trips_checked`, `trips_passed`, `trips_failed`, `dq_summary` | Row-level quality checks and the passed/failed split |
| `marts` | `fct_trips`, `dim_zone`, `dim_date`, `dim_vendor`, `dim_payment_type`, `dim_rate_code`, `daily_trip_summary` | Star schema built from passed trips only, plus a daily summary |
| `reference` | `vendors`, `payment_types`, `rate_codes` (seeds) | Code lists from the TLC data dictionary |

Run it after the dlt pipeline has loaded data. Close any open DuckDB session on the file first, because DuckDB allows only one writer:

```bash
cd nyc_tlc_dbt
dbt build --profiles-dir .
```

`dbt build` loads the seeds, builds the models and runs the tests in dependency order. Set `NYC_TLC_DUCKDB_PATH` if your DuckDB file lives somewhere other than the repo root.

### Data quality

Quality is checked in two ways:

1. **Row-level checks** in `quality.trips_checked`. Each trip gets one `dq_fail_*` flag per check. Trips with no failures go to `trips_passed`; the rest go to `trips_failed`, with `dq_failure_reasons` listing every check they failed.

   | Check | A trip fails when |
   |---|---|
   | `duplicate_trip` | It is an exact copy of an earlier record (the first copy passes) |
   | `missing_timestamp` | Pickup or dropoff time is missing |
   | `pickup_outside_file_month` | Pickup is outside the month of its source file |
   | `non_positive_duration` | Dropoff is at or before pickup |
   | `excessive_duration` | Trip lasts more than 24 hours |
   | `invalid_trip_distance` | Distance is negative or over 200 miles |
   | `negative_amount` | Fare or total is negative |
   | `invalid_passenger_count` | Passenger count is 0 or over 9 (missing is allowed) |
   | `unknown_vendor` / `unknown_payment_type` / `unknown_rate_code` | Code is not in the data dictionary (a missing rate code is allowed) |
   | `unknown_pickup_zone` / `unknown_dropoff_zone` | Zone ID is missing or not in the zone lookup |

   The thresholds are `vars` in `dbt_project.yml`. `quality.dq_summary` shows how many trips failed each check per month.

2. **dbt tests** (`not_null`, `unique`, `accepted_values`, `relationships`, plus two singular tests in `tests/`):
   - Tests on raw and staging data only **warn**, since bad rows are expected there and are quarantined rather than stopping the build.
   - Tests on `trips_passed` and the marts **error**, because those tables should be clean.
   - `assert_every_trip_is_passed_or_failed` checks that no trip is lost or counted twice in the split.

### Example queries

```sql
-- Daily trip summary (one row per pickup day)
SELECT date_day, day_name, total_trips, avg_duration_minutes, total_revenue, card_tip_pct_of_fare
FROM marts.daily_trip_summary
ORDER BY date_day;

-- Why did trips fail?
SELECT * FROM quality.dq_summary;

-- Trips and revenue by pickup borough and weekday
SELECT z.borough, d.day_name, COUNT(*) AS trips, SUM(f.total_amount) AS revenue
FROM marts.fct_trips f
JOIN marts.dim_zone z ON f.pickup_location_id = z.location_id
JOIN marts.dim_date d ON f.pickup_date_key = d.date_key
GROUP BY ALL
ORDER BY z.borough, MIN(d.day_of_week);
```

`stg_yellow_tripdata` expects the `cbd_congestion_fee` column, which the TLC added in January 2025. If you load data from before 2025, remove that column from the staging model and `fct_trips`.
