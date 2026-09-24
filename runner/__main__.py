"""CLI: python -m runner {reset,run,compare,experiment}."""
import argparse
import json
import sys
import time
from pathlib import Path

import psycopg

from .compare import compare_runs
from .evaluator import apply_index, connect, error_record, load_queries, reset_database, run_workload
from .metrics import save_json


def measurement_args(parser):
    parser.add_argument("--workload", type=Path, default=Path("workloads/smoke"))
    parser.add_argument("--repeat", type=int, default=5)
    parser.add_argument("--warmup", type=int, default=1)
    parser.add_argument("--timeout-ms", type=int, default=30000)


def main():
    parser = argparse.ArgumentParser(description="Kmogo MP1 PostgreSQL evaluation loop")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("reset", help="DESTROY/recreate only the kmogo development schema")
    run = commands.add_parser("run", help="Run read-only workload and save JSON")
    measurement_args(run)
    run.add_argument("--explain", action="store_true")
    run.add_argument("--label", default="baseline")
    run.add_argument("--output", type=Path, required=True)
    compare = commands.add_parser("compare", help="Compare complete compatible result files")
    compare.add_argument("baseline", type=Path)
    compare.add_argument("candidate", type=Path)
    compare.add_argument("--output", type=Path, required=True)
    experiment = commands.add_parser("experiment", help="RESET smoke data; baseline; index; rerun")
    measurement_args(experiment)
    experiment.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.command == "reset":
            with connect() as conn:
                reset_database(conn)
            print("Recreated kmogo schema: 10000 customers, 200000 orders, primary keys only.")
        elif args.command == "run":
            result = run_workload(args.workload, args.repeat, args.warmup, args.explain,
                                  args.label, args.output, args.timeout_ms)
            print(f"{result['status']}: {args.output}")
            return 0 if result["status"] == "complete" else 1
        elif args.command == "compare":
            result = compare_runs(
                json.loads(args.baseline.read_text(encoding="utf-8")),
                json.loads(args.candidate.read_text(encoding="utf-8")),
            )
            save_json(args.output, result)
            print(json.dumps(result["workload"], indent=2))
        elif args.command == "experiment":
            if args.repeat < 1 or args.warmup < 0 or args.timeout_ms < 1:
                raise ValueError("repeat >= 1, warmup >= 0 and timeout-ms >= 1 are required")
            load_queries(args.workload)
            # Reserve the directory before destructive reset; never replace evidence.
            args.output_dir.mkdir(parents=True, exist_ok=False)
            with connect() as conn:
                reset_database(conn)
            baseline = run_workload(args.workload, args.repeat, args.warmup, True,
                                    "baseline", args.output_dir / "baseline.json", args.timeout_ms)
            if baseline["status"] != "complete":
                raise ValueError("Baseline failed; candidate index was not applied")
            with connect() as conn:
                start = time.perf_counter()
                apply_index(conn)
                index_setup_ms = (time.perf_counter() - start) * 1000
            candidate = run_workload(args.workload, args.repeat, args.warmup, True,
                                     "manual-index-001", args.output_dir / "indexed.json",
                                     args.timeout_ms)
            comparison = compare_runs(baseline, candidate)
            comparison["index_setup_including_analyze_ms"] = index_setup_ms
            save_json(args.output_dir / "comparison.json", comparison)
            print(json.dumps(comparison["workload"], indent=2))
            print(f"Full results and plans: {args.output_dir}")
        return 0
    except (ValueError, OSError, psycopg.Error) as error:
        if isinstance(error, psycopg.Error):
            print(json.dumps(error_record(error)), file=sys.stderr)
        else:
            print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
