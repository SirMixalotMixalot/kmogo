"""Sequential, read-only workload measurements against the isolated dev DB."""
import hashlib
import os
import platform
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

import psycopg
from psycopg import sql

from .metrics import digest, distribution, plan_metrics, save_json

ROOT = Path(__file__).resolve().parents[1]
SETTINGS = (
    "shared_buffers", "effective_cache_size", "work_mem", "maintenance_work_mem",
    "random_page_cost", "seq_page_cost", "max_parallel_workers_per_gather",
    "jit", "track_io_timing", "statement_timeout", "lock_timeout",
    "default_statistics_target", "server_encoding", "TimeZone",
)


def now():
    return datetime.now(timezone.utc).isoformat()


def connect():
    # libpq PG* environment variables; never persist passwords or a connection URI.
    conn = psycopg.connect(connect_timeout=5, autocommit=True, prepare_threshold=None)
    conn.execute("SET statement_timeout = '30s'")
    conn.execute("SET lock_timeout = '5s'")
    conn.execute("SET max_parallel_workers_per_gather = 0")
    conn.execute("SET jit = off")
    conn.execute("SET TIME ZONE 'UTC'")
    return conn


def reset_database(conn):
    # One transaction in the SQL file: a failed reset preserves the prior state.
    conn.execute((ROOT / "db/init.sql").read_text(encoding="utf-8"), prepare=False)


def apply_index(conn):
    with conn.transaction():
        conn.execute((ROOT / "db/manual-index-001.sql").read_text(encoding="utf-8"), prepare=False)


def metadata(conn):
    tables = {}
    for table, key in (("customers", "customer_id"), ("orders", "order_id")):
        query = sql.SQL(
            "SELECT count(*), md5(string_agg(md5(row_to_json(t)::text), '' ORDER BY {})) "
            "FROM kmogo.{} AS t"
        ).format(sql.Identifier(key), sql.Identifier(table))
        count, checksum = conn.execute(query).fetchone()
        tables[table] = {"rows": count, "content_md5": checksum}
    dataset = {
        "registration": conn.execute(
            "SELECT dataset_id, description FROM kmogo.dataset_metadata ORDER BY dataset_id"
        ).fetchall(),
        "tables": tables,
    }
    indexes = conn.execute("""
        SELECT i.indexname, i.indexdef, pg_relation_size(
            quote_ident(i.schemaname) || '.' || quote_ident(i.indexname))
        FROM pg_indexes AS i WHERE i.schemaname = 'kmogo'
        ORDER BY i.indexname
    """).fetchall()
    return {
        "postgres_version": conn.execute("SELECT version()").fetchone()[0],
        "server_version_num": conn.info.server_version,
        "connection": {k: getattr(conn.info, k) for k in ("host", "port", "dbname", "user")},
        "dataset": dataset,
        "dataset_fingerprint": digest(dataset),
        "indexes": [{"name": n, "definition": d, "bytes": b} for n, d, b in indexes],
        "settings": dict(conn.execute(
            "SELECT name, setting FROM pg_settings WHERE name = ANY(%s) ORDER BY name",
            (list(SETTINGS),)
        ).fetchall()),
        "client": {"python": sys.version.split()[0], "psycopg": psycopg.__version__,
                   "platform": platform.platform(), "cpu_count": os.cpu_count()},
        "source_revision": os.environ.get("KMOGO_REVISION", "unrecorded"),
        "schema_sha256": hashlib.sha256((ROOT / "db/init.sql").read_bytes()).hexdigest(),
    }


def load_queries(workload):
    queries = []
    for path in sorted(Path(workload).glob("*.sql")):
        text = path.read_text(encoding="utf-8").strip()
        if not text:
            raise ValueError(f"Empty SQL file: {path.name}")
        queries.append({"id": path.stem, "sql": text,
                        "sha256": hashlib.sha256(text.encode()).hexdigest()})
    if not queries:
        raise ValueError(f"No SQL files in {workload}")
    return queries


