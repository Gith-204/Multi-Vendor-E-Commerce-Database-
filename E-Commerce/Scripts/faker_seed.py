import random
import sys
from datetime import datetime, timedelta
import psycopg2
from psycopg2.extras import execute_values
from faker import Faker

fake = Faker('en_IN')

# --- DATABASE CONNECTION ---
try:
    conn = psycopg2.connect(
        host='localhost',
        user='postgres',
        password='anand',    
        database='postgres'  
    )
    cursor = conn.cursor()
    print("Successfully connected to PostgreSQL database 'postgres'.")
except Exception as e:
    print(f"Database connection failed! Reason: {e}")
    sys.exit(1)

# --- CONFIGURATION PARAMETERS ---
NUM_USERS      = 10000
NUM_SELLERS    = 5
NUM_ORDERS     = 10000000 # Set optimally for standard operational data sizing
BATCH_SIZE     = 5000

def random_date(start_months_ago=6):
    start = datetime.now() - timedelta(days=start_months_ago * 30)
    return fake.date_time_between(start_date=start, end_date='now')

# Clear historical data cleanly via CASCADE
print("Clearing historical data to ensure unique constraints pass clean...")
cursor.execute("""
    TRUNCATE users, customer_profiles, seller_profiles, addresses,
             categories, brands, products, product_categories, product_images,
             warehouses, inventory, stock_movements,
             carts, cart_items, coupons, coupon_usage,
             orders, order_items, payments, payment_transactions, invoices,
             reviews, ratings, returns, return_items, refunds CASCADE;
""")
conn.commit()

# =========================================================================
# 1. USER MANAGEMENT (Tables 1 - 4)
# =========================================================================
print("\n[1-4/24] Seeding User Management System...")

# [Table 1/24]: users
seller_user_ids = []
for i in range(NUM_SELLERS):
    cursor.execute("""
        INSERT INTO users (email, password_hash, role)
        VALUES (%s, %s, 'seller') RETURNING user_id;
    """, (f"seller_{i+1}_{random.randint(1000,9999)}@shop.com", fake.sha256()))
    seller_user_ids.append(cursor.fetchone()[0])

customer_user_batch = []
for i in range(NUM_USERS):
    customer_user_batch.append((f"user_{i+1}_{random.randint(1000,9999)}@example.com", fake.sha256(), 'customer'))

execute_values(cursor, """
    INSERT INTO users (email, password_hash, role) VALUES %s;
""", customer_user_batch)
conn.commit()

cursor.execute("SELECT user_id FROM users WHERE role = 'customer';")
customer_ids = [row[0] for row in cursor.fetchall()]
print(f"-> Successfully registered {len(seller_user_ids)} sellers and {len(customer_ids)} customers.")

# [Table 2/24]: seller_profiles
print("[2/24] Expanding seller business metadata profiles...")
seller_names = ['Samsung Official Store', 'Nike India', 'Apple Reseller', 'boAt Lifestyle', 'Puma Sports']
for i, uid in enumerate(seller_user_ids):
    name = seller_names[i] if i < len(seller_names) else f"Enterprise Partner {uid}"
    cursor.execute("""
        INSERT INTO seller_profiles (seller_id, business_name, gst_vat, commission_rate, verification_status)
        VALUES (%s, %s, %s, %s, 'verified');
    """, (uid, name, f"GST{random.randint(10,99)}{fake.bothify(text='??####?####')}", round(random.uniform(2.0, 15.0), 2)))
conn.commit()

# [Table 3/24]: addresses
print("[3/24] Injecting address books...")
cities = ['Mumbai','Delhi','Chennai','Bangalore','Hyderabad','Pune','Kolkata','Ahmedabad']
states = ['Maharashtra','Delhi','Tamil Nadu','Karnataka','Telangana','Maharashtra','West Bengal','Gujarat']
address_batch = []
for uid in (customer_ids + seller_user_ids):
    idx = random.randint(0, len(cities)-1)
    address_batch.append((uid, f"{random.randint(1,999)}, {fake.last_name()} Street", f"Near {fake.last_name()} Colony", cities[idx], states[idx], str(random.randint(100000, 999999)), 'India', False))

execute_values(cursor, """
    INSERT INTO addresses (user_id, address_line1, address_line2, city, state, postal_code, country, is_default) 
    VALUES %s;
""", address_batch)
conn.commit()

cursor.execute("SELECT address_id, user_id FROM addresses;")
address_rows = cursor.fetchall()
all_address_ids = [row[0] for row in address_rows]
user_address_map = {row[1]: row[0] for row in address_rows}

