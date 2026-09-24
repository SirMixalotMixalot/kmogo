# Measurement contract

## Primary metric

A sample times a plain SQL query's execute and complete result fetch with a
monotonic client clock. Hashing results happens afterwards. A workload repetition
is the sum of these timings for all queries; setup, warmups, metadata, EXPLAIN and
idle time are excluded. Report means plus median, min/max and nearest-rank p95.
With only five samples, p95 is the maximum; it is not a stable tail estimate.

With `--explain`, each plain sample is followed by a separate
`EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` execution in the same read-only
transaction. The raw JSON is authoritative. Extracted fields include planning
and execution time, root/node/scan type, estimated cost/rows, actual rows/loops,
index names and buffer counters. Parent buffer counts include children, so the
runner does not sum counters over the tree. Cost is not milliseconds.
These separate executions can differ; EXPLAIN instrumentation has overhead.

## Controls and identity

- Fixed SQL file order; one statement per file enforced by PostgreSQL's extended
  protocol. All measured queries run in read-only transactions; failed
  transactions roll back before the next query.
- One connection, one client, no concurrent load intentionally generated.
- One untimed warmup pass by default, five measured repetitions by default.
- Serial plans (`max_parallel_workers_per_gather=0`), JIT off, UTC session time.
  No index or scan type is forced; PostgreSQL chooses the actual plan.
- Workload timeout is configurable; lock timeout is 5 seconds.
- The smoke schema's registration, row counts and ordered content checksums are
  captured before and after each run. This metadata scan itself warms caches.
- Data fingerprints, index definitions/sizes, settings, PostgreSQL version,
  SQL hashes, client details and optional source revision accompany the evidence.
- Comparison requires complete runs, identical SQL/configuration/data/server
  settings and identical fetched results for each query across all repetitions.
  Use deterministic output ordering in SQL. Index differences are intentionally
  allowed. A changed dataset/index state during a run makes that run fail.
- Database metadata currently targets the smoke schema. A TPC-H adapter must
  extend it to that benchmark's data identity before claiming comparable runs.

## Interpreting evidence

Baseline data has only primary-key indexes; the manual candidate adds
`orders_customer_date_idx (customer_id, order_date)`. The experiment resets data
at the beginning of each cycle. Index creation plus ANALYZE is timed separately,
and index storage is captured. No write-overhead benchmark is included.

The dataset is small and synthetic. Warm caches, fixed query order, ANALYZE's
statistics sample and local machine/VM activity introduce variability and bias.
Run several full baseline/index cycles and examine individual regressions. No
cache flushing is attempted. A restart does not guarantee cold OS caches.
Do not call one faster result statistically significant or a TPC-H result.

## Sources and planning context

- [PostgreSQL 16 EXPLAIN](https://www.postgresql.org/docs/16/sql-explain.html)
- [PostgreSQL 16 ANALYZE](https://www.postgresql.org/docs/16/sql-analyze.html)
- [Psycopg transaction management](https://www.psycopg.org/psycopg3/docs/basic/transactions.html)
- [Compose health dependencies](https://docs.docker.com/compose/how-tos/startup-order/)
- Linear KMO-24 recommends small-scale TPC-H; this temporary smoke test is an
  implementation stepping stone. KMO-25 motivates raw JSON plan capture.
