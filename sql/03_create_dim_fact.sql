-- 03_create_dim_fact.sql
-- Building the warehouse star schema

-- Drop and recreate the warehouse schema
-- (idempotent: this script can be re-run safely)
DROP SCHEMA IF EXISTS warehouse CASCADE;
CREATE SCHEMA warehouse;


-- dim_date: the calendar dimension
-- One row per day from 2016-01-01 to 2018-12-31 (1,096 rows)
CREATE TABLE warehouse.dim_date (
  -- Surrogate key: YYYYMMDD as integer (e.g., 20180615 for June 15, 2018)
  date_sk        INTEGER     PRIMARY KEY,

  -- The actual calendar date (one per row)
  date_actual    DATE        NOT NULL UNIQUE,

  -- Pre-computed date parts: avoid having analysts re-extract these every query
  year           SMALLINT    NOT NULL,        -- e.g., 2018
  quarter        SMALLINT    NOT NULL,        -- 1, 2, 3, or 4
  month          SMALLINT    NOT NULL,        -- 1-12
  month_name     VARCHAR(10) NOT NULL,        -- 'January', 'February', ...
  day            SMALLINT    NOT NULL,        -- 1-31
  day_of_week    SMALLINT    NOT NULL,        -- 0=Sun, 1=Mon, ..., 6=Sat
  day_name       VARCHAR(10) NOT NULL,        -- 'Monday', 'Tuesday', ...
  is_weekend     BOOLEAN     NOT NULL,        -- TRUE for Sat/Sun, FALSE otherwise
  week_of_year   SMALLINT    NOT NULL         -- 1-53
);

-- Populate dim_date
-- For every day "d" in the range, compute all the date-part columns
-- and insert as a row.
INSERT INTO warehouse.dim_date
SELECT
  TO_CHAR(d, 'YYYYMMDD')::INTEGER    AS date_sk,         -- e.g., 20180615
  d::DATE                            AS date_actual,     -- e.g., 2018-06-15
  EXTRACT(YEAR FROM d)::SMALLINT     AS year,            -- 2018
  EXTRACT(QUARTER FROM d)::SMALLINT  AS quarter,         -- 2
  EXTRACT(MONTH FROM d)::SMALLINT    AS month,           -- 6
  TRIM(TO_CHAR(d, 'Month'))          AS month_name,      -- 'June' (TRIM removes padding)
  EXTRACT(DAY FROM d)::SMALLINT      AS day,             -- 15
  EXTRACT(DOW FROM d)::SMALLINT      AS day_of_week,     -- 5 (Friday)
  TRIM(TO_CHAR(d, 'Day'))            AS day_name,        -- 'Friday'
  EXTRACT(DOW FROM d) IN (0, 6)      AS is_weekend,      -- FALSE (Friday)
  EXTRACT(WEEK FROM d)::SMALLINT     AS week_of_year     -- 24
FROM generate_series(
  '2016-01-01'::DATE,         -- start date
  '2018-12-31'::DATE,         -- end date
  '1 day'::INTERVAL           -- step: one row per day
) AS d;                          -- name each generated date "d"

-- Index on date_actual makes joins from fact_order_items fast
CREATE INDEX idx_dim_date_actual ON warehouse.dim_date(date_actual);

-- Count check (should be 1096)
SELECT 'dim_date built' AS status, COUNT(*) AS row_count FROM warehouse.dim_date;

-- Sample rows
SELECT * FROM warehouse.dim_date 
WHERE date_actual IN ('2018-01-01', '2018-06-15', '2018-12-25')
ORDER BY date_actual;


-- dim_customer
-- One row per UNIQUE customer (deduped via customer_unique_id)
-- Source: staging.customers (99,441 rows → ~96,000 unique customers)

CREATE TABLE warehouse.dim_customer (
  customer_sk              SERIAL       PRIMARY KEY,   -- our surrogate key
  customer_unique_id       VARCHAR(50)  NOT NULL UNIQUE, -- natural key from Olist
  customer_city            VARCHAR(100),
  customer_state           CHAR(2),
  customer_zip_code_prefix VARCHAR(10)
);

-- Populate dim_customer with deduplication
INSERT INTO warehouse.dim_customer (
  customer_unique_id,
  customer_city,
  customer_state,
  customer_zip_code_prefix
)
SELECT DISTINCT ON (customer_unique_id)
  customer_unique_id,
  customer_city,
  customer_state,
  customer_zip_code_prefix
FROM staging.customers
WHERE customer_unique_id IS NOT NULL AND customer_unique_id != ''
ORDER BY customer_unique_id, customer_id;
-- ORDER BY here matters: DISTINCT ON keeps the FIRST row per group,
-- and "first" is defined by ORDER BY. We sort by customer_id as 
-- tiebreaker to make this deterministic (re-runnable with same result).

-- Index for fast lookup when populating fact_order_items
CREATE INDEX idx_dim_customer_unique_id ON warehouse.dim_customer(customer_unique_id);

