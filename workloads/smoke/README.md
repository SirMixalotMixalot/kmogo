# Temporary smoke workload

This is **not TPC-H** and is not representative benchmark evidence. It verifies
the evaluator with 10,000 customers and 200,000 deterministic orders generated
by `db/init.sql`. Generation uses fixed dates and integer arithmetic, with no
random seed, downloads, or external data generator.

The baseline has primary-key indexes only. The queries cover a selective
customer/date lookup, totals for 50 customers through a join, and a broad status
aggregate. `orders_customer_date_idx` is plausible for the first two queries;
the third helps expose workload regressions or timing noise.

Each `.sql` file must contain one read-only query. Filenames identify queries;
the runner also records their SHA-256 hashes. Files run in sorted order.

KMO-24 recommends small-scale TPC-H. That remains the next benchmark task:
pin a PostgreSQL-compatible data/query generator, document its license and
provenance, start at scale factor 0.1, and reuse this runner. This smoke dataset
deliberately avoids adding a second database/generator toolchain to the first
working slice. It does not satisfy the broader representative-benchmark goal.
