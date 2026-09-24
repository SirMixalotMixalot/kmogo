# Docker validation and manual index experiment 001

## Result and scope

**All eight Docker checks passed** on 2026-09-24. The user ran the committed
validation script from their normal terminal because Windows denied the Codex
sandbox access to Docker's named pipe. The saved log and JSON were then reviewed;
all 90 measured samples, raw plan metrics, per-run summaries and three comparisons
were independently recomputed from the saved results.

The pooled mean workload time changed from **131.276 ms to 78.128 ms
(-40.49%)**, across three fresh reset/baseline/index cycles. Each configuration
had one untimed warmup and five measured repetitions per cycle. This uses the
temporary deterministic smoke workload, **not TPC-H**. It proves the evaluation
loop and container lifecycle work on this machine; it makes no statistical
significance or general index recommendation claim.

These measurements are separate from the [native Windows experiment](manual-index-001.md).
They are not a controlled comparison of Docker versus native performance.

## Runtime and provenance

- Validation: 2026-09-24 05:23:52-05:27:55 UTC.
- Clean source revision: `7ec05bb4309c007f4fee01273fa2dff2b4f36b24`.
- Docker Desktop 4.28.0; Docker Engine/CLI 25.0.3; Linux amd64 containers
  on WSL2 kernel 6.18.33.2-microsoft-standard-WSL2.
- PostgreSQL 16.15 (Debian 16.15-1.pgdg12+2), from `postgres:16-bookworm`.
- PostgreSQL image digest:
  `postgres@sha256:efedf3595f1d6f415c08568ba171029bf54052e754cc9f030e3f2412b21f3d67`.
- Built runner image ID:
  `sha256:cf8dceabb84733850ef75eaa2f20ee28084009fc939f8402a94560914579f41b`.
- Runner: Python 3.12.14, psycopg 3.2.9; 12 logical CPUs reported.
- Dataset: synthetic-orders-v1, 10,000 customers and 200,000 orders.
- Queries: `workloads/smoke`, in fixed filename order, serial single client.
- Session settings: parallel workers 0, JIT off, UTC, query timeout 30 s,
  lock timeout 5 s, statistics target 100, shared buffers 128 MiB,
  work_mem 4 MiB and effective cache size 4 GiB. Full settings and units
  are in the JSON metadata.

The Compose tag pins the PostgreSQL major version, and can receive patch updates.
The digest above identifies the image actually tested.

## Container checks

Command run by the user:

~~~powershell
pwsh -NoProfile -File scripts/validate-docker.ps1
~~~

| Check | Observed result |
| --- | --- |
| Docker engine and Compose configuration | Passed |
| PostgreSQL startup and health | Healthy |
| Runner image build | Passed |
| Runner client connection and data load | 10,000 customers / 200,000 orders |
| `KMOGO_INTEGRATION_TEST=1 python -m unittest discover -s tests -v` | All 5 tests passed in 27.934 s; no skips |
| Three complete manual-index experiments | All queries and comparisons succeeded |
| `docker compose down -v` followed by `up -d --wait postgres` | New container and volume created; healthy |
| Initialization on recreated volume | Matching data fingerprint, row counts and baseline index definitions |

The tests cover real plan capture, failure/timeout recovery, rejected writes and
multiple statements, incompatible comparison rejection, deterministic reset,
buffer-counter handling and distribution calculation.

The volume creation timestamp changed from **05:24:36 UTC to 05:27:43 UTC**;
the container ID changed as well. The script read the recreated database
**without running a schema reset**, verifying initialization on the new volume.
Both database snapshots have fingerprint
`ec1a56d3012b5690376ef55f56fa71c513e01d70a17725e2bc1f9e025f969e7c`.
The script finished with PostgreSQL healthy and baseline data restored.
Individual teammates' repository access or machines have not been verified.

## Workload results

The primary metric sums plain-query client execute/fetch durations per repetition.
Setup, metadata, warmups and separate EXPLAIN executions are outside the timer.
Negative changes mean faster.

