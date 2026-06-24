-- 1 & 2. Place Order Transaction containing Concurrency Race Controls 
CREATE OR REPLACE PROCEDURE place_order(
    p_customer_id INT,
    p_cart_id INT,
    p_coupon_code VARCHAR(50) DEFAULT NULL
)
LANGUAGE plpgsql AS $$
DECLARE
    v_cart_item RECORD;
    v_order_id INT;
    v_total_amount DECIMAL(10,2) := 0.00;
    v_item_price DECIMAL(10,2);
    v_discount DECIMAL(10,2) := 0.00;
    v_stock INT;
BEGIN
    -- Concurrency Row-level validation using direct locking loops 
    FOR v_cart_item IN SELECT product_id, quantity FROM cart_items WHERE cart_id = p_cart_id LOOP
        SELECT quantity_available INTO v_stock 
        FROM inventory 
        WHERE product_id = v_cart_item.product_id 
        FOR UPDATE; -- Prevents multi-customer race conditions 

        IF v_stock < v_cart_item.quantity THEN
            RAISE EXCEPTION 'Insufficient item stock for transaction isolation.';
        END IF;
    END LOOP;

    -- Calculate Gross Total
    SELECT COALESCE(SUM(ci.quantity * p.base_price), 0.00) INTO v_total_amount
    FROM cart_items ci
    JOIN products p ON ci.product_id = p.product_id
    WHERE ci.cart_id = p_cart_id;

    -- Coupon Valuation Rules
    IF p_coupon_code IS NOT NULL THEN
        SELECT discount_value INTO v_discount FROM coupons 
        WHERE coupon_code = p_coupon_code AND expiry_date >= CURRENT_DATE LIMIT 1;
        v_total_amount := v_total_amount - COALESCE(v_discount, 0.00);
    END IF;

    -- Process insertions
    INSERT INTO orders (customer_id, order_status, total_amount, created_at)
    VALUES (p_customer_id, 'pending', GREATEST(v_total_amount, 0.00), CURRENT_TIMESTAMP)
    RETURNING order_id INTO v_order_id;

    -- Populate individual order lines
    for v_cart_item IN SELECT ci.product_id, ci.quantity, p.base_price FROM cart_items ci JOIN products p ON ci.product_id = p.product_id WHERE ci.cart_id = p_cart_id LOOP
        INSERT INTO order_items (order_id, product_id, quantity, unit_price)
        VALUES (v_order_id, v_cart_item.product_id, v_cart_item.quantity, v_cart_item.base_price);
    END LOOP;

    -- Flush Cart instance
    DELETE FROM cart_items WHERE cart_id = p_cart_id;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK; -- 14. Full backtrace cleanup on runtime crash 
        RAISE;
END;
$$;

-- 3. Cancel Order Stored Procedure Execution 
CREATE OR REPLACE PROCEDURE cancel_order(p_order_id INT)
LANGUAGE plpgsql AS $$
DECLARE
    v_order_date TIMESTAMP;
BEGIN
    SELECT created_at INTO v_order_date FROM orders WHERE order_id = p_order_id;
    
    -- Check window limit conditions (24 hours) 
    IF v_order_date < (CURRENT_TIMESTAMP - INTERVAL '24 hours') THEN
        RAISE EXCEPTION 'Cancellation period has closed.';
    END IF;

    -- Trigger auto-rollback features through database engine triggers
    UPDATE orders SET order_status = 'cancelled' WHERE order_id = p_order_id;
END;
$$;

-- 4. Refund Payment 
CREATE OR REPLACE PROCEDURE refund_payment(p_order_id INT, p_amount DECIMAL(10,2))
LANGUAGE plpgsql AS $$
DECLARE
    v_payment_id INT;
    v_orig_amount DECIMAL(10,2);
BEGIN
    SELECT payment_id, amount INTO v_payment_id, v_orig_amount FROM payments WHERE order_id = p_order_id;
    
    IF p_amount > v_orig_amount THEN
        RAISE EXCEPTION 'Refund bounds overflow execution threshold.';
    END IF;

    UPDATE payments SET payment_status = 'refunded' WHERE payment_id = v_payment_id;
END;
$$;

-- 5. Update Inventory Explicit Auditing Log 
CREATE OR REPLACE PROCEDURE update_inventory(p_product_id INT, p_warehouse_id INT, p_delta INT)
LANGUAGE plpgsql AS $$
DECLARE
    v_current_stock INT;
BEGIN
    SELECT quantity_available INTO v_current_stock FROM inventory WHERE product_id = p_product_id AND warehouse_id = p_warehouse_id;
    
    IF (v_current_stock + p_delta) < 0 THEN
        RAISE EXCEPTION 'Negative capacity limits breached.';
    END IF;

    UPDATE inventory SET quantity_available = quantity_available + p_delta WHERE product_id = p_product_id AND warehouse_id = p_warehouse_id;
    
    INSERT INTO stock_movements(product_id, warehouse_id, movement_type, quantity)
    VALUES (p_product_id, p_warehouse_id, CASE WHEN p_delta > 0 THEN 'stock_in' ELSE 'stock_out' END, ABS(p_delta));
END;
$$;

-- 6. Apply Coupon Validation Pipeline 
CREATE OR REPLACE PROCEDURE apply_coupon(p_coupon_code VARCHAR(50), p_order_val DECIMAL(10,2))
LANGUAGE plpgsql AS $$
DECLARE
    v_coupon RECORD;
BEGIN
    SELECT * INTO v_coupon FROM coupons WHERE coupon_code = p_coupon_code;
    IF v_coupon IS NULL OR v_coupon.expiry_date < CURRENT_DATE OR p_order_val < v_coupon.minimum_order_value THEN
        RAISE EXCEPTION 'Coupon validation policies failed.';
    END IF;
END;
$$;

-- 7. Mark Order Delivered Pipeline 
CREATE OR REPLACE PROCEDURE mark_order_delivered(p_order_id INT)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE orders SET order_status = 'delivered' WHERE order_id = p_order_id;
    -- Automatically sparks trg_after_payment_success mechanisms if success state conditions tie inside the pipeline paths
END;
$$;

-- 15. Complete Process Return Transaction Suite 
CREATE OR REPLACE PROCEDURE process_return(p_order_item_id INT, p_reason TEXT)
LANGUAGE plpgsql AS $$
DECLARE
    v_ret_id INT;
    v_ord_id INT;
    v_refund_val DECIMAL(10,2);
BEGIN
    SELECT order_id, (quantity * unit_price) INTO v_ord_id, v_refund_val FROM order_items WHERE order_item_id = p_order_item_id;
    
    INSERT INTO returns (order_item_id, reason_code, item_condition)
    VALUES (p_order_item_id, p_reason, 'Returned to Hub')
    RETURNING return_id INTO v_ret_id;
    
    INSERT INTO refunds (return_id, refund_amount, refund_method)
    VALUES (v_ret_id, v_refund_val, 'original_gateway_wallet');
    
    CALL refund_payment(v_ord_id, v_refund_val);
END;
$$;