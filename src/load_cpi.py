"""Load annual average CPI-U into dasher.cpi_annual.

Source: BLS CPI-U, all items, U.S. city average, not seasonally adjusted,
1982-84 = 100 (series CUUR0000SA0), annual averages 1996-2024. The file is
data/raw/cpi_annual.csv with columns year,cpi_u. Record in the runbook where
the values came from. 2025 is left out: BLS has no October 2025 value.

Run once from the repository's top folder:
    python src/load_cpi.py
A second run fails on the duplicate year, because year is the primary key.
"""

from pathlib import Path

from course_db import connect

TEAM = "dasher"
CSV_FILE = Path("data/raw/cpi_annual.csv")

with connect(team=TEAM) as conn:
    with conn.cursor() as cur:
        with cur.copy("COPY cpi_annual FROM STDIN (FORMAT csv, HEADER true)") as copy:
            with open(CSV_FILE, "rb") as f:
                for line in f:
                    copy.write(line)
        print(f"Loaded {cur.rowcount} rows from {CSV_FILE}.")