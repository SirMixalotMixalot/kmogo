# Manual index experiment 001

Protocol: reset the deterministic smoke dataset; run one warmup and five measured
passes with separate EXPLAIN capture; create
`orders_customer_date_idx ON kmogo.orders (customer_id, order_date)`; ANALYZE;
repeat the identical workload; compare query results, plans and elapsed times.

Reproduce with:

```sh
docker compose run --rm runner experiment --repeat 5 --warmup 1 --output-dir results/manual-index-001
```

This resets the development schema. Use a new output directory for every cycle.
See [measurement contract](../docs/measurement.md) for controls and limitations.

Measured results will be added after the full protocol is executed and verified.
No performance claim is made by this protocol alone.