def execute_query(conn, query, explain=False, timeout_ms=30000):
    with conn.transaction():
        conn.execute("SET TRANSACTION READ ONLY")
        conn.execute("SELECT set_config('statement_timeout', %s, true)", (str(timeout_ms),))
        with conn.cursor(binary=True) as cur:
            # Binary results force the extended protocol, which rejects multiple
            # statements in one file. No automatic prepared statement caching.
            start = time.perf_counter_ns()
            cur.execute(query, prepare=False)
            rows = cur.fetchall()
            elapsed_ms = (time.perf_counter_ns() - start) / 1_000_000
            result = {"elapsed_ms": elapsed_ms, "rows_returned": len(rows),
                      "result_sha256": digest(rows)}
            if explain:
                cur.execute("EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) " + query,
                            prepare=False)
                document = cur.fetchone()[0]
                result["plan"] = document
                result["plan_metrics"] = plan_metrics(document)
            return result


def error_record(error):
    return {
        "type": type(error).__name__,
        "sqlstate": getattr(error, "sqlstate", None),
        "message": getattr(getattr(error, "diag", None), "message_primary", None)
                   or type(error).__name__,
    }


def summarize(samples, queries, repeat):
    per_query = {}
    for query in queries:
        valid = [s for s in samples if s["query_id"] == query["id"] and s["success"]]
        per_query[query["id"]] = {
            "client_elapsed": distribution([s["elapsed_ms"] for s in valid]),
            "explain_execution": distribution([
                s["plan_metrics"]["execution_ms"] for s in valid if "plan_metrics" in s
            ]),
            "failures": repeat - len(valid),
        }
    totals = []
    for repetition in range(1, repeat + 1):
        batch = [s for s in samples if s["repetition"] == repetition]
        if len(batch) == len(queries) and all(s["success"] for s in batch):
            totals.append(sum(s["elapsed_ms"] for s in batch))
    return {"queries": per_query, "workload_client_elapsed": distribution(totals),
            "workload_totals_ms": totals}


def run_workload(workload, repeat=5, warmup=1, explain=False,
                 label="run", output=None, timeout_ms=30000):
    if repeat < 1 or warmup < 0 or timeout_ms < 1:
        raise ValueError("repeat >= 1, warmup >= 0 and timeout-ms >= 1 are required")
    if output and Path(output).exists():
        raise ValueError(f"Output already exists: {output}; choose a new path")
    queries = load_queries(workload)
    result = {
        "format_version": 1, "run_id": str(uuid.uuid4()), "label": label,
        "started_at": now(), "status": "failed",
        "configuration": {
            "workload": Path(workload).name, "repeat": repeat, "warmup": warmup,
            "explain": explain, "timeout_ms": timeout_ms,
            "query_order": "sorted filenames, fixed every repetition",
            "measurement": "plain query execute + fetch; separate EXPLAIN after each sample",
            "cache_policy": "warm; no cache flush; metadata and warmups touch data",
        },
        "queries": queries, "samples": [], "warmup_failures": [],
    }
    try:
        with connect() as conn:
            result["metadata"] = metadata(conn)
            for repetition in range(1, warmup + 1):
                for query in queries:
                    try:
                        execute_query(conn, query["sql"], timeout_ms=timeout_ms)
                    except psycopg.Error as error:
                        result["warmup_failures"].append({
                            "query_id": query["id"], "repetition": repetition,
                            "error": error_record(error),
                        })
            for repetition in range(1, repeat + 1):
                for query in queries:
                    sample = {"query_id": query["id"], "repetition": repetition}
                    started = time.perf_counter_ns()
                    try:
                        sample.update(execute_query(conn, query["sql"], explain, timeout_ms))
                        sample["success"] = True
                    except psycopg.Error as error:
                        sample.update(success=False, error=error_record(error),
                                      failed_attempt_ms=(time.perf_counter_ns() - started) / 1_000_000)
                    result["samples"].append(sample)
            result["summary"] = summarize(result["samples"], queries, repeat)
            # Detect unexpected writes by another client during this run.
            after = metadata(conn)
            result["final_dataset_fingerprint"] = after["dataset_fingerprint"]
            result["database_state_unchanged"] = (
                after["dataset_fingerprint"] == result["metadata"]["dataset_fingerprint"]
                and after["indexes"] == result["metadata"]["indexes"]
            )
            if (all(s["success"] for s in result["samples"])
                    and not result["warmup_failures"] and result["database_state_unchanged"]):
                result["status"] = "complete"
    except psycopg.Error as error:
        result["fatal_error"] = error_record(error)
    result["finished_at"] = now()
    if output:
        save_json(output, result)
    return result
