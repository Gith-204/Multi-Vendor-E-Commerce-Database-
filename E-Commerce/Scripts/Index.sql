-- 6. High-traffic Foreign Key B-Tree Optimization Layer 
CREATE INDEX idx_orders_fk_customer ON orders(customer_id);
CREATE INDEX idx_order_items_fk_order ON order_items(order_id);
CREATE INDEX idx_order_items_fk_product ON order_items(product_id);
CREATE INDEX idx_payments_fk_order ON payments(order_id);
CREATE INDEX idx_inventory_fk_product ON inventory(product_id);
CREATE INDEX idx_inventory_fk_warehouse ON inventory(warehouse_id);

-- 7. Composite Date Range Filter for Seller Operational Queries 
CREATE INDEX idx_products_seller_composite ON products(seller_id, created_at DESC);

-- 8. High-Performance Covering Index for Index-Only Scans 
CREATE INDEX idx_covering_order_items ON order_items(order_id) 
INCLUDE (product_id, quantity, unit_price);