-- Row count: should be ~96,000 (NOT 99,441 — that's the whole point!)
SELECT 'dim_customer built' AS status, COUNT(*) AS row_count FROM warehouse.dim_customer;

-- Sanity check: each customer_unique_id appears exactly once
SELECT customer_unique_id, COUNT(*) AS appearances
FROM warehouse.dim_customer
GROUP BY customer_unique_id
HAVING COUNT(*) > 1
LIMIT 5;
-- Expected: 0 rows (no duplicates)

-- Sample data: top 5 cities by customer count
SELECT customer_city, customer_state, COUNT(*) AS customer_count
FROM warehouse.dim_customer
GROUP BY customer_city, customer_state
ORDER BY customer_count DESC
LIMIT 5;

-- Peek at 5 sample rows with surrogate keys
SELECT customer_sk, customer_unique_id, customer_city, customer_state
FROM warehouse.dim_customer
ORDER BY customer_sk
LIMIT 5;


-- dim_product
-- One row per product, enriched with English category translation
-- Source: staging.products LEFT JOIN staging.category_translation

CREATE TABLE warehouse.dim_product (
  product_sk                 SERIAL       PRIMARY KEY,    -- surrogate key
  product_id                 VARCHAR(50)  NOT NULL UNIQUE, -- natural key
  product_category_pt        VARCHAR(100),                 -- Portuguese (original)
  product_category_en        VARCHAR(100),                 -- English (enriched)
  product_weight_g           INTEGER,
  product_length_cm          INTEGER,
  product_height_cm          INTEGER,
  product_width_cm           INTEGER,
  product_photos_qty         SMALLINT
);

-- Populate dim_product with enrichment
INSERT INTO warehouse.dim_product (
  product_id,
  product_category_pt,
  product_category_en,
  product_weight_g,
  product_length_cm,
  product_height_cm,
  product_width_cm,
  product_photos_qty
)
SELECT 
  p.product_id,
  NULLIF(p.product_category_name, '') AS product_category_pt,
  NULLIF(ct.product_category_name_english, '') AS product_category_en,
  -- Convert TEXT staging columns to proper numeric types
  -- NULLIF(x, '') turns empty strings into NULL so cast doesn't fail
  NULLIF(p.product_weight_g, '')::INTEGER AS product_weight_g,
  NULLIF(p.product_length_cm, '')::INTEGER AS product_length_cm,
  NULLIF(p.product_height_cm, '')::INTEGER AS product_height_cm,
  NULLIF(p.product_width_cm, '')::INTEGER AS product_width_cm,
  NULLIF(p.product_photos_qty, '')::SMALLINT AS product_photos_qty
FROM staging.products p
LEFT JOIN staging.category_translation ct ON p.product_category_name = ct.product_category_name
WHERE p.product_id IS NOT NULL AND p.product_id != '';

-- Index
CREATE INDEX idx_dim_product_id ON warehouse.dim_product(product_id);

-- Row count
SELECT 'dim_product built' AS status, COUNT(*) AS row_count FROM warehouse.dim_product;

-- How many products have a Portuguese category but no English translation?
-- This is a data quality check: did our enrichment cover everything?
SELECT 
  COUNT(*) AS total_products,
  COUNT(product_category_pt) AS has_pt_category,
  COUNT(product_category_en) AS has_en_category,
  COUNT(*) FILTER (WHERE product_category_pt IS NOT NULL AND product_category_en IS NULL) AS pt_but_no_en
FROM warehouse.dim_product;

-- Top 5 product categories by product count (now in English!)
SELECT 
  product_category_en,
  COUNT(*) AS product_count
FROM warehouse.dim_product
WHERE product_category_en IS NOT NULL
GROUP BY product_category_en
ORDER BY product_count DESC
LIMIT 5;


-- dim_seller
-- One row per seller in the marketplace
-- Source: staging.sellers (3,095 rows)

CREATE TABLE warehouse.dim_seller (
  seller_sk              SERIAL       PRIMARY KEY,
  seller_id              VARCHAR(50)  NOT NULL UNIQUE,
  seller_city            VARCHAR(100),
  seller_state           CHAR(2),
  seller_zip_code_prefix VARCHAR(10)
);

INSERT INTO warehouse.dim_seller (
  seller_id, seller_city, seller_state, seller_zip_code_prefix
)
SELECT 
  seller_id,
  seller_city,
  seller_state,
  seller_zip_code_prefix
FROM staging.sellers
WHERE seller_id IS NOT NULL AND seller_id != '';

CREATE INDEX idx_dim_seller_id ON warehouse.dim_seller(seller_id);


-- dim_order_status
-- One row per distinct order status (the 8 statuses we found)
-- Source: SELECT DISTINCT from staging.orders

CREATE TABLE warehouse.dim_order_status (
  order_status_sk SERIAL      PRIMARY KEY,
  order_status    VARCHAR(20) NOT NULL UNIQUE
);

INSERT INTO warehouse.dim_order_status (order_status)
SELECT DISTINCT order_status
FROM staging.orders
WHERE order_status IS NOT NULL AND order_status != ''
ORDER BY order_status;

CREATE INDEX idx_dim_order_status_name ON warehouse.dim_order_status(order_status);


-- dim_payment_type
-- One row per distinct payment method
-- Source: SELECT DISTINCT from staging.order_payments

CREATE TABLE warehouse.dim_payment_type (
  payment_type_sk SERIAL      PRIMARY KEY,
  payment_type    VARCHAR(20) NOT NULL UNIQUE
);

INSERT INTO warehouse.dim_payment_type (payment_type)
SELECT DISTINCT payment_type
FROM staging.order_payments
WHERE payment_type IS NOT NULL AND payment_type != '';

CREATE INDEX idx_dim_payment_type_name ON warehouse.dim_payment_type(payment_type);

SELECT 'dim_seller' AS dimension, COUNT(*) AS row_count FROM warehouse.dim_seller
UNION ALL
SELECT 'dim_order_status',         COUNT(*) FROM warehouse.dim_order_status
UNION ALL
SELECT 'dim_payment_type',         COUNT(*) FROM warehouse.dim_payment_type
ORDER BY row_count DESC;

-- Show the actual order statuses with their surrogate keys
SELECT * FROM warehouse.dim_order_status ORDER BY order_status_sk;

-- Show the payment types
SELECT * FROM warehouse.dim_payment_type ORDER BY payment_type_sk;

-- Sample 3 sellers
SELECT seller_sk, seller_id, seller_city, seller_state 
FROM warehouse.dim_seller 
ORDER BY seller_sk 
LIMIT 3;


-- fact_order_items
-- Grain: one row per item per order

CREATE TABLE warehouse.fact_order_items (
  order_item_fact_sk   BIGSERIAL     PRIMARY KEY,
  order_id             VARCHAR(50)   NOT NULL,
  order_item_id        SMALLINT      NOT NULL,
  
  customer_sk          INTEGER       NOT NULL REFERENCES warehouse.dim_customer(customer_sk),
  product_sk           INTEGER       NOT NULL REFERENCES warehouse.dim_product(product_sk),
  seller_sk            INTEGER       NOT NULL REFERENCES warehouse.dim_seller(seller_sk),
  date_sk              INTEGER       NOT NULL REFERENCES warehouse.dim_date(date_sk),
  order_status_sk      INTEGER       NOT NULL REFERENCES warehouse.dim_order_status(order_status_sk),
  payment_type_sk      INTEGER                REFERENCES warehouse.dim_payment_type(payment_type_sk),
  
  price                NUMERIC(10,2) NOT NULL,
  freight_value        NUMERIC(10,2) NOT NULL,
  payment_value        NUMERIC(10,2),
  payment_installments SMALLINT,
  
  total_value          NUMERIC(10,2) GENERATED ALWAYS AS (price + freight_value) STORED
);

-- Populate fact_order_items
INSERT INTO warehouse.fact_order_items (
  order_id, order_item_id,
  customer_sk, product_sk, seller_sk, date_sk, order_status_sk, payment_type_sk,
  price, freight_value, payment_value, payment_installments
)
WITH order_payments_agg AS (
  SELECT 
    order_id,
    SUM(NULLIF(payment_value, '')::NUMERIC) AS total_payment_value,
    SUM(NULLIF(payment_installments, '')::INTEGER) AS total_installments,
    (array_agg(payment_type ORDER BY NULLIF(payment_value, '')::NUMERIC DESC NULLS LAST))[1] AS dominant_payment_type
  FROM staging.order_payments
  GROUP BY order_id
)
SELECT 
  oi.order_id,
  NULLIF(oi.order_item_id, '')::SMALLINT AS order_item_id,
  dc.customer_sk,
  dp.product_sk,
  ds.seller_sk,
  TO_CHAR(NULLIF(o.order_purchase_timestamp, '')::TIMESTAMP, 'YYYYMMDD')::INTEGER AS date_sk,
  dos.order_status_sk,
  dpt.payment_type_sk,
  NULLIF(oi.price, '')::NUMERIC(10,2) AS price,
  NULLIF(oi.freight_value, '')::NUMERIC(10,2) AS freight_value,
  opa.total_payment_value AS payment_value,
  opa.total_installments AS payment_installments
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
  
-- Indexes on foreign keys for fast analytical queries
CREATE INDEX idx_fact_customer_sk     ON warehouse.fact_order_items(customer_sk);
CREATE INDEX idx_fact_product_sk      ON warehouse.fact_order_items(product_sk);
CREATE INDEX idx_fact_seller_sk       ON warehouse.fact_order_items(seller_sk);
CREATE INDEX idx_fact_date_sk         ON warehouse.fact_order_items(date_sk);
CREATE INDEX idx_fact_order_status_sk ON warehouse.fact_order_items(order_status_sk);

SELECT 'fact_order_items built' AS status, COUNT(*) AS row_count 
FROM warehouse.fact_order_items;

SELECT * FROM warehouse.fact_order_items LIMIT 5;

SELECT 
  (SELECT COUNT(*) FROM staging.order_items) AS staging_rows,
  (SELECT COUNT(*) FROM warehouse.fact_order_items) AS warehouse_rows,
  (SELECT COUNT(*) FROM staging.order_items) - 
  (SELECT COUNT(*) FROM warehouse.fact_order_items) AS rows_filtered;