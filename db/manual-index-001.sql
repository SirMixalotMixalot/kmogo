-- One manually selected index, supporting customer equality + date range.
-- Fail if already present: the experiment must start from a clean baseline.
CREATE INDEX orders_customer_date_idx ON kmogo.orders (customer_id, order_date);
ANALYZE kmogo.orders;
