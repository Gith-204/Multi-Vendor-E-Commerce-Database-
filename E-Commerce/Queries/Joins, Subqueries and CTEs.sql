-- 2.1 Four-Table Inner Join for Complete Product Mapping [cite: 48, 49]
SELECT p.product_id, p.product_name, sp.business_name AS seller_name, b.brand_name, c.category_name
FROM products p
INNER JOIN seller_profiles sp ON p.seller_id = sp.seller_id
INNER JOIN brands b ON p.brand_id = b.brand_id
INNER JOIN product_categories pc ON p.product_id = pc.product_id
INNER JOIN categories c ON pc.category_id = c.category_id;

-- 2.2 Left Join Null-Check for Unproductive Customers [cite: 50, 51]
SELECT cp.customer_id, u.full_name, u.email
FROM customer_profiles cp
INNER JOIN users u ON cp.user_id = u.user_id
LEFT JOIN orders o ON cp.customer_id = o.customer_id
WHERE o.order_id IS NULL;

-- 2.3 Left Join Aggregate for Seller Product Distribution [cite: 52, 53, 54]
SELECT sp.seller_id, sp.business_name, COUNT(p.product_id) AS total_products
FROM seller_profiles sp
LEFT JOIN products p ON sp.seller_id = p.seller_id
GROUP BY sp.seller_id, sp.business_name;

-- 2.4 Multi-Table Order Ledger Join [cite: 55, 56]
SELECT o.order_id, u.full_name AS customer_name, sp.business_name AS seller_name, o.total_amount
FROM orders o
JOIN customer_profiles cp ON o.customer_id = cp.customer_id
JOIN users u ON cp.user_id = u.user_id
JOIN order_items oi ON o.order_id = oi.order_id
JOIN products p ON oi.product_id = p.product_id
JOIN seller_profiles sp ON p.seller_id = sp.seller_id;

-- 2.5 Ordered At-Least-Once Subquery (EXISTS) [cite: 57, 58]
SELECT p.product_id, p.product_name 
FROM products p
WHERE EXISTS (SELECT 1 FROM order_items oi WHERE oi.product_id = p.product_id);

-- 2.6 Never Ordered Subquery (NOT EXISTS) [cite: 59, 60]
SELECT p.product_id, p.product_name 
FROM products p
WHERE NOT EXISTS (SELECT 1 FROM order_items oi WHERE oi.product_id = p.product_id);

-- 2.7 Correlated Pricing Outlier Scanning [cite: 61, 62]
SELECT p.product_id, p.product_name, p.base_price, pc.category_id
FROM products p
JOIN product_categories pc ON p.product_id = pc.product_id
WHERE p.base_price > (
    SELECT AVG(p2.base_price) 
    FROM products p2
    JOIN product_categories pc2 ON p2.product_id = pc2.product_id
    WHERE pc2.category_id = pc.category_id
);

-- 2.8 Top 3 Most Expensive Products Per Seller [cite: 63, 64]
SELECT seller_id, product_id, product_name, base_price
FROM (
    SELECT seller_id, product_id, product_name, base_price,
           ROW_NUMBER() OVER (PARTITION BY seller_id ORDER BY base_price DESC) as rank_order
    FROM products
) t WHERE rank_order <= 3;

-- 2.9 Unbroken 6-Month Purchase Frequency Filter [cite: 65, 67]
SELECT o.customer_id, u.full_name, COUNT(DISTINCT TO_CHAR(o.created_at, 'YYYY-MM')) as active_months
FROM orders o
JOIN customer_profiles cp ON o.customer_id = cp.customer_id
JOIN users u ON cp.user_id = u.user_id
WHERE o.created_at >= CURRENT_TIMESTAMP - INTERVAL '6 months'
GROUP BY o.customer_id, u.full_name
HAVING COUNT(DISTINCT TO_CHAR(o.created_at, 'YYYY-MM')) = 6;

-- 2.10 Left Join Unused Coupons Scan [cite: 66, 68]
SELECT c.coupon_id, c.coupon_code
FROM coupons c
LEFT JOIN coupon_usage cu ON c.coupon_id = cu.coupon_id
WHERE cu.usage_id IS NULL;

-- 2.11 Top Velocity Volume Item per Seller (CTE) [cite: 69, 70]
WITH seller_sales AS (
    SELECT p.seller_id, p.product_id, p.product_name, SUM(oi.quantity) as total_sold,
           DENSE_RANK() OVER(PARTITION BY p.seller_id ORDER BY SUM(oi.quantity) DESC) as sales_rank
    FROM products p
    JOIN order_items oi ON p.product_id = oi.product_id
    GROUP BY p.seller_id, p.product_id, p.product_name
)
SELECT seller_id, product_id, product_name, total_sold FROM seller_sales WHERE sales_rank = 1;

