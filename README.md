# Kmogo

University of Waterloo SE390 capstone: **Intelligent Cloud Database Autotuner**.
MP1 focuses on PostgreSQL index optimization. This slice establishes a
reproducible workload Ã¢â€ â€™ baseline Ã¢â€ â€™ query plan Ã¢â€ â€™ manual index Ã¢â€ â€™ comparison loop.
The AI/search strategy remains undecided.

**Validation status:** the runner and three index-experiment cycles passed on native
Windows PostgreSQL 16.15. Compose configuration validates, but container startup,
build and volume recreation remain unverified because this sandbox cannot access
the Docker engine. See the experiment evidence for the exact checks and limits.

## Prerequisites and setup

- Git, Docker Desktop with Linux containers (or Docker Engine), Docker Compose v2.
- An available localhost port, default **55432**.
- No local PostgreSQL or Python installation is needed for the Docker workflow.

Clone the repository, enter its directory, and copy `.env.example` to `.env`:

```powershell
Copy-Item .env.example .env
```

On macOS/Linux use `cp .env.example .env`. Database, user, password and host port
are configurable in `.env`. Credentials are development-only; never commit
that file. The database port binds to localhost.

```sh
docker compose up -d --wait postgres
docker compose ps
docker compose build runner
docker compose run --rm runner --help
```

On a new volume, initialization creates **10,000 customers and 200,000 orders**.
The PostgreSQL image is pinned to major version **16** (`postgres:16-bookworm`).
The tag can receive patch updates; each result records the exact server version.
The experiment record identifies the runtime used for its evidence.

To connect interactively (substitute your configured database/user if changed):

```sh
docker compose exec postgres psql -U kmogo -d kmogo_dev
```

From host clients use `127.0.0.1:55432` and the values in `.env`.
This is an isolated development database. Team-member access/verification has
not been established merely by providing these instructions.

## Load or reset data

```sh
docker compose run --rm runner reset
```

This destroys and recreates only the `kmogo` schema, regenerates deterministic
data, removes experimental indexes and updates statistics. It is transactional.
It does not delete saved JSON evidence.

`docker compose down` stops services and preserves the named database volume.
For a complete recreation of **this project's dev database**:

```sh
docker compose down -v
docker compose up -d --wait postgres
```

The `-v` command deletes the project's database volume. Initialization SQL runs
only on an empty volume; restart alone does not reload data. Changing initial
database/user/password values requires volume recreation. Never run these
commands against production data.

## Run the workload and capture a baseline

```sh
docker compose run --rm runner run --workload workloads/smoke --repeat 5 --warmup 1 --explain --label baseline --output results/baseline.json
```

The temporary [smoke workload](workloads/smoke/README.md) has three read-only
queries: a selective lookup, a join, and a broad aggregate. It is **not TPC-H**.
TPC-H at a small scale factor remains the next representative benchmark task.

Each SQL file contains one query and executes in filename order. Files are
identified by name and SHA-256. Every repetition records client execution/fetch
time; with `--explain`, a **separate execution** captures
`EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)`. Plans do not belong to the exact plain
timed execution. Plan capture is outside that timer, but warms caches for later
samples. Raw plans and extracted fields are saved alongside each sample.

Results include per-query and workload distributions, errors, data fingerprints,
indexes/size, settings, PostgreSQL/client versions and run configuration.
The workload metric is the sum of successful plain-query elapsed times in each
complete repetition. It excludes setup, metadata, warmups and plan capture.
Failed/incomplete runs cannot be compared. Outputs are never silently overwritten.

To record source identity, set `KMOGO_REVISION` before running:
PowerShell: `$env:KMOGO_REVISION = git rev-parse HEAD`;
macOS/Linux: `export KMOGO_REVISION=$(git rev-parse HEAD)`.

## First index experiment

```sh
docker compose run --rm runner experiment --repeat 5 --warmup 1 --output-dir results/manual-index-001
```

This command **resets the smoke data**, measures the baseline, applies exactly
one index from `db/manual-index-001.sql`, runs ANALYZE, repeats the same workload
and writes `baseline.json`, `indexed.json` and `comparison.json`.
Use a new output directory for each independent cycle. The indexed state remains
available afterwards; use `reset` to restore the baseline.

To compare compatible saved runs separately:

```sh
docker compose run --rm runner compare results/manual-index-001/baseline.json results/manual-index-001/indexed.json --output results/manual-index-001/recomparison.json
```

A negative change percentage means faster. Inspect **every query**, observed
index use and raw before/after plans, not just the aggregate.

## Development and checks

After changing Python, SQL or tests, rebuild with `docker compose build runner`.
Tests below reset the development schema:

```sh
docker compose run --rm -e KMOGO_INTEGRATION_TEST=1 --entrypoint python runner -m unittest discover -s tests -v
```

The tests exercise real plans, reset reproducibility, read-only protection,
multi-statement rejection, query failures, timeout recovery and incompatible
comparison rejection. Without `KMOGO_INTEGRATION_TEST=1`, DB tests are skipped.

Optional host Python workflow (Python 3.10+): create a virtual environment,
`pip install -r runner/requirements.txt`, set standard `PGHOST`, `PGPORT`,
`PGDATABASE`, `PGUSER`, `PGPASSWORD` variables from your configuration, then use
`python -m runner` with the same arguments. The runner does not read `.env`
directly; Compose maps it to the PG variables.

## One-command Docker validation on Windows

From your normal terminal with Docker Desktop's Linux engine running:

~~~powershell
pwsh -NoProfile -File scripts/validate-docker.ps1
~~~

The script builds the runner, checks PostgreSQL health/client access, runs the
integration suite and three index-experiment cycles, then **deletes and recreates
the kmogo-mp1 development volume**. It verifies the recreated dataset fingerprint
and baseline indexes. Existing Kmogo development data is reset.

Logs, image identities, checks and result JSON are saved in a new
results/docker-validation-TIMESTAMP directory. Failed checks return a nonzero
exit code and preserve their logs. A successful run leaves PostgreSQL healthy
with baseline data. Run this from a terminal that can access Docker; the Codex
sandbox may be denied access even while Docker Desktop is running.

## Measurement limits and next work

See [measurement notes](docs/measurement.md) and
[manual experiment evidence](experiments/manual-index-001.md).
Warm caches, fixed query order, local-machine activity and a small synthetic
dataset limit conclusions. Repetitions show variation; they do not establish
statistical significance. Read-only tests omit index write/maintenance costs.

Next: integrate a pinned, PostgreSQL-compatible **TPC-H scale factor 0.1**
generator and query set, then repeat this evaluator protocol. AI methods,
advanced candidate generation, frontend, APIs and production deployment are
outside this slice.

Planning source: [MP1 Technical Scope](https://linear.app/kmogo/document/mp1-technical-scope-bac0abef4db0).
Issues: KMO-7, KMO-17, KMO-18, KMO-19; research KMO-24/KMO-25.
