# Manual index experiment 001

## Result and scope

Three independent baseline/index cycles completed on **native Windows
PostgreSQL 16.15**, with five measured repetitions per configuration and one
untimed warmup pass per cycle. This is a temporary synthetic smoke test,
**not TPC-H**. Subsequent Docker lifecycle validation also passed; its
[separate record](docker-validation-001.md) contains container measurements.
The timings below remain native Windows measurements.

The pooled mean workload time changed from **163.577 ms to 100.333 ms**
(**38.66% faster**). PostgreSQL used the manual index for the selective lookup
and join. The broad aggregate retained its sequential scan and regressed in
two of three cycles. These observations prove the evaluator can measure a
configuration change; they do not establish statistical significance,
portability, or a general index recommendation.

## Environment and data

- Measurements: 2026-09-24 02:57-02:59 UTC.
- Source revision: f4e0af39df9fa8b1afe5d9f91027f93603adea4c.
- Server: PostgreSQL 16.15, compiled by Visual C++ build 1944, 64-bit.
- Client: Python 3.13.11, psycopg 3.2.9, Windows 11 build 26200;
  12 logical CPUs reported. Additional hardware inspection was denied by the sandbox.
- Isolated scratch cluster on localhost:55433, database kmogo_dev.
  No system service or production database was used.
- Binary provenance: [EDB official archives](https://www.enterprisedb.com/download-postgresql-binaries),
  postgresql-16.15-4-windows-x64-binaries.zip.
- Archive SHA-256:
  f5f55b03bd54ce0dd1c51d524b54c7e015abd4d620af27d6971288a2dbe4a8f8.
- Dataset synthetic-orders-v1: 10,000 customers, 200,000 orders, deterministic
  arithmetic generation with fixed dates. Baseline has primary-key indexes only.
- Workload: workloads/smoke; three queries in fixed filename order.
- Session controls: parallel workers 0, JIT off, UTC, 30-second query timeout,
  5-second lock timeout, default statistics target 100.
- Shared buffers 128 MiB, work_mem 4 MiB, effective cache size 4 GiB.
  Full recorded settings use PostgreSQL's native setting units.
- Each cycle resets the schema and data, ANALYZEs, measures the baseline,
  creates orders_customer_date_idx on orders(customer_id, order_date), ANALYZEs
  again, and measures the indexed state.

## Workload results

The metric is the sum of **plain-query client execute/fetch durations** in each
repetition. Setup, metadata scans, warmups and separate EXPLAIN executions are
outside this timer. Negative percentage changes mean faster.

| Cycle | Baseline mean ms | Indexed mean ms | Change |
| --- | ---: | ---: | ---: |
| 1 | 155.722 | 83.880 | -46.13% |
| 2 | 170.167 | 103.027 | -39.46% |
| 3 | 164.841 | 114.092 | -30.79% |

Across 15 repetitions per configuration, baseline median was 158.214 ms and
indexed median 90.326 ms. Individual samples and distributions are retained.

## Per-query measurements and plans

These means pool 15 samples per configuration. EXPLAIN timings are from a
separate execution after each plain-query sample.

| Query | Before client ms | After client ms | Change | Before -> after EXPLAIN execution ms |
| --- | ---: | ---: | ---: | ---: |
| 01_customer_orders | 35.344 | 1.005 | -97.16% | 34.408 -> 0.138 |
| 02_customer_totals | 37.430 | 4.333 | -88.42% | 68.354 -> 2.933 |
| 03_status_summary | 90.802 | 94.995 | 4.62% | 100.317 -> 104.908 |

- 01_customer_orders: sequential scan -> bitmap index/heap scan using
  orders_customer_date_idx.
- 02_customer_totals: orders sequential scan -> bitmap index/heap scans using
  orders_customer_date_idx; customers_pkey is also used.
- 03_status_summary: sequential scan in both states; candidate index unused.
  Changes were -7.18%, +4.35%, and +15.54% by cycle. The pooled 4.62% regression
  must remain visible even though the overall workload improves.

Index size: **4,513,792 bytes** (about 4.30 MiB) in all cycles.
Index creation plus ANALYZE took 578.95, 498.54, and 522.30 ms.
Index write and maintenance overhead were not evaluated.

All measured queries succeeded. Fetched results matched between configurations
and repetitions. Data fingerprints and index state remained unchanged during
each run. The comparison checks reject differing SQL, settings, data, failed
samples, and changed query results.

## Evidence

- [baseline.json](evidence/manual-index-001/baseline.json): cycle 1, all timings,
  full raw EXPLAIN JSON for every query/repetition, configuration and database state.
- [indexed.json](evidence/manual-index-001/indexed.json): corresponding indexed
  state, including full plans.
- [cycles.json](evidence/manual-index-001/cycles.json): all three cycle comparisons,
  individual timings/result checksums and plan summaries.
  Full plans for cycles 2 and 3 remain in ignored local results files.
- [Measurement contract](../docs/measurement.md): timing definitions and limits.

The three committed JSON files total about 160 KiB. Larger local results,
virtual environments, credentials and the downloaded server are excluded from Git.

## Commands and checks actually performed

The native test process used PGHOST=127.0.0.1, PGPORT=55433,
PGDATABASE=kmogo_dev, PGUSER=kmogo and the development password.
KMOGO_REVISION was set to the source revision above.

After initializing the official portable server and creating the empty database:

~~~sh
python -m compileall -q runner tests
python -m unittest discover -s tests -v
python -m runner experiment --repeat 5 --warmup 1 --output-dir results/precommit-validation
python -m runner experiment --repeat 5 --warmup 1 --output-dir results/native-cycle-1
python -m runner experiment --repeat 5 --warmup 1 --output-dir results/native-cycle-2
python -m runner experiment --repeat 5 --warmup 1 --output-dir results/native-cycle-3
docker compose config --quiet
git diff --check
~~~

The unittest command had KMOGO_INTEGRATION_TEST=1: **all five tests passed**
in 24.935 seconds. Tests covered real plans, failed-query recovery, timeouts,
read-only write rejection, multi-statement rejection, comparison mismatch guards
and deterministic schema reset. Invalid --repeat 0 was rejected with exit 1.

All four full experiment invocations succeeded. The precommit validation is
excluded from the reported three-cycle evidence. Compose configuration validation
and Python compilation passed.

## Subsequent Docker validation and next task

Docker validation completed on 2026-09-24 from the user's terminal via
`pwsh -NoProfile -File scripts/validate-docker.ps1`. Container build/startup,
health, client access, all five tests, three fresh experiment cycles and volume
destroy/recreation passed. The newly initialized volume reproduced the same
data fingerprint and baseline indexes without an additional schema reset.

See the [Docker validation record](docker-validation-001.md) for the image
digest, command log, runtime metadata and separate container timings. The
sandbox's Docker pipe restriction was resolved for validation by running the
committed script from the user's normal terminal.

The next benchmark task is PostgreSQL-compatible TPC-H at scale factor 0.1,
as recommended by KMO-24.

Warm caches, metadata scans, fixed query order, EXPLAIN instrumentation, ANALYZE
sampling, local Windows activity and the small synthetic dataset limit the
conclusions. There is no statistical-significance claim. KMO-7 also still needs
confirmation that every team member has repository access.
