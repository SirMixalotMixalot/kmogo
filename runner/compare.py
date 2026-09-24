"""Compare only complete, compatible runs with unchanged query results."""
from .metrics import distribution


def change(before, after):
    if before == 0:
        return None
    return 100.0 * (after - before) / before


def compare_runs(baseline, candidate):
    for run in (baseline, candidate):
        if run.get("format_version") != 1 or run.get("status") != "complete":
            raise ValueError("Comparison requires two complete format-version 1 runs")
        if not run.get("database_state_unchanged"):
            raise ValueError("Database state changed during measurement")
        expected = run["configuration"]["repeat"] * len(run["queries"])
        if len(run["samples"]) != expected or not all(s["success"] for s in run["samples"]):
            raise ValueError("Missing or failed samples")
        expected_keys = {(q["id"], i) for q in run["queries"]
                         for i in range(1, run["configuration"]["repeat"] + 1)}
        if {(s["query_id"], s["repetition"]) for s in run["samples"]} != expected_keys:
            raise ValueError("Missing or duplicate query/repetition samples")
    if baseline["configuration"] != candidate["configuration"]:
        raise ValueError("Workload measurement configuration differs")
    if [(q["id"], q["sha256"]) for q in baseline["queries"]] != [
        (q["id"], q["sha256"]) for q in candidate["queries"]
    ]:
        raise ValueError("Workload SQL or query order differs")
    for key in ("dataset_fingerprint", "schema_sha256", "postgres_version", "settings"):
        if baseline["metadata"][key] != candidate["metadata"][key]:
            raise ValueError(f"Incompatible metadata: {key}")
    rows = []
    for query in baseline["queries"]:
        query_id = query["id"]
        before = [s for s in baseline["samples"] if s["query_id"] == query_id]
        after = [s for s in candidate["samples"] if s["query_id"] == query_id]
        signatures = {(s["rows_returned"], s["result_sha256"]) for s in before + after}
        if len(signatures) != 1:
            raise ValueError(f"Query results differ or are nondeterministic: {query_id}")
        b = distribution([s["elapsed_ms"] for s in before])
        a = distribution([s["elapsed_ms"] for s in after])
        def plans(samples):
            return {
                "root_nodes": sorted({s["plan_metrics"]["root_node"] for s in samples
                                      if "plan_metrics" in s}),
                "scan_types": sorted({t for s in samples
                                      for t in s.get("plan_metrics", {}).get("scan_types", [])}),
                "indexes_used": sorted({t for s in samples
                                        for t in s.get("plan_metrics", {}).get("indexes_used", [])}),
                "execution_ms": distribution([
                    s["plan_metrics"]["execution_ms"] for s in samples if "plan_metrics" in s
                ]),
            }
        rows.append({
            "query_id": query_id, "baseline": b, "candidate": a,
            "mean_change_pct": change(b["mean_ms"], a["mean_ms"]),
            "baseline_plan": plans(before), "candidate_plan": plans(after),
        })
    b = baseline["summary"]["workload_client_elapsed"]
    a = candidate["summary"]["workload_client_elapsed"]
    return {
        "format_version": 1, "baseline_run_id": baseline["run_id"],
        "candidate_run_id": candidate["run_id"],
        "metric": "sum of plain-query client elapsed milliseconds per repetition",
        "change_convention": "negative percent is faster; positive percent is slower",
        "workload": {"baseline": b, "candidate": a,
                     "mean_change_pct": change(b["mean_ms"], a["mean_ms"])},
        "queries": rows,
        "baseline_indexes": baseline["metadata"]["indexes"],
        "candidate_indexes": candidate["metadata"]["indexes"],
        "limitations": [
            "Warm cache, fixed query order, sequential single-client measurements.",
            "EXPLAIN adds overhead and warms caches but is outside the primary timer.",
            "Small synthetic dataset and local timing noise; no statistical significance claim.",
            "Read-only workload does not measure index write/maintenance costs.",
        ],
    }
