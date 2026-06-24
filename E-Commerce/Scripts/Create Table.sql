-- 1. USER MANAGEMENT

CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    role VARCHAR(20) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE customer_profiles (
    customer_id SERIAL PRIMARY KEY,
    user_id INT UNIQUE NOT NULL,
    loyalty_points INT DEFAULT 0,
    preferred_address TEXT,
    date_of_birth DATE,

    FOREIGN KEY (user_id)
    REFERENCES users(user_id)
);

CREATE TABLE seller_profiles (
    seller_id SERIAL PRIMARY KEY,
    user_id INT UNIQUE NOT NULL,
    business_name VARCHAR(100) NOT NULL,
    gst_number VARCHAR(50) UNIQUE,
    commission_rate DECIMAL(5,2) DEFAULT 10.00,
    verification_status BOOLEAN DEFAULT FALSE,

    FOREIGN KEY (user_id)
    REFERENCES users(user_id)
);

CREATE TABLE addresses (
    address_id SERIAL PRIMARY KEY,
    user_id INT NOT NULL,
    address_line TEXT NOT NULL,
    city VARCHAR(100) NOT NULL,
    state VARCHAR(100) NOT NULL,
    country VARCHAR(100) NOT NULL,
    postal_code VARCHAR(20),
    address_type VARCHAR(20) NOT NULL,

    FOREIGN KEY (user_id)
    REFERENCES users(user_id)
);

-- 2. PRODUCT CATALOGUE


CREATE TABLE categories (
    category_id SERIAL PRIMARY KEY,
    category_name VARCHAR(100) NOT NULL,
    parent_category_id INT,

    FOREIGN KEY (parent_category_id)
    REFERENCES categories(category_id)
);

CREATE TABLE brands (
    brand_id SERIAL PRIMARY KEY,
    brand_name VARCHAR(100) UNIQUE NOT NULL,
    is_verified BOOLEAN DEFAULT FALSE
);

CREATE TABLE products (
    product_id SERIAL PRIMARY KEY,
    seller_id INT NOT NULL,
    brand_id INT,
    product_name VARCHAR(200) NOT NULL,
    sku VARCHAR(100) UNIQUE NOT NULL,
    slug VARCHAR(200) UNIQUE,
    base_price DECIMAL(10,2) NOT NULL,
    product_status VARCHAR(20) DEFAULT 'active',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (seller_id)
    REFERENCES seller_profiles(seller_id),

    FOREIGN KEY (brand_id)
    REFERENCES brands(brand_id)
);

CREATE TABLE product_categories (
    product_id INT,
    category_id INT,

    PRIMARY KEY (product_id, category_id),

    FOREIGN KEY (product_id)
    REFERENCES products(product_id),

    FOREIGN KEY (category_id)
    REFERENCES categories(category_id)
);

CREATE TABLE product_images (
    image_id SERIAL PRIMARY KEY,
    product_id INT NOT NULL,
    image_url TEXT NOT NULL,
    sort_order INT DEFAULT 1,
    is_primary BOOLEAN DEFAULT FALSE,

    FOREIGN KEY (product_id)
    REFERENCES products(product_id)
);


-- 3. INVENTORY


CREATE TABLE warehouses (
    warehouse_id SERIAL PRIMARY KEY,
    warehouse_name VARCHAR(100) NOT NULL,
    city VARCHAR(100) NOT NULL,
    state VARCHAR(100) NOT NULL,
    capacity INT NOT NULL
);

CREATE TABLE inventory (
    inventory_id SERIAL PRIMARY KEY,
    product_id INT NOT NULL,
    warehouse_id INT NOT NULL,
    quantity_available INT DEFAULT 0,
    reorder_threshold INT DEFAULT 10,

    FOREIGN KEY (product_id)
    REFERENCES products(product_id),

    FOREIGN KEY (warehouse_id)
    REFERENCES warehouses(warehouse_id)
);

CREATE TABLE stock_movements (
    movement_id SERIAL PRIMARY KEY,
    product_id INT NOT NULL,
    warehouse_id INT NOT NULL,
    movement_type VARCHAR(20) NOT NULL,
    quantity INT NOT NULL,
    movement_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (product_id)
    REFERENCES products(product_id),

    FOREIGN KEY (warehouse_id)
    REFERENCES warehouses(warehouse_id)
);

-- 4. ORDERS


CREATE TABLE cart (
    cart_id SERIAL PRIMARY KEY,
    customer_id INT UNIQUE NOT NULL,
    expires_at TIMESTAMP,

    FOREIGN KEY (customer_id)
    REFERENCES customer_profiles(customer_id)
);