| Cycle | Baseline mean ms | Indexed mean ms | Change |
| --- | ---: | ---: | ---: |
| 1 | 129.524 | 74.602 | -42.40% |
| 2 | 126.356 | 79.523 | -37.06% |
| 3 | 137.947 | 80.260 | -41.82% |
| Pooled, 15 repetitions per configuration | 131.276 | 78.128 | -40.49% |

Pooled medians: **129.583 -> 76.991 ms**. Individual repetitions are retained.

## Per-query results and plans

The following means pool 15 samples per configuration. EXPLAIN durations come
from separate executions after each plain-query sample.

| Query | Baseline client ms | Indexed client ms | Change | Baseline -> indexed EXPLAIN execution ms |
| --- | ---: | ---: | ---: | ---: |
| 01_customer_orders | 26.899 | 1.286 | -95.22% | 25.957 -> 0.105 |
| 02_customer_totals | 31.220 | 4.319 | -86.17% | 61.240 -> 3.071 |
| 03_status_summary | 73.156 | 72.524 | -0.87% | 83.984 -> 82.372 |

- Lookup: sequential scan changed to bitmap index/heap scans using
  `orders_customer_date_idx` on `orders(customer_id, order_date)`.
- Join: the orders sequential scan changed to bitmap index/heap scans using
  the same index; the customer primary-key index was also used.
- Broad aggregate: sequential scan in both configurations; candidate index unused.
  Per-cycle changes were **-3.64%, +7.47%, -5.61%**. The second cycle regressed,
  and the small pooled change does not establish an improvement for this query.

The only added index was **4,513,792 bytes (4.30 MiB)** in every cycle.
Creation plus ANALYZE took **342.50, 372.22 and 364.43 ms**.
Every query returned matching results before/after; no measured or warmup queries
failed. The data fingerprint and index state stayed stable during each run.

## Saved evidence

Under [evidence/docker-validation-001](evidence/docker-validation-001/):

- [validation.json](evidence/docker-validation-001/validation.json): eight check
  outcomes, source identity, Docker versions, image identities, container/volume
  recreation evidence and all three cycle comparisons.
- [commands.log](evidence/docker-validation-001/commands.log): actual commands and
  output, including all test results. The absolute repository path is replaced
  with `<repository>`, line endings are normalized, and trailing whitespace
  is removed; other command/output content is preserved.
- [initial-state.json](evidence/docker-validation-001/initial-state.json) and
  [recreated-state.json](evidence/docker-validation-001/recreated-state.json):
  database metadata before/after volume recreation.
- [baseline.json](evidence/docker-validation-001/baseline.json) and
  [indexed.json](evidence/docker-validation-001/indexed.json): cycle 1's complete
  results, including all raw EXPLAIN plans, query text, settings and fingerprints.
- [cycles.json](evidence/docker-validation-001/cycles.json): all 90 individual
  timings, result checksums, plan summaries, per-cycle comparisons and pooled
  workload/query distributions. Full plans for cycles 2 and 3 remain in ignored
  local results. The seven committed evidence files total about **246 KiB**.

Recompute the saved full-plan pair with host Python and the runner dependencies:

~~~sh
python -m runner compare experiments/evidence/docker-validation-001/baseline.json experiments/evidence/docker-validation-001/indexed.json --output results/docker-evidence-recomparison.json
~~~

Use a fresh output path if it already exists. The Docker runner image does not
bundle the committed evidence directory; its normal inputs are the local results
directory mounted into the container.

## Limits and next task

Warm caches, metadata scans, fixed query order, ANALYZE sampling, separate
EXPLAIN executions and local machine activity affect timings. Repetitions expose
variation but do not establish statistical significance. This small, read-only
synthetic workload does not measure index write or maintenance costs.

KMO-17's container acceptance checks are satisfied. KMO-7 remains open for team
repository access confirmation. The next technical task is to integrate a pinned,
PostgreSQL-compatible **TPC-H scale factor 0.1** generator and query set, then run
the same evaluation protocol.
