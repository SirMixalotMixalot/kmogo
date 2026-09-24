SELECT c.customer_id, c.customer_name, count(o.order_id) AS order_count,
       sum(o.total_amount) AS total_spend
FROM kmogo.customers AS c
JOIN kmogo.orders AS o ON o.customer_id = c.customer_id
WHERE c.customer_id BETWEEN 4200 AND 4249
GROUP BY c.customer_id, c.customer_name
ORDER BY c.customer_id;
