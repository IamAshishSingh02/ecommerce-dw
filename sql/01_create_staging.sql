-- 01_create_staging.sql
-- Purpose: Create raw staging tables that mirror source CSVs 1:1
-- Pattern: All columns TEXT, no constraints, no indexes
-- Why: We trust nothing at the landing zone. Clean during transform.

-- Drop and recreate the staging schema for idempotency
-- (idempotency = you can re-run this script safely many times)
DROP SCHEMA IF EXISTS staging CASCADE;
CREATE SCHEMA staging;

-- 1. Customers
CREATE TABLE staging.customers (
  customer_id              TEXT,
  customer_unique_id       TEXT,
  customer_zip_code_prefix TEXT,
  customer_city            TEXT,
  customer_state           TEXT
);

-- 2. Orders
CREATE TABLE staging.orders (
  order_id                      TEXT,
  customer_id                   TEXT,
  order_status                  TEXT,
  order_purchase_timestamp      TEXT,
  order_approved_at             TEXT,
  order_delivered_carrier_date  TEXT,
  order_delivered_customer_date TEXT,
  order_estimated_delivery_date TEXT
);

-- 3. Order Items (one row per item per order — finest grain)
CREATE TABLE staging.order_items (
  order_id            TEXT,
  order_item_id       TEXT,
  product_id          TEXT,
  seller_id           TEXT,
  shipping_limit_date TEXT,
  price               TEXT,
  freight_value       TEXT
);

-- 4. Order Payments
CREATE TABLE staging.order_payments (
  order_id             TEXT,
  payment_sequential   TEXT,
  payment_type         TEXT,
  payment_installments TEXT,
  payment_value        TEXT
);

-- 5. Order Reviews
CREATE TABLE staging.order_reviews (
  review_id               TEXT,
  order_id                TEXT,
  review_score            TEXT,
  review_comment_title    TEXT,
  review_comment_message  TEXT,
  review_creation_date    TEXT,
  review_answer_timestamp TEXT
);

-- 6. Products
CREATE TABLE staging.products (
  product_id                 TEXT,
  product_category_name      TEXT,
  product_name_length        TEXT,
  product_description_length TEXT,
  product_photos_qty         TEXT,
  product_weight_g           TEXT,
  product_length_cm          TEXT,
  product_height_cm          TEXT,
  product_width_cm           TEXT
);

-- 7. Sellers
CREATE TABLE staging.sellers (
  seller_id              TEXT,
  seller_zip_code_prefix TEXT,
  seller_city            TEXT,
  seller_state           TEXT
);

-- 8. Geolocation
CREATE TABLE staging.geolocation (
  geolocation_zip_code_prefix TEXT,
  geolocation_lat             TEXT,
  geolocation_lng             TEXT,
  geolocation_city            TEXT,
  geolocation_state           TEXT
);

-- 9. Category Name Translation (Portuguese -> English)
CREATE TABLE staging.category_translation (
  product_category_name         TEXT,
  product_category_name_english TEXT
);

SELECT table_schema, table_name 
FROM information_schema.tables 
WHERE table_schema = 'staging'
ORDER BY table_name;