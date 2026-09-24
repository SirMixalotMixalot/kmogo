# Kmogo

University of Waterloo SE390 capstone: Intelligent Cloud Database Autotuner.
MP1 focuses on PostgreSQL index optimization and reproducible evaluation.
The AI/search strategy is intentionally undecided.

## PostgreSQL development setup

Install Git and Docker Desktop with Linux containers (or Docker Engine with
Compose v2). Copy `.env.example` to `.env` with `Copy-Item .env.example .env`
in PowerShell or `cp .env.example .env` on macOS/Linux.

Run `docker compose up -d --wait postgres` and `docker compose ps`.
Connect with `docker compose exec postgres psql -U kmogo -d kmogo_dev`,
substituting your configured user/database when changed.
The host endpoint is localhost:55432 by default.

PostgreSQL is pinned to major version 16. Credentials and the host port are
configurable in `.env`; never commit it. Initial SQL generates 10,000 customers
and 200,000 orders. This temporary smoke dataset is **not TPC-H**.
See [workload notes](workloads/smoke/README.md).

`docker compose down` preserves the database. To destroy and recreate this
project's isolated development volume, run `docker compose down -v`, then
`docker compose up -d --wait postgres`. This deletes development data and reruns
initialization. Initial credentials cannot be changed just by restarting an
existing volume.

Team access and teammate setup verification are not yet confirmed.
