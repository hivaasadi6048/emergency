"""Ensure the emergency_dev database exists (called by start-servers.bat)."""
import sys

import psycopg

try:
    conn = psycopg.connect(
        "host=127.0.0.1 port=5433 dbname=postgres user=postgres",
        autocommit=True,
        connect_timeout=8,
    )
except Exception as exc:  # pragma: no cover - operational helper
    print(f"PG_CONNECT_FAILED: {exc}")
    sys.exit(1)

try:
    conn.execute("CREATE DATABASE emergency_dev")
    print("DB_CREATED")
except psycopg.errors.DuplicateDatabase:
    print("DB_ALREADY_EXISTS")
finally:
    conn.close()
