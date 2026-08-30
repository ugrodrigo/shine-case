"""Execute sql/playground.sql against the prepared Shine DuckDB database."""

import argparse
from pathlib import Path

import duckdb


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SQL_FILE = PROJECT_ROOT / "sql" / "playground.sql"
DATABASE = PROJECT_ROOT / "data" / "shine_case.duckdb"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Run a SQL file against the local Shine DuckDB database."
    )
    parser.add_argument(
        "sql_file",
        nargs="?",
        type=Path,
        default=DEFAULT_SQL_FILE,
        help="SQL file to execute (default: sql/playground.sql)",
    )
    args = parser.parse_args()

    sql_file = args.sql_file.resolve()
    if not DATABASE.exists():
        raise SystemExit("Database not found. Run `python scripts/run_eda.py` first.")
    if not sql_file.exists():
        raise SystemExit(f"SQL file not found: {sql_file}")

    connection = duckdb.connect(str(DATABASE), read_only=True)
    try:
        result = connection.execute(sql_file.read_text(encoding="utf-8"))
        if result.description:
            frame = result.fetchdf()
            print(frame.to_string(index=False))
        else:
            print("Query completed successfully; it returned no result table.")
    finally:
        connection.close()


if __name__ == "__main__":
    main()
