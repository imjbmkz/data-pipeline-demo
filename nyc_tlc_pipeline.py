"""Load NYC TLC data into DuckDB with dlt.

Resources:
  - taxi_zone_lookup   : zone id -> borough / zone / service zone (CSV)
  - taxi_zones         : zone polygons from the official shapefile (GeoJSON text)
  - yellow_tripdata    : Yellow Taxi trip records for the selected months (Parquet)

Usage:
    python nyc_tlc_pipeline.py                      # June-August 2026
    python nyc_tlc_pipeline.py --year 2025          # June-August 2025
    python nyc_tlc_pipeline.py --months 6 7         # only June and July
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import logging
import tempfile
import zipfile
from pathlib import Path
from typing import Iterator, Sequence

import dlt
import pyarrow as pa
import pyarrow.parquet as pq
import shapefile  # pyshp
from dlt.sources.helpers import requests

URL_TAXI_ZONE_LOOKUP_TABLE = "https://d37ci6vzurychx.cloudfront.net/misc/taxi_zone_lookup.csv"
URL_TAXI_ZONE_SHAPEFILE = "https://d37ci6vzurychx.cloudfront.net/misc/taxi_zones.zip"
URL_YELLOW_TAXI_TRIP_RECORDS = (
    "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_{year}-{month}.parquet"
)

DEFAULT_YEAR = 2026
DEFAULT_MONTHS = (6, 7, 8)  # June to August
PARQUET_BATCH_SIZE = 250_000

logger = logging.getLogger("nyc_tlc_pipeline")


@dlt.resource(name="taxi_zone_lookup", write_disposition="replace", primary_key="location_id")
def taxi_zone_lookup() -> Iterator[dict]:
    """Taxi zone lookup table (about 265 rows)."""
    response = requests.get(URL_TAXI_ZONE_LOOKUP_TABLE)
    response.raise_for_status()
    reader = csv.DictReader(io.StringIO(response.text))
    for row in reader:
        yield {
            "location_id": int(row["LocationID"]),
            "borough": row["Borough"],
            "zone": row["Zone"],
            "service_zone": row["service_zone"],
        }


@dlt.resource(name="taxi_zones", write_disposition="replace", primary_key="location_id")
def taxi_zones() -> Iterator[dict]:
    """Taxi zone polygons from the shapefile.

    Geometry is stored as GeoJSON text in the shapefile's native coordinate system
    (NAD83 / New York Long Island, EPSG:2263, in feet), not latitude/longitude.
    """
    response = requests.get(URL_TAXI_ZONE_SHAPEFILE)
    response.raise_for_status()

    with tempfile.TemporaryDirectory() as tmp_dir:
        with zipfile.ZipFile(io.BytesIO(response.content)) as archive:
            archive.extractall(tmp_dir)
        shp_files = list(Path(tmp_dir).rglob("*.shp"))
        if not shp_files:
            raise FileNotFoundError("No .shp file found in the taxi zones archive")

        with shapefile.Reader(str(shp_files[0])) as reader:
            for record in reader.iterShapeRecords():
                attrs = record.record.as_dict()
                yield {
                    "location_id": int(attrs["LocationID"]),
                    "object_id": int(attrs["OBJECTID"]),
                    "zone": attrs["zone"],
                    "borough": attrs["borough"],
                    "shape_length": float(attrs["Shape_Leng"]),
                    "shape_area": float(attrs["Shape_Area"]),
                    "geometry_geojson": json.dumps(record.shape.__geo_interface__),
                    "crs": "EPSG:2263",
                }


def _download_to(url: str, target: Path) -> bool:
    """Stream a file to disk. Returns False if TLC hasn't published it (403/404)."""
    with requests.get(url, stream=True) as response:
        if response.status_code in (403, 404):
            return False
        response.raise_for_status()
        with open(target, "wb") as f:
            for chunk in response.iter_content(chunk_size=8 * 1024 * 1024):
                f.write(chunk)
    return True


@dlt.resource(name="yellow_tripdata", write_disposition="replace")
def yellow_tripdata(year: int, months: Sequence[int]) -> Iterator[pa.Table]:
    """Yellow Taxi trip records, streamed month by month as Arrow batches.

    Uses replace so that re-running the pipeline never duplicates trips.
    """
    for month in months:
        url = URL_YELLOW_TAXI_TRIP_RECORDS.format(year=year, month=f"{month:02d}")
        source_file = url.rsplit("/", 1)[-1]

        with tempfile.TemporaryDirectory() as tmp_dir:
            local_path = Path(tmp_dir) / source_file
            logger.info("Downloading %s", url)
            if not _download_to(url, local_path):
                logger.warning("Skipping %s: not published yet (or not found)", source_file)
                continue

            parquet_file = pq.ParquetFile(local_path)
            logger.info("Loading %s (%s rows)", source_file, parquet_file.metadata.num_rows)
            for batch in parquet_file.iter_batches(batch_size=PARQUET_BATCH_SIZE):
                table = pa.Table.from_batches([batch])
                yield table.append_column(
                    "source_file", pa.array([source_file] * table.num_rows, pa.string())
                )


@dlt.source(name="nyc_tlc")
def nyc_tlc_source(year: int = DEFAULT_YEAR, months: Sequence[int] = DEFAULT_MONTHS):
    return [
        taxi_zone_lookup(),
        taxi_zones(),
        yellow_tripdata(year=year, months=months),
    ]


def main() -> None:
    parser = argparse.ArgumentParser(description="Load NYC TLC Yellow Taxi data with dlt")
    parser.add_argument("--year", type=int, default=DEFAULT_YEAR)
    parser.add_argument("--months", type=int, nargs="+", default=list(DEFAULT_MONTHS))
    parser.add_argument("--destination", default="duckdb", help="Any dlt destination name")
    parser.add_argument("--dataset", default="nyc_tlc")
    args = parser.parse_args()

    if any(m < 1 or m > 12 for m in args.months):
        parser.error("--months must be between 1 and 12")

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

    pipeline = dlt.pipeline(
        pipeline_name="nyc_tlc",
        destination=args.destination,
        dataset_name=args.dataset,
        progress="log",
    )
    load_info = pipeline.run(nyc_tlc_source(year=args.year, months=args.months))
    print(load_info)
    print(pipeline.last_trace.last_normalize_info)


if __name__ == "__main__":
    main()
