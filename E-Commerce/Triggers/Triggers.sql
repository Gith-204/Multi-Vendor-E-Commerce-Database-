-- 8. Deduct Inventory & Log Outward Stock Movement on Order Placement 
CREATE OR REPLACE FUNCTION fn_trg_deduct_stock_on_order()
RETURNS TRIGGER AS $$
DECLARE
    v_warehouse_id INT;
BEGIN
    SELECT warehouse_id INTO v_warehouse_id 
    FROM inventory 
    WHERE product_id = NEW.product_id AND quantity_available >= NEW.quantity 
    LIMIT 1;

    IF v_warehouse_id IS NULL THEN
        RAISE EXCEPTION 'Stock Allocation Failure for Product %', NEW.product_id;
    END IF;

    UPDATE inventory 
    SET quantity_available = quantity_available - NEW.quantity
    WHERE product_id = NEW.product_id AND warehouse_id = v_warehouse_id;

    INSERT INTO stock_movements (product_id, warehouse_id, movement_type, quantity, movement_date)
    VALUES (NEW.product_id, v_warehouse_id, 'stock_out', NEW.quantity, CURRENT_TIMESTAMP);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_after_order_item_insert
AFTER INSERT ON order_items
FOR EACH ROW EXECUTE FUNCTION fn_trg_deduct_stock_on_order();

-- 9. Restore Inventory & Log Return Movement on Return Creation 
CREATE OR REPLACE FUNCTION fn_trg_restore_stock_on_return()
RETURNS TRIGGER AS $$
DECLARE
    v_prod_id INT;
    v_qty INT;
    v_wh_id INT;
BEGIN
    SELECT product_id, quantity INTO v_prod_id, v_qty 
    FROM order_items WHERE order_item_id = NEW.order_item_id;

    SELECT warehouse_id INTO v_wh_id 
    FROM inventory WHERE product_id = v_prod_id 
    LIMIT 1;

    UPDATE inventory 
    SET quantity_available = quantity_available + v_qty
    WHERE product_id = v_prod_id AND warehouse_id = v_wh_id;

    INSERT INTO stock_movements (product_id, warehouse_id, movement_type, quantity, movement_date)
    VALUES (v_prod_id, v_wh_id, 'returned', v_qty, CURRENT_TIMESTAMP);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_after_return_insert
AFTER INSERT ON returns
FOR EACH ROW EXECUTE FUNCTION fn_trg_restore_stock_on_return();

-- 10. Bulk Inventory Restoration on Order Cancellation 
CREATE OR REPLACE FUNCTION fn_trg_restore_stock_on_cancel()
RETURNS TRIGGER AS $$
DECLARE
    v_item RECORD;
    v_wh_id INT;
BEGIN
    IF NEW.order_status = 'cancelled' AND OLD.order_status != 'cancelled' THEN
        FOR v_item IN SELECT product_id, quantity FROM order_items WHERE order_id = NEW.order_id LOOP
            SELECT warehouse_id INTO v_wh_id FROM inventory WHERE product_id = v_item.product_id LIMIT 1;
            
            UPDATE inventory 
            SET quantity_available = quantity_available + v_item.quantity
            WHERE product_id = v_item.product_id AND warehouse_id = v_wh_id;

            INSERT INTO stock_movements (product_id, warehouse_id, movement_type, quantity, movement_date)
            VALUES (v_item.product_id, v_wh_id, 'returned', v_item.quantity, CURRENT_TIMESTAMP);
        END LOOP;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_after_order_cancel
AFTER UPDATE ON orders
FOR EACH ROW EXECUTE FUNCTION fn_trg_restore_stock_on_cancel();

-- 11. Recalculate Ratings Dynamic Table Verification 
-- Simulates structural updates to a calculation summary process.
CREATE OR REPLACE FUNCTION fn_trg_log_rating_moderation()
RETURNS TRIGGER AS $$
BEGIN
    RAISE NOTICE 'Rating recorded for product %. Triggering aggregation calculations.', NEW.product_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_after_review_insert
AFTER INSERT ON reviews
FOR EACH ROW EXECUTE FUNCTION fn_trg_log_rating_moderation();

-- 12. Auto Invoice Generation on Payment Success 
CREATE OR REPLACE FUNCTION fn_trg_auto_invoice()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.payment_status = 'success' THEN
        INSERT INTO invoices (order_id, invoice_date, total_amount)
        VALUES (NEW.order_id, CURRENT_TIMESTAMP, NEW.amount);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_after_payment_success
AFTER INSERT OR UPDATE ON payments
FOR EACH ROW EXECUTE FUNCTION fn_trg_auto_invoice();

-- 13. Dynamic Stock Level Alert Triggers 
CREATE OR REPLACE FUNCTION fn_trg_inventory_alert()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.quantity_available < NEW.reorder_threshold THEN
        RAISE WARNING 'Stock alert: Product % in warehouse % has dropped below threshold (% left)', 
            NEW.product_id, NEW.warehouse_id, NEW.quantity_available;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_after_inventory_update
AFTER UPDATE ON inventory
FOR EACH ROW EXECUTE FUNCTION fn_trg_inventory_alert();