-- Reproducible smoke data, NOT TPC-H. Only the dedicated kmogo schema is reset.
BEGIN;
DROP SCHEMA IF EXISTS kmogo CASCADE;
CREATE SCHEMA kmogo;

CREATE TABLE kmogo.dataset_metadata (
    dataset_id text PRIMARY KEY,
    description text NOT NULL
);
INSERT INTO kmogo.dataset_metadata VALUES (
    'synthetic-orders-v1',
    '10000 customers; 200000 orders; deterministic arithmetic generation; no RNG'
);

CREATE TABLE kmogo.customers (
    customer_id integer PRIMARY KEY,
    region text NOT NULL,
    customer_name text NOT NULL
);
CREATE TABLE kmogo.orders (
    order_id integer PRIMARY KEY,
    customer_id integer NOT NULL REFERENCES kmogo.customers(customer_id),
    order_date date NOT NULL,
    status text NOT NULL,
    total_amount numeric(12,2) NOT NULL
);

INSERT INTO kmogo.customers
SELECT n, (ARRAY['AFRICA','AMERICA','ASIA','EUROPE','OCEANIA'])[1 + n % 5],
       'customer-' || n
FROM generate_series(1, 10000) AS n;

INSERT INTO kmogo.orders
SELECT n, 1 + (n * 37) % 10000,
       DATE '2024-01-01' + (n * 17) % 730,
       (ARRAY['complete','pending','cancelled'])[1 + n % 3],
       (100 + (n::bigint * 7919) % 100000)::numeric / 100
FROM generate_series(1, 200000) AS n;

ANALYZE kmogo.customers;
ANALYZE kmogo.orders;
COMMIT;
