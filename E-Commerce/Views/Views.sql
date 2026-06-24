-- 1. Seller Dashboard View
-- Displays total revenue, order count, average rating, and top product by units sold per vendor.
CREATE OR REPLACE VIEW seller_dashboard_view AS
WITH seller_metrics AS (
    SELECT 
        p.seller_id,
        COALESCE(SUM(oi.quantity * oi.unit_price), 0.00) AS total_revenue,
        COUNT(DISTINCT oi.order_id) AS order_count
    FROM products p
    LEFT JOIN order_items oi ON p.product_id = oi.product_id
    LEFT JOIN orders o ON oi.order_id = o.order_id AND o.order_status != 'cancelled'
    GROUP BY p.seller_id
),
seller_avg_rating AS (
    SELECT 
        p.seller_id,
        ROUND(AVG(r.rating_value), 2) AS average_rating
    FROM products p
    LEFT JOIN ratings r ON p.product_id = r.product_id
    WHERE r.moderation_status = 'approved' OR r.moderation_status IS NULL
    GROUP BY p.seller_id
),
seller_top_product AS (
    SELECT 
        seller_id,
        product_id,
        row_num
    FROM (
        SELECT 
            p.seller_id,
            p.product_id,
            SUM(oi.quantity) as total_units,
            ROW_NUMBER() OVER (PARTITION BY p.seller_id ORDER BY SUM(oi.quantity) DESC NULLS LAST) as row_num
        FROM products p
        LEFT JOIN order_items oi ON p.product_id = oi.product_id
        GROUP BY p.seller_id, p.product_id
    ) t WHERE row_num = 1
)
SELECT 
    sp.seller_id,
    sp.business_name,
    sm.total_revenue,
    sm.order_count,
    COALESCE(sar.average_rating, 0.00) AS average_rating,
    stp.product_id AS top_product_id
FROM seller_profiles sp
LEFT JOIN seller_metrics sm ON sp.seller_id = sm.seller_id
LEFT JOIN seller_avg_rating sar ON sp.seller_id = sar.seller_id
LEFT JOIN seller_top_product stp ON sp.seller_id = stp.seller_id;

-- 2. Monthly Revenue View
-- Revenue grouped by seller and month, including month-over-month growth percentage.
CREATE OR REPLACE VIEW monthly_revenue_view AS
WITH monthly_sales AS (
    SELECT 
        p.seller_id,
        sp.business_name,
        DATE_TRUNC('month', o.created_at) AS sales_month,
        SUM(oi.quantity * oi.unit_price) AS current_month_revenue
    FROM seller_profiles sp
    JOIN products p ON sp.seller_id = p.seller_id
    JOIN order_items oi ON p.product_id = oi.product_id
    JOIN orders o ON oi.order_id = o.order_id
    WHERE o.order_status = 'completed'
    GROUP BY p.seller_id, sp.business_name, DATE_TRUNC('month', o.created_at)
),
lagged_sales AS (
    SELECT 
        seller_id,
        business_name,
        sales_month,
        current_month_revenue,
        LAG(current_month_revenue) OVER (PARTITION BY seller_id ORDER BY sales_month) AS previous_month_revenue
    FROM monthly_sales
)
SELECT 
    seller_id,
    business_name,
    TO_CHAR(sales_month, 'YYYY-MM') AS month,
    current_month_revenue AS revenue,
    COALESCE(previous_month_revenue, 0.00) AS previous_month_revenue,
    ROUND(
        CASE 
            WHEN previous_month_revenue IS NULL OR previous_month_revenue = 0 THEN 0.00
            ELSE ((current_month_revenue - previous_month_revenue) / previous_month_revenue) * 100.00
        END, 2
    ) AS mom_growth_percentage
FROM lagged_sales;

-- 3. Low Stock View
-- Highlights item alerts falling underneath safety buffer values per storage warehouse.
CREATE OR REPLACE VIEW low_stock_view AS
SELECT 
    i.inventory_id,
    p.product_id,
    p.product_name,
    p.sku,
    i.quantity_available,
    i.reorder_threshold,
    w.warehouse_id,
    w.warehouse_name,
    w.city,
    w.state
FROM inventory i
JOIN products p ON i.product_id = p.product_id
JOIN warehouses w ON i.warehouse_id = w.warehouse_id
WHERE i.quantity_available < i.reorder_threshold;

-- 4. Customer Order History View
-- Centralizes purchase profiles containing structural status flows.
CREATE OR REPLACE VIEW customer_order_history_view AS
SELECT 
    cp.customer_id,
    u.full_name AS customer_name,
    o.order_id,
    o.total_amount,
    o.order_status,
    o.created_at AS order_date,
    COALESCE(p.payment_status, 'unpaid') AS payment_status,
    COALESCE(r.item_condition, 'N/A') AS return_status
FROM customer_profiles cp
JOIN users u ON cp.user_id = u.user_id
JOIN orders o ON cp.customer_id = o.customer_id
LEFT JOIN payments p ON o.order_id = p.order_id
LEFT JOIN order_items oi ON o.order_id = oi.order_id
LEFT JOIN returns r ON oi.order_item_id = r.order_item_id;

-- 5. Abandoned Cart View
-- Gathers customer contacts holding open shopping instances unrevised for over 24 hours.
CREATE OR REPLACE VIEW abandoned_cart_view AS
SELECT 
    c.cart_id,
    u.email AS customer_email,
    cp.customer_id,
    COUNT(ci.cart_item_id) AS item_count,
    SUM(ci.quantity * p.base_price) AS total_cart_value,
    c.expires_at AS cart_expiration_time
FROM cart c
JOIN cart_items ci ON c.cart_id = ci.cart_id
JOIN products p ON ci.product_id = p.product_id
JOIN customer_profiles cp ON c.customer_id = cp.customer_id
JOIN users u ON cp.user_id = u.user_id
WHERE c.expires_at < (CURRENT_TIMESTAMP - INTERVAL '24 hours')
  AND c.customer_id NOT IN (SELECT DISTINCT customer_id FROM orders WHERE created_at > c.expires_at - INTERVAL '24 hours')
GROUP BY c.cart_id, u.email, cp.customer_id, c.expires_at;