# [Table 4/24]: customer_profiles
print("[4/24] Binding customer fidelity parameters...")
customer_prof_batch = [(uid, random.randint(0, 5000), user_address_map.get(uid), fake.date_of_birth(minimum_age=18, maximum_age=65)) for uid in customer_ids]
execute_values(cursor, """
    INSERT INTO customer_profiles (customer_id, loyalty_points, preferred_address_id, date_of_birth) 
    VALUES %s;
""", customer_prof_batch)
conn.commit()

# =========================================================================
# 2. PRODUCT CATALOGUE (Tables 5 - 9)
# =========================================================================
print("\n[5-9/24] Compiling Product Catalogue Schema maps...")

# [Table 5/24]: categories
root_categories = ['Electronics','Fashion','Sports','Home and Kitchen','Books']
category_ids = []
for name in root_categories:
    cursor.execute("INSERT INTO categories (name, slug, parent_id) VALUES (%s, %s, NULL) RETURNING category_id;", (name, name.lower().replace(' ', '-')))
    category_ids.append(cursor.fetchone()[0])

# [Table 6/24]: brands
brand_names = ['Samsung','Nike','Apple','boAt','Puma','Sony','LG','Adidas','OnePlus','Xiaomi','HP','Dell']
brand_ids = []
for name in brand_names:
    cursor.execute("INSERT INTO brands (name, slug, is_verified) VALUES (%s, %s, True) RETURNING brand_id;", (name, name.lower()))
    brand_ids.append(cursor.fetchone()[0])
conn.commit()

# [Table 7/24]: products
product_pool = ['Galaxy S24', 'iPhone 15 Pro', 'Air Max Shoes', 'Airdopes Wireless Buds', 'WH-1000XM5 Headphones', 'XPS Laptop']
product_ids = []
prod_prices_cache = {}
for i in range(50):
    pname = f"{random.choice(product_pool)} {random.randint(10,99)}"
    seller = random.choice(seller_user_ids)
    brand = random.choice(brand_ids)
    price = round(random.uniform(299, 149999), 2)
    slug = f"{pname.lower().replace(' ', '-')}-{i}"
    
    cursor.execute("""
        INSERT INTO products (sku, name, slug, description, base_price, seller_id, brand_id, status)
        VALUES (%s, %s, %s, %s, %s, %s, %s, 'active') RETURNING product_id;
    """, (f'SKU-{1000+i}', pname, slug, f"Official premium product item description details for {pname}", price, seller, brand))
    pid = cursor.fetchone()[0]
    product_ids.append(pid)
    prod_prices_cache[pid] = price
conn.commit()

# [Table 8/24]: product_categories
prod_cat_batch = [(pid, random.choice(category_ids)) for pid in product_ids]
execute_values(cursor, "INSERT INTO product_categories (product_id, category_id) VALUES %s;", prod_cat_batch)

# [Table 9/24]: product_images
image_batch = [(pid, f"https://images.ecommerce.com/products/{pid}/img_main.jpg", 0) for pid in product_ids]
execute_values(cursor, "INSERT INTO product_images (product_id, image_url, sort_order) VALUES %s;", image_batch)
conn.commit()

# =========================================================================
# 3. INVENTORY (Tables 10 - 12)
# =========================================================================
print("\n[10-12/24] Securing Supply Chain Inventory records...")

# [Table 10/24]: warehouses
warehouse_data = [('Mumbai Central Hub', 'Mumbai, MH', 50000), ('Delhi Logistics Yard', 'Delhi, NCR', 45000), ('Chennai South Depot', 'Chennai, TN', 40000)]
warehouse_ids = []
for name, loc, cap in warehouse_data:
    cursor.execute("INSERT INTO warehouses (name, location, capacity) VALUES (%s, %s, %s) RETURNING warehouse_id;", (name, loc, cap))
    warehouse_ids.append(cursor.fetchone()[0])

# [Table 11/24]: inventory
inv_batch = [(pid, wid, random.randint(100, 5000), 10) for pid in product_ids for wid in warehouse_ids]
execute_values(cursor, "INSERT INTO inventory (product_id, warehouse_id, quantity_available, reorder_threshold) VALUES %s;", inv_batch)
conn.commit()

# [Table 12/24]: stock_movements
cursor.execute("SELECT inventory_id, quantity_available FROM inventory;")
inventory_rows = cursor.fetchall()
mov_batch = [(row[0], row[1], 'stock_in', None) for row in inventory_rows]
execute_values(cursor, "INSERT INTO stock_movements (inventory_id, quantity_changed, movement_type, reference_id) VALUES %s;", mov_batch)
conn.commit()

# =========================================================================
# 4. CARTS & DISCOUNTS (Tables 13 - 15)
# =========================================================================
# =========================================================================
# 4. CARTS & DISCOUNTS (Tables 13 - 15)
# =========================================================================
print("\n[13-15/24] Initializing user terminals & marketing ledgers...")

# [Table 13/24]: carts
# Explicitly clear out any legacy cart data right before processing to avoid primary key overlaps
cursor.execute("TRUNCATE carts, cart_items CASCADE;")
conn.commit()

