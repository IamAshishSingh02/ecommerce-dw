-- 04_transform_load.sql
-- Purpose: DML only — populate warehouse tables from staging
-- Pattern: Transform raw staging data into clean star schema

-- Runs on every data refresh (daily/hourly in production).
-- Requires: warehouse schema already created by 03_create_dim_fact.sql

-- Truncate all warehouse tables in reverse dependency order
-- (children first, parents last — opposite of FK direction)
-- RESTART IDENTITY resets the auto-increment counters
TRUNCATE TABLE 
  warehouse.fact_order_items,
  warehouse.dim_customer,
  warehouse.dim_product,
  warehouse.dim_seller,
  warehouse.dim_date,
  warehouse.dim_order_status,
  warehouse.dim_payment_type
RESTART IDENTITY CASCADE;


-- 1. dim_date — generated calendar
INSERT INTO warehouse.dim_date
SELECT
  TO_CHAR(d, 'YYYYMMDD')::INTEGER    AS date_sk,
  d::DATE                            AS date_actual,
  EXTRACT(YEAR FROM d)::SMALLINT     AS year,
  EXTRACT(QUARTER FROM d)::SMALLINT  AS quarter,
  EXTRACT(MONTH FROM d)::SMALLINT    AS month,
  TRIM(TO_CHAR(d, 'Month'))          AS month_name,
  EXTRACT(DAY FROM d)::SMALLINT      AS day,
  EXTRACT(DOW FROM d)::SMALLINT      AS day_of_week,
  TRIM(TO_CHAR(d, 'Day'))            AS day_name,
  EXTRACT(DOW FROM d) IN (0, 6)      AS is_weekend,
  EXTRACT(WEEK FROM d)::SMALLINT     AS week_of_year
FROM generate_series(
  '2016-01-01'::DATE,
  '2018-12-31'::DATE,
  '1 day'::INTERVAL
) AS d;


-- 2. dim_customer — deduplicated via customer_unique_id
INSERT INTO warehouse.dim_customer (
  customer_unique_id, customer_city, customer_state, customer_zip_code_prefix
)
SELECT DISTINCT ON (customer_unique_id)
  customer_unique_id,
  customer_city,
  customer_state,
  customer_zip_code_prefix
FROM staging.customers
WHERE customer_unique_id IS NOT NULL AND customer_unique_id != ''
ORDER BY customer_unique_id, customer_id;


-- 3. dim_product — enriched with English category translation
INSERT INTO warehouse.dim_product (
  product_id, product_category_pt, product_category_en,
  product_weight_g, product_length_cm, product_height_cm, 
  product_width_cm, product_photos_qty
)
SELECT 
  p.product_id,
  NULLIF(p.product_category_name, '')           AS product_category_pt,
  NULLIF(ct.product_category_name_english, '')  AS product_category_en,
  NULLIF(p.product_weight_g, '')::INTEGER       AS product_weight_g,
  NULLIF(p.product_length_cm, '')::INTEGER      AS product_length_cm,
  NULLIF(p.product_height_cm, '')::INTEGER      AS product_height_cm,
  NULLIF(p.product_width_cm, '')::INTEGER       AS product_width_cm,
  NULLIF(p.product_photos_qty, '')::SMALLINT    AS product_photos_qty
FROM staging.products p
LEFT JOIN staging.category_translation ct ON p.product_category_name = ct.product_category_name
WHERE p.product_id IS NOT NULL AND p.product_id != '';


-- 4. dim_seller
INSERT INTO warehouse.dim_seller (
  seller_id, seller_city, seller_state, seller_zip_code_prefix
)
SELECT 
  seller_id, seller_city, seller_state, seller_zip_code_prefix
FROM staging.sellers
WHERE seller_id IS NOT NULL AND seller_id != '';


-- 5. dim_order_status
INSERT INTO warehouse.dim_order_status (order_status)
SELECT DISTINCT order_status
FROM staging.orders
WHERE order_status IS NOT NULL AND order_status != ''
ORDER BY order_status;