-- 2.12 Payment Transaction Audit Matching [cite: 71, 72]
SELECT o.order_id, o.customer_id, p.payment_id, pt.transaction_id, pt.transaction_status
FROM orders o
JOIN payments p ON o.order_id = p.order_id
JOIN payment_transactions pt ON p.payment_id = pt.payment_id
WHERE pt.transaction_status = 'failed' OR p.payment_status = 'failed';

-- 2.13 Consolidated Product Quality Left Join Summary [cite: 73, 74]
SELECT p.product_id, p.product_name, 
       ROUND(AVG(r.rating_value), 2) AS avg_rating, 
       COUNT(DISTINCT rev.review_id) AS total_reviews
FROM products p
LEFT JOIN ratings r ON p.product_id = r.product_id
LEFT JOIN reviews rev ON p.product_id = rev.product_id
GROUP BY p.product_id, p.product_name;

-- 2.14 Platform Revenue Outlier Extraction (CTE) [cite: 75, 76]
WITH seller_revenue AS (
    SELECT p.seller_id, SUM(oi.quantity * oi.unit_price) as gross_revenue
    FROM products p
    JOIN order_items oi ON p.product_id = oi.product_id
    GROUP BY p.seller_id
),
platform_average AS (
    SELECT AVG(gross_revenue) as avg_revenue FROM seller_revenue
)
SELECT sr.seller_id, sr.gross_revenue 
FROM seller_revenue sr, platform_average pa 
WHERE sr.gross_revenue > pa.avg_revenue;

-- 2.15 High-Velocity Repeat Customers Definition (CTE) [cite: 77, 78]
WITH loyal_customers AS (
    SELECT customer_id, COUNT(order_id) as completed_orders
    FROM orders
    WHERE order_status = 'completed'
    GROUP BY customer_id
)
SELECT lc.customer_id, u.full_name, lc.completed_orders
FROM loyal_customers lc
JOIN customer_profiles cp ON lc.customer_id = cp.customer_id
JOIN users u ON cp.user_id = u.user_id
WHERE lc.completed_orders > 5;

-- 2.16 Full Category Structural Hierarchy Resolution (Recursive CTE) [cite: 79, 80]
WITH RECURSIVE hierarchy_path AS (
    SELECT category_id, category_name, parent_category_id, text(category_name) AS structural_path
    FROM categories
    WHERE parent_category_id IS NULL
    UNION ALL
    SELECT c.category_id, c.category_name, c.parent_category_id, 
           text(hp.structural_path || ' > ' || c.category_name)
    FROM categories c
    JOIN hierarchy_path hp ON c.parent_category_id = hp.category_id
)
SELECT category_id, structural_path FROM hierarchy_path ORDER BY structural_path;

-- 2.17 Returned Items Processing Log [cite: 83, 84]
SELECT r.return_id, u.full_name as customer_name, p.product_name, r.reason_code, ref.refund_amount
FROM returns r
JOIN order_items oi ON r.order_item_id = oi.order_item_id
JOIN orders o ON oi.order_id = o.order_id
JOIN customer_profiles cp ON o.customer_id = cp.customer_id
JOIN users u ON cp.user_id = u.user_id
JOIN products p ON oi.product_id = p.product_id
LEFT JOIN refunds ref ON r.return_id = ref.return_id;

-- 2.18 Critical At-Risk Quality Warning Flags [cite: 85, 86]
SELECT DISTINCT sp.seller_id, sp.business_name
FROM seller_profiles sp
JOIN products p ON sp.seller_id = p.seller_id
JOIN ratings r ON p.product_id = r.product_id
WHERE r.rating_value = 1;

-- 2.19 Unique Market Footprint Rank (CTE) [cite: 87, 88]
WITH seller_reach AS (
    SELECT p.seller_id, COUNT(DISTINCT o.customer_id) as unique_buyers,
           ROW_NUMBER() OVER(ORDER BY COUNT(DISTINCT o.customer_id) DESC) as performance_rank
    FROM products p
    JOIN order_items oi ON p.product_id = oi.product_id
    JOIN orders o ON oi.order_id = o.order_id
    GROUP BY p.seller_id
)
SELECT seller_id, unique_buyers FROM seller_reach WHERE performance_rank <= 10;

-- 2.20 Unconverted Cart Pipeline Summary [cite: 89, 90]
SELECT u.email, p.product_name, EXTRACT(DAY FROM (CURRENT_TIMESTAMP - c.expires_at)) + 1 AS cart_age_days
FROM cart c
JOIN cart_items ci ON c.cart_id = ci.cart_id
JOIN products p ON ci.product_id = p.product_id
JOIN customer_profiles cp ON c.customer_id = cp.customer_id
JOIN users u ON cp.user_id = u.user_id
WHERE c.customer_id NOT IN (SELECT DISTINCT customer_id FROM orders);

