import copy
import json
import os
import tempfile
import unittest
from pathlib import Path

from runner.compare import compare_runs
from runner.evaluator import connect, metadata, reset_database, run_workload
from runner.metrics import distribution, plan_metrics


class MetricsTests(unittest.TestCase):
    def test_distribution_uses_nearest_rank_p95(self):
        self.assertEqual(distribution(list(range(1, 21)))["p95_ms"], 19)
        self.assertIsNone(distribution([]))

    def test_buffers_are_not_double_counted(self):
        plan = [{"Planning Time": 1, "Execution Time": 2, "Plan": {
            "Node Type": "Aggregate", "Total Cost": 12, "Plan Rows": 1,
            "Actual Rows": 1, "Shared Hit Blocks": 7, "Plans": [{
                "Node Type": "Index Scan", "Index Name": "example_idx",
                "Shared Hit Blocks": 7
            }]
        }}]
        metrics = plan_metrics(plan)
        self.assertEqual(metrics["shared_hit_blocks"], 7)
        self.assertEqual(metrics["indexes_used"], ["example_idx"])


@unittest.skipUnless(os.environ.get("KMOGO_INTEGRATION_TEST") == "1",
                     "set KMOGO_INTEGRATION_TEST=1 for destructive dev-schema tests")
class DatabaseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with connect() as conn:
            reset_database(conn)

    def test_failures_are_recorded_and_next_queries_continue(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)
            cases = {
                "01_good.sql": "SELECT count(*) FROM kmogo.orders",
                "02_bad.sql": "SELECT absent_column FROM kmogo.orders",
                "03_write.sql": "DELETE FROM kmogo.orders",
                "04_multiple.sql": "SELECT 1; SELECT 2",
                "05_timeout.sql": "SELECT pg_sleep(2)",
                "06_after_errors.sql": "SELECT 42",
            }
            for name, content in cases.items():
                (path / name).write_text(content)
            output = path / "failed.json"
            result = run_workload(path, repeat=1, warmup=0, timeout_ms=1000, output=output)
            self.assertEqual(result["status"], "failed")
            self.assertEqual(len(result["samples"]), 6)
            self.assertEqual([s["success"] for s in result["samples"]],
                             [True, False, False, False, False, True])
            self.assertEqual(result["samples"][2]["error"]["sqlstate"], "25006")
            self.assertEqual(result["samples"][4]["error"]["sqlstate"], "57014")
            self.assertEqual(json.loads(output.read_text())["status"], "failed")
            with connect() as conn:
                self.assertEqual(conn.execute("SELECT count(*) FROM kmogo.orders").fetchone()[0],
                                 200000)

    def test_real_plan_capture_and_comparison_guards(self):
        result = run_workload("workloads/smoke", repeat=2, warmup=1, explain=True)
        self.assertEqual(result["status"], "complete")
        self.assertEqual(len(result["samples"]), 6)
        self.assertTrue(all(s["plan"][0]["Plan"] for s in result["samples"]))
        self.assertEqual(compare_runs(result, result)["workload"]["mean_change_pct"], 0)
        for location, value in (
            (("metadata", "dataset_fingerprint"), "different"),
            (("configuration", "repeat"), 3),
            (("metadata", "settings"), {}),
        ):
            changed = copy.deepcopy(result)
            changed[location[0]][location[1]] = value
            with self.assertRaises(ValueError):
                compare_runs(result, changed)
        changed = copy.deepcopy(result)
        changed["samples"][0]["result_sha256"] = "different"
        with self.assertRaises(ValueError):
            compare_runs(result, changed)
        changed = copy.deepcopy(result)
        changed["queries"][0]["sha256"] = "different"
        with self.assertRaises(ValueError):
            compare_runs(result, changed)

    def test_reset_restores_same_data_fingerprint(self):
        with connect() as conn:
            before = metadata(conn)["dataset_fingerprint"]
            conn.execute("CREATE INDEX reset_probe ON kmogo.orders (status)")
            reset_database(conn)
            self.assertEqual(metadata(conn)["dataset_fingerprint"], before)
            self.assertIsNone(conn.execute("SELECT to_regclass('kmogo.reset_probe')").fetchone()[0])


if __name__ == "__main__":
    unittest.main()
