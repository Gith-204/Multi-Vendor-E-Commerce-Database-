-- 3.1 Category Financial Contribution Partition Ranking 
SELECT pc.category_id, p.product_id, p.product_name,
       SUM(oi.quantity * oi.unit_price) as total_revenue,
       RANK() OVER(PARTITION BY pc.category_id ORDER BY SUM(oi.quantity * oi.unit_price) DESC NULLS LAST) as internal_category_rank
FROM products p
JOIN product_categories pc ON p.product_id = pc.product_id
JOIN order_items oi ON p.product_id = oi.product_id
GROUP BY pc.category_id, p.product_id, p.product_name;

-- 3.2 Top 5 Performance Filtering Subquery Layer 
SELECT category_id, product_id, total_revenue, volume_rank
FROM (
    SELECT pc.category_id, p.product_id, SUM(oi.quantity * oi.unit_price) as total_revenue,
           ROW_NUMBER() OVER(PARTITION BY pc.category_id ORDER BY SUM(oi.quantity) DESC) as volume_rank
    FROM products p
    JOIN product_categories pc ON p.product_id = pc.product_id
    JOIN order_items oi ON p.product_id = oi.product_id
    GROUP BY pc.category_id, p.product_id
) t WHERE volume_rank <= 5;

-- 3.3 Customer Onboarding & Retention Sequencing 
SELECT customer_id, order_id, created_at,
       ROW_NUMBER() OVER(PARTITION BY customer_id ORDER BY created_at ASC) as historical_purchase_sequence
FROM orders;

-- 3.4 Rolling Monthly Revenue Build Partitioned by Seller 
SELECT p.seller_id, TO_CHAR(o.created_at, 'YYYY-MM') as sale_month,
       SUM(SUM(oi.quantity * oi.unit_price)) OVER(PARTITION BY p.seller_id ORDER BY TO_CHAR(o.created_at, 'YYYY-MM') ROWS UNBOUNDED PRECEDING) as running_total
FROM products p
JOIN order_items oi ON p.product_id = oi.product_id
JOIN orders o ON oi.order_id = o.order_id
GROUP BY p.seller_id, TO_CHAR(o.created_at, 'YYYY-MM');

-- 3.5 Period-Over-Period Revenue Variances 
WITH monthly_metrics AS (
    SELECT p.seller_id, TO_CHAR(o.created_at, 'YYYY-MM') as month_str, SUM(oi.quantity * oi.unit_price) as gross
    FROM products p JOIN order_items oi ON p.product_id = oi.product_id JOIN orders o ON oi.order_id = o.order_id GROUP BY p.seller_id, TO_CHAR(o.created_at, 'YYYY-MM')
)
SELECT seller_id, month_str, gross,
       LAG(gross) OVER(PARTITION BY seller_id ORDER BY month_str) as previous_month_gross
FROM monthly_metrics;

-- 3.6 Period-Over-Period Growth Rates Percentage 
WITH growth_metrics AS (
    SELECT p.seller_id, TO_CHAR(o.created_at, 'YYYY-MM') as month_str, SUM(oi.quantity * oi.unit_price) as gross
    FROM products p JOIN order_items oi ON p.product_id = oi.product_id JOIN orders o ON oi.order_id = o.order_id GROUP BY p.seller_id, TO_CHAR(o.created_at, 'YYYY-MM')
)
SELECT seller_id, month_str,
       ROUND(((gross - LAG(gross) OVER(PARTITION BY seller_id ORDER BY month_str)) / COALESCE(LAG(gross) OVER(PARTITION BY seller_id ORDER BY month_str), 1.0)), 4) * 100.0 as growth_pct
FROM growth_metrics;

-- 3.7 Contraction Downturn Alert Identifications 
WITH contraction_cte AS (
    SELECT p.seller_id, TO_CHAR(o.created_at, 'YYYY-MM') as month_str, SUM(oi.quantity * oi.unit_price) as gross,
           LAG(gross) OVER(PARTITION BY seller_id ORDER BY month_str) as prev
    FROM products p JOIN order_items oi ON p.product_id = oi.product_id JOIN orders o ON oi.order_id = o.order_id GROUP BY p.seller_id, TO_CHAR(o.created_at, 'YYYY-MM')
)
SELECT * FROM contraction_cte WHERE gross < prev;

-- 3.8 7-Day Rolling Moving Averages Engine 
SELECT order_id, created_at, total_amount,
       AVG(total_amount) OVER(ORDER BY created_at RANGE BETWEEN INTERVAL '6 days' PRECEDING AND CURRENT ROW) as rolling_7_day_avg
FROM orders;

-- 3.9 Lifetime Spend Segmentation (DENSE_RANK) 
SELECT customer_id, SUM(total_amount) as lifetime_spend,
       DENSE_RANK() OVER(ORDER BY SUM(total_amount) DESC) as platform_spend_rank
FROM orders
WHERE order_status = 'completed'
GROUP BY customer_id;

-- 3.10 Revenue Performance Quartile Distribution (NTILE) 
SELECT product_id, SUM(quantity * unit_price) as gross,
       NTILE(4) OVER(ORDER BY SUM(quantity * unit_price) DESC) as revenue_quartile