CREATE TABLE cart_items (
    cart_item_id SERIAL PRIMARY KEY,
    cart_id INT NOT NULL,
    product_id INT NOT NULL,
    quantity INT DEFAULT 1,

    FOREIGN KEY (cart_id)
    REFERENCES cart(cart_id),

    FOREIGN KEY (product_id)
    REFERENCES products(product_id)
);

CREATE TABLE orders (
    order_id SERIAL PRIMARY KEY,
    customer_id INT NOT NULL,
    order_status VARCHAR(30) DEFAULT 'pending',
    total_amount DECIMAL(10,2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (customer_id)
    REFERENCES customer_profiles(customer_id)
);

CREATE TABLE order_items (
    order_item_id SERIAL PRIMARY KEY,
    order_id INT NOT NULL,
    product_id INT NOT NULL,
    quantity INT NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,

    FOREIGN KEY (order_id)
    REFERENCES orders(order_id),

    FOREIGN KEY (product_id)
    REFERENCES products(product_id)
);

-- 5. PAYMENTS


CREATE TABLE payments (
    payment_id SERIAL PRIMARY KEY,
    order_id INT NOT NULL,
    payment_method VARCHAR(50) NOT NULL,
    payment_status VARCHAR(30) DEFAULT 'pending',
    gateway_reference VARCHAR(100),
    amount DECIMAL(10,2) NOT NULL,
    paid_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (order_id)
    REFERENCES orders(order_id)
);

CREATE TABLE payment_transactions (
    transaction_id SERIAL PRIMARY KEY,
    payment_id INT NOT NULL,
    transaction_status VARCHAR(30),
    transaction_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (payment_id)
    REFERENCES payments(payment_id)
);

CREATE TABLE invoices (
    invoice_id SERIAL PRIMARY KEY,
    order_id INT NOT NULL,
    invoice_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    total_amount DECIMAL(10,2) NOT NULL,

    FOREIGN KEY (order_id)
    REFERENCES orders(order_id)
);


-- 6. DISCOUNTS


CREATE TABLE coupons (
    coupon_id SERIAL PRIMARY KEY,
    coupon_code VARCHAR(50) UNIQUE NOT NULL,
    discount_type VARCHAR(20) NOT NULL,
    discount_value DECIMAL(10,2) NOT NULL,
    max_uses INT,
    expiry_date DATE,
    minimum_order_value DECIMAL(10,2)
);

CREATE TABLE coupon_usage (
    usage_id SERIAL PRIMARY KEY,
    coupon_id INT NOT NULL,
    customer_id INT NOT NULL,
    used_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (coupon_id)
    REFERENCES coupons(coupon_id),

    FOREIGN KEY (customer_id)
    REFERENCES customer_profiles(customer_id)
);


-- 7. REVIEWS & RATINGS


CREATE TABLE reviews (
    review_id SERIAL PRIMARY KEY,
    customer_id INT NOT NULL,
    product_id INT NOT NULL,
    title VARCHAR(200),
    review_body TEXT,
    verified_purchase BOOLEAN DEFAULT FALSE,
    helpful_votes INT DEFAULT 0,

    FOREIGN KEY (customer_id)
    REFERENCES customer_profiles(customer_id),

    FOREIGN KEY (product_id)
    REFERENCES products(product_id)
);

CREATE TABLE ratings (
    rating_id SERIAL PRIMARY KEY,
    customer_id INT NOT NULL,
    product_id INT NOT NULL,
    rating_value INT CHECK (rating_value BETWEEN 1 AND 5),
    moderation_status VARCHAR(20) DEFAULT 'pending',

    FOREIGN KEY (customer_id)
    REFERENCES customer_profiles(customer_id),

    FOREIGN KEY (product_id)
    REFERENCES products(product_id)
);

-- 8. RETURNS & REFUNDS

CREATE TABLE returns (
    return_id SERIAL PRIMARY KEY,
    order_item_id INT NOT NULL,
    reason_code TEXT,
    item_condition VARCHAR(100),
    returned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (order_item_id)
    REFERENCES order_items(order_item_id)
);

CREATE TABLE refunds (
    refund_id SERIAL PRIMARY KEY,
    return_id INT NOT NULL,
    refund_amount DECIMAL(10,2) NOT NULL,
    refund_method VARCHAR(50),
    processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (return_id)
    REFERENCES returns(return_id)
);