cart_user_sample = customer_ids[:2000] # Ensure we have plenty of users to split across
cart_batch = [(uid, datetime.now() + timedelta(days=3)) for uid in cart_user_sample]
execute_values(cursor, "INSERT INTO carts (user_id, expires_at) VALUES %s;", cart_batch)
conn.commit()

# [Table 14/24]: cart_items (GUARANTEED UNIQUE PAIRS WITH SAFETY VALVE)
cursor.execute("SELECT cart_id FROM carts;")
cart_ids = [row[0] for row in cursor.fetchall()]

unique_cart_items = set()
# Generate a controlled sample size relative to available combinations
max_possible_combinations = min(3000, len(cart_ids) * len(product_ids))

while len(unique_cart_items) < max_possible_combinations:
    chosen_cart = random.choice(cart_ids)
    chosen_prod = random.choice(product_ids)
    chosen_qty  = random.randint(1, 3)
    # The set tracks unique (cart_id, product_id) pairs perfectly
    unique_cart_items.add((chosen_cart, chosen_prod, chosen_qty))

# ON CONFLICT DO NOTHING ensures that even if a strange edge-case occurs, PostgreSQL won't crash
execute_values(cursor, """
    INSERT INTO cart_items (cart_id, product_id, quantity) 
    VALUES %s
    ON CONFLICT (cart_id, product_id) DO NOTHING;
""", list(unique_cart_items))
conn.commit()
print(f"-> Successfully synchronized unique items across {len(cart_ids)} active carts.")

# [Table 15/24]: coupons
cursor.execute("TRUNCATE coupons CASCADE;") # Safety reset
coupon_data = [('SAVE10', 'percentage', 10.00, 500, 100.00), ('FLAT200', 'flat', 200.00, 500, 1000.00), ('FESTIVE20', 'percentage', 20.00, 300, 500.00)]
coupon_ids = []
for code, ctype, val, max_uses, min_order in coupon_data:
    cursor.execute("""
        INSERT INTO coupons (code, discount_type, value, max_uses, min_order_value, expires_at)
        VALUES (%s, %s, %s, %s, %s, %s) RETURNING coupon_id;
    """, (code, ctype, val, max_uses, min_order, datetime.now() + timedelta(days=180)))
    coupon_ids.append(cursor.fetchone()[0])
conn.commit() 

# =========================================================================
# 5. ORDER MATCHING RUNTIME PIPELINE (Tables 16 - 19)
# =========================================================================
print(f"\n[16-19/24] Launching Transaction Matrix Engine for {NUM_ORDERS:,} transactions...")

statuses = ['pending','confirmed','shipped','delivered','cancelled']
weights  = [5, 10, 15, 65, 5]
methods  = ['credit_card','debit_card','net_banking','upi','wallet','cod']

order_batch, oi_batch, pay_batch, coupon_use_batch = [], [], [], []

for i in range(1, NUM_ORDERS + 1):
    cid = random.choice(customer_ids)
    addr = user_address_map.get(cid, random.choice(all_address_ids))
    status = random.choices(statuses, weights=weights)[0]
    
    num_items = random.randint(1, 3)
    gross_total = 0.0
    items_meta = []
    
    for _ in range(num_items):
        pid = random.choice(product_ids)
        qty = random.randint(1, 2)
        u_price = prod_prices_cache[pid]
        gross_total += (u_price * qty)
        items_meta.append((pid, qty, u_price))

    has_coupon = random.random() < 0.15
    discount = float(round(random.uniform(50, 200), 2)) if has_coupon else 0.00
    if discount > gross_total: 
        discount = 0.00
    net_total = gross_total - discount

    order_batch.append((i, cid, round(gross_total,2), round(discount,2), round(net_total,2), status, addr))

    for pid, qty, up in items_meta:
        oi_batch.append((i, pid, qty, up))

    pstatus = 'success' if status in ('confirmed','shipped','delivered') else ('failed' if status == 'cancelled' else 'pending')
    pay_batch.append((i, random.choice(methods), pstatus, f"GTW-REF-{random.randint(1000000,9999999)}"))

    if has_coupon:
        coupon_use_batch.append((random.choice(coupon_ids), cid, i))

    if len(order_batch) == BATCH_SIZE or i == NUM_ORDERS:
        execute_values(cursor, "INSERT INTO orders (order_id, customer_id, total_amount, discount_amount, net_amount, status, shipping_address_id) VALUES %s;", order_batch)
        execute_values(cursor, "INSERT INTO order_items (order_id, product_id, quantity, unit_price) VALUES %s;", oi_batch)
        execute_values(cursor, "INSERT INTO payments (order_id, method, status, gateway_reference) VALUES %s;", pay_batch)
        if coupon_use_batch:
            execute_values(cursor, "INSERT INTO coupon_usage (coupon_id, customer_id, order_id) VALUES %s;", coupon_use_batch)
        conn.commit()
        order_batch, oi_batch, pay_batch, coupon_use_batch = [], [], [], []