FROM order_items
GROUP BY product_id;

-- 3.11 Continuous Lifetime Bounds Processing Window 
SELECT DISTINCT customer_id,
       MIN(created_at) OVER(PARTITION BY customer_id) as registration_order_date,
       MAX(created_at) OVER(PARTITION BY customer_id) as latest_activity_date
FROM orders;

-- 3.12 Transaction Ticket Size Line Proportions 
SELECT order_id, product_id, (quantity * unit_price) as line_valuation,
       ROUND(((quantity * unit_price) / SUM(quantity * unit_price) OVER(PARTITION BY order_id)) * 100.0, 2) as order_contribution_pct
FROM order_items;

-- 3.13 Dynamic Order Intervals Scan (LEAD) 
SELECT customer_id, order_id, created_at as current_purchase,
       LEAD(created_at) OVER(PARTITION BY customer_id ORDER BY created_at ASC) as next_purchase,
       EXTRACT(DAY FROM (LEAD(created_at) OVER(PARTITION BY customer_id ORDER BY created_at ASC) - created_at)) as baseline_days_interval
FROM orders;

-- 3.14 Seasonal Peaks Identification 
WITH seasonal_cte AS (
    SELECT p.seller_id, TO_CHAR(o.created_at, 'YYYY-MM') as monthly_period, SUM(oi.quantity * oi.unit_price) as gross,
           RANK() OVER(PARTITION BY p.seller_id ORDER BY SUM(oi.quantity * oi.unit_price) DESC) as peak_rank
    FROM products p JOIN order_items oi ON p.product_id = oi.product_id JOIN orders o ON oi.order_id = o.order_id GROUP BY p.seller_id, TO_CHAR(o.created_at, 'YYYY-MM')
)
SELECT seller_id, monthly_period, gross FROM seasonal_cte WHERE peak_rank = 1;

-- 3.15 Structural Velocity Momentum Shifts 
WITH double_lag AS (
    SELECT p.product_id, TO_CHAR(o.created_at, 'YYYY-MM') as period, SUM(oi.quantity) as volume,
           RANK() OVER(PARTITION BY TO_CHAR(o.created_at, 'YYYY-MM') ORDER BY SUM(oi.quantity) DESC) as current_rank,
           LAG(RANK() OVER(PARTITION BY TO_CHAR(o.created_at, 'YYYY-MM') ORDER BY SUM(oi.quantity) DESC)) OVER(PARTITION BY p.product_id ORDER BY TO_CHAR(o.created_at, 'YYYY-MM')) as last_month_rank
    FROM products p JOIN order_items oi ON p.product_id = oi.product_id JOIN orders o ON oi.order_id = o.order_id GROUP BY p.product_id, TO_CHAR(o.created_at, 'YYYY-MM')
)
SELECT * FROM double_lag WHERE current_rank < last_month_rank;

-- 3.16 Daily Transaction Multiplier Progression 
SELECT DATE(created_at) as timeline_date, COUNT(order_id) as single_day_count,
       SUM(COUNT(order_id)) OVER(ORDER BY DATE(created_at) ROWS UNBOUNDED PRECEDING) as cumulative_orders_count
FROM orders
GROUP BY DATE(created_at);

-- 3.17 Market Position Percentile Matrix (PERCENT_RANK) 
WITH total_seller_rev AS (
    SELECT p.seller_id, SUM(oi.quantity * oi.unit_price) as gross
    FROM products p JOIN order_items oi ON p.product_id = oi.product_id GROUP BY p.seller_id
)
SELECT seller_id, gross, ROUND(PERCENT_RANK() OVER(ORDER BY gross ASC) * 100.0, 2) as platform_market_percentile
FROM total_seller_rev;

-- 3.18 Top 3 Category Leaders Matrix 
WITH partitioned_market AS (
    SELECT pc.category_id, p.seller_id, SUM(oi.quantity * oi.unit_price) as gross,
           DENSE_RANK() OVER(PARTITION BY pc.category_id ORDER BY SUM(oi.quantity * oi.unit_price) DESC) as tier_rank
    FROM products p 
    JOIN product_categories pc ON p.product_id = pc.product_id 
    JOIN order_items oi ON p.product_id = oi.product_id 
    GROUP BY pc.category_id, p.seller_id
)
SELECT * FROM partitioned_market WHERE tier_rank <= 3;

-- 3.19 Micro Ticket Deviations Filter 
SELECT order_id, customer_id, total_amount,
       AVG(total_amount) OVER() as overall_platform_average,
       (total_amount - AVG(total_amount) OVER()) as ticket_variance_deviation
FROM orders;

-- 3.20 Duplicate Basket Multiplier Purge 
WITH clean_basket AS (
    SELECT cart_item_id, cart_id, product_id, quantity,
           ROW_NUMBER() OVER(PARTITION BY cart_id, product_id ORDER BY cart_item_id DESC) as tracking_inversion
    FROM cart_items
)
SELECT cart_item_id, cart_id, product_id, quantity FROM clean_basket WHERE tracking_inversion = 1;