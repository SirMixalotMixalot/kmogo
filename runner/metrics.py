"""Small result/plan helpers; planner cost units are never treated as time."""
import hashlib
import json
import math
import statistics
from pathlib import Path


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, default=str).encode()).hexdigest()


def distribution(values):
    if not values:
        return None
    ordered = sorted(values)
    return {
        "count": len(values),
        "min_ms": min(values),
        "max_ms": max(values),
        "mean_ms": statistics.fmean(values),
        "median_ms": statistics.median(values),
        "p95_ms": ordered[math.ceil(0.95 * len(ordered)) - 1],
    }


def plan_metrics(document):
    root = document[0]["Plan"]
    nodes = []
    def visit(node):
        nodes.append({key: node[key] for key in (
            "Node Type", "Relation Name", "Index Name", "Startup Cost",
            "Total Cost", "Plan Rows", "Actual Rows", "Actual Loops",
            "Shared Hit Blocks", "Shared Read Blocks", "Temp Read Blocks",
            "Temp Written Blocks",
        ) if key in node})
        for child in node.get("Plans", []):
            visit(child)
    visit(root)
    return {
        "planning_ms": document[0].get("Planning Time"),
        "execution_ms": document[0].get("Execution Time"),
        "root_node": root["Node Type"],
        "estimated_total_cost": root["Total Cost"],
        "estimated_rows": root["Plan Rows"],
        "actual_rows": root["Actual Rows"],
        "scan_types": sorted({n["Node Type"] for n in nodes if "Scan" in n["Node Type"]}),
        "indexes_used": sorted({n["Index Name"] for n in nodes if "Index Name" in n}),
        # Parent buffer counters include children; never sum across nodes.
        "shared_hit_blocks": root.get("Shared Hit Blocks", 0),
        "shared_read_blocks": root.get("Shared Read Blocks", 0),
        "nodes": nodes,
    }


def save_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    # Exclusive creation prevents silently replacing earlier experiment evidence.
    with path.open("x", encoding="utf-8") as handle:
        json.dump(value, handle, indent=2, default=str, allow_nan=False)
        handle.write("\n")
