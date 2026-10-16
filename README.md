# data-pipeline-demo

A simple [dlt](https://dlthub.com) pipeline that loads NYC TLC data into DuckDB:

| Table | Source | Notes |
|---|---|---|
| `taxi_zone_lookup` | `taxi_zone_lookup.csv` | Zone ID → borough, zone, service zone |
| `taxi_zones` | `taxi_zones.zip` (shapefile) | Zone polygons as GeoJSON text, in EPSG:2263 (NY State Plane, feet) |
| `yellow_tripdata` | `yellow_tripdata_{year}-{month}.parquet` | Yellow Taxi trips, June–August by default, plus a `source_file` column |

All three tables use `replace`, so re-running the pipeline never duplicates rows.

## Run it

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
