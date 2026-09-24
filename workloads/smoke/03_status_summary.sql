SELECT status, count(*) AS order_count, sum(total_amount) AS total_amount
FROM kmogo.orders
WHERE order_date >= DATE '2025-01-01'
GROUP BY status
ORDER BY status;
