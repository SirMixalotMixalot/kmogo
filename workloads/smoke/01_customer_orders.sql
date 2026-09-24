SELECT order_id, order_date, status, total_amount
FROM kmogo.orders
WHERE customer_id = 4242
  AND order_date >= DATE '2024-07-01'
ORDER BY order_date, order_id;