-- 6. dim_payment_type
INSERT INTO warehouse.dim_payment_type (payment_type)
SELECT DISTINCT payment_type
FROM staging.order_payments
WHERE payment_type IS NOT NULL AND payment_type != '';


-- 7. fact_order_items — the centerpiece
-- Grain: one row per item per order

-- Technique: 
--   - CTE aggregates payments to order grain (prevents fan-out)
--   - JOINs to dim tables on natural keys to retrieve surrogate keys
--   - LEFT JOIN on optional dimensions (payment_type)
--   - WHERE filter drops rows with missing critical fields
INSERT INTO warehouse.fact_order_items (
  order_id, order_item_id,
  customer_sk, product_sk, seller_sk, date_sk, order_status_sk, payment_type_sk,
  price, freight_value, payment_value, payment_installments
)
WITH order_payments_agg AS (
  SELECT 
    order_id,
    SUM(NULLIF(payment_value, '')::NUMERIC)        AS total_payment_value,
    SUM(NULLIF(payment_installments, '')::INTEGER) AS total_installments,
    (array_agg(payment_type ORDER BY 
        NULLIF(payment_value, '')::NUMERIC DESC NULLS LAST
    ))[1] AS dominant_payment_type
  FROM staging.order_payments
  GROUP BY order_id
)
SELECT 
  oi.order_id,
  NULLIF(oi.order_item_id, '')::SMALLINT          AS order_item_id,
  dc.customer_sk,
  dp.product_sk,
  ds.seller_sk,
  TO_CHAR(NULLIF(o.order_purchase_timestamp, '')::TIMESTAMP, 'YYYYMMDD')::INTEGER AS date_sk,
  dos.order_status_sk,
  dpt.payment_type_sk,
  NULLIF(oi.price, '')::NUMERIC(10,2)             AS price,
  NULLIF(oi.freight_value, '')::NUMERIC(10,2)     AS freight_value,
  opa.total_payment_value                         AS payment_value,
  opa.total_installments                          AS payment_installments
FROM staging.order_items oi
JOIN staging.orders o 
  ON oi.order_id = o.order_id
JOIN staging.customers sc 
  ON o.customer_id = sc.customer_id
LEFT JOIN order_payments_agg opa 
  ON oi.order_id = opa.order_id
JOIN warehouse.dim_customer dc 
  ON sc.customer_unique_id = dc.customer_unique_id
JOIN warehouse.dim_product dp 
  ON oi.product_id = dp.product_id
JOIN warehouse.dim_seller ds 
  ON oi.seller_id = ds.seller_id
JOIN warehouse.dim_order_status dos 
  ON o.order_status = dos.order_status
LEFT JOIN warehouse.dim_payment_type dpt 
  ON opa.dominant_payment_type = dpt.payment_type
WHERE NULLIF(o.order_purchase_timestamp, '') IS NOT NULL
  AND NULLIF(oi.price, '')          IS NOT NULL
  AND NULLIF(oi.freight_value, '')  IS NOT NULL;


-- Verification: row counts across all warehouse tables
SELECT 'dim_date' AS table_name, COUNT(*) AS row_count FROM warehouse.dim_date
UNION ALL 
SELECT 'dim_customer', COUNT(*) FROM warehouse.dim_customer
UNION ALL 
SELECT 'dim_product', COUNT(*) FROM warehouse.dim_product
UNION ALL 
SELECT 'dim_seller', COUNT(*) FROM warehouse.dim_seller
UNION ALL 
SELECT 'dim_order_status', COUNT(*) FROM warehouse.dim_order_status
UNION ALL 
SELECT 'dim_payment_type', COUNT(*) FROM warehouse.dim_payment_type
UNION ALL 
SELECT 'fact_order_items', COUNT(*) FROM warehouse.fact_order_items
ORDER BY row_count DESC;

-- Data quality check: rows filtered from source
SELECT 
  (SELECT COUNT(*) FROM staging.order_items) AS staging_rows,
  (SELECT COUNT(*) FROM warehouse.fact_order_items) AS warehouse_rows,
  (SELECT COUNT(*) FROM staging.order_items) - (SELECT COUNT(*) FROM warehouse.fact_order_items) AS rows_filtered;