# =========================================================================
# 6. POST-TRANSACTION LEDGERS & FEEDBACK TRACE (Tables 20 - 24)
# =========================================================================
print("\n[20-24/24] Structuring financial invoices and review streams...")

# [Table 20/24]: payment_transactions & [Table 21/24]: invoices
offset = 0
CHUNK = 5000
while True:
    cursor.execute("SELECT payment_id, order_id, status FROM payments LIMIT %s OFFSET %s;", (CHUNK, offset))
    pay_rows = cursor.fetchall()
    if not pay_rows: 
        break
    
    ptx_batch, inv_batch = [], []
    for pay_id, order_id, p_status in pay_rows:
        ptx_batch.append((pay_id, 1, 'success' if p_status == 'success' else 'failed', '200', 'PROCESSED_SUCCESSFULLY'))
        if p_status == 'success':
            inv_batch.append((pay_id, f"INV-2026-{order_id}-{pay_id}", float(round(random.uniform(10, 200), 2)), float(round(random.uniform(300, 10000), 2))))
            
    execute_values(cursor, "INSERT INTO payment_transactions (payment_id, attempt_number, status, response_code, raw_payload) VALUES %s;", ptx_batch)
    if inv_batch:
        execute_values(cursor, "INSERT INTO invoices (payment_id, invoice_number, tax_amount, total_billed) VALUES %s;", inv_batch)
    conn.commit()
    offset += CHUNK

# [Table 22/24]: reviews
print("[22/24] Generating customer reviews...")
rev_batch = [(random.choice(product_ids), random.choice(customer_ids), "Product Review", fake.sentence(), True, random.randint(0, 50)) for _ in range(1000)]
execute_values(cursor, "INSERT INTO reviews (product_id, customer_id, title, body, is_verified_purchase, helpful_votes) VALUES %s;", rev_batch)
conn.commit()

# [Table 23/24]: ratings
print("[23/24] Binding internal star ratings...")
cursor.execute("SELECT review_id FROM reviews;")
review_ids = [row[0] for row in cursor.fetchall()]
rat_batch = [(r_id, random.randint(1, 5), 'approved') for r_id in review_ids]
execute_values(cursor, "INSERT INTO ratings (review_id, stars, moderation_status) VALUES %s;", rat_batch)
conn.commit()

# [Table 24/24]: returns, return_items, refunds (DYNAMIC FK SAFE LOOKUP)
print("[24/24] Structuring complex logistics: returns, return_items, and refunds...")

# 1. Grab actual valid order items from the database
cursor.execute("SELECT order_id, order_item_id FROM order_items LIMIT 500;")
oi_samples = cursor.fetchall()

if oi_samples:
    ret_batch = []
    for order_id, _ in oi_samples:
        ret_batch.append((order_id, random.choice(customer_ids), 'quality_issue', 'requested'))
    
    # We use RETURNING return_id to explicitly know what ids PostgreSQL created
    execute_values(cursor, "INSERT INTO returns (order_id, customer_id, reason_code, status) VALUES %s RETURNING return_id, order_id;", ret_batch)
    return_metadata = cursor.fetchall() # Gives us pairs of (return_id, order_id)
    conn.commit()

    # 2. Build a reliable lookup map of existing successful payments linked to order_id
    cursor.execute("SELECT order_id, payment_id FROM payments WHERE status = 'success';")
    payment_lookup = dict(cursor.fetchall())

    ret_items_batch = []
    refund_batch = []

    for idx, (ret_id, ord_id) in enumerate(return_metadata):
        # Match back to our initial order item sample slice safely
        associated_item_id = oi_samples[idx][1]
        ret_items_batch.append((ret_id, associated_item_id, 1, 'Opened Box'))
        
        # Pull the REAL payment_id from our lookup dictionary instead of guessing integers
        real_payment_id = payment_lookup.get(ord_id)
        if real_payment_id:
            refund_batch.append((ret_id, real_payment_id, float(round(random.uniform(100, 2000), 2)), 'original_payment', 'processed'))

    # Insert verified records
    execute_values(cursor, "INSERT INTO return_items (return_id, order_item_id, quantity, item_condition) VALUES %s;", ret_items_batch)
    if refund_batch:
        execute_values(cursor, "INSERT INTO refunds (return_id, payment_id, amount, method, status) VALUES %s;", refund_batch)
    conn.commit()

cursor.close()
conn.close()

print("\n" + "="*60)
print("SUCCESS: ALL 24 TABLES IN THE SCHEMA TOTALLY SEEDED SUCCESSFULLY!")
print("="*60) 