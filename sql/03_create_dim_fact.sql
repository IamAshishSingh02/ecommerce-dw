-- 03_create_dim_fact.sql
-- Purpose: DDL only — create warehouse schema, tables, and indexes
-- Pattern: All CREATE statements, no data manipulation
--
-- Runs ONCE during warehouse setup, or whenever schema changes.
-- For data refresh, run 04_transform_load.sql separately.

-- Drop and recreate the warehouse schema for idempotency
DROP SCHEMA IF EXISTS warehouse CASCADE;
CREATE SCHEMA warehouse;


-- DIMENSION TABLES

-- dim_date: calendar dimension (populated via generate_series in 04)
CREATE TABLE warehouse.dim_date (
  date_sk        INTEGER     PRIMARY KEY,
  date_actual    DATE        NOT NULL UNIQUE,
  year           SMALLINT    NOT NULL,
  quarter        SMALLINT    NOT NULL,
  month          SMALLINT    NOT NULL,
  month_name     VARCHAR(10) NOT NULL,
  day            SMALLINT    NOT NULL,
  day_of_week    SMALLINT    NOT NULL,
  day_name       VARCHAR(10) NOT NULL,
  is_weekend     BOOLEAN     NOT NULL,
  week_of_year   SMALLINT    NOT NULL
);

CREATE INDEX idx_dim_date_actual ON warehouse.dim_date(date_actual);


-- dim_customer: deduplicated customer master
CREATE TABLE warehouse.dim_customer (
  customer_sk              SERIAL       PRIMARY KEY,
  customer_unique_id       VARCHAR(50)  NOT NULL UNIQUE,
  customer_city            VARCHAR(100),
  customer_state           CHAR(2),
  customer_zip_code_prefix VARCHAR(10)
);

CREATE INDEX idx_dim_customer_unique_id ON warehouse.dim_customer(customer_unique_id);


-- dim_product: enriched with English category translation
CREATE TABLE warehouse.dim_product (
  product_sk                 SERIAL       PRIMARY KEY,
  product_id                 VARCHAR(50)  NOT NULL UNIQUE,
  product_category_pt        VARCHAR(100),
  product_category_en        VARCHAR(100),
  product_weight_g           INTEGER,
  product_length_cm          INTEGER,
  product_height_cm          INTEGER,
  product_width_cm           INTEGER,
  product_photos_qty         SMALLINT
);

CREATE INDEX idx_dim_product_id ON warehouse.dim_product(product_id);


-- dim_seller: marketplace sellers
CREATE TABLE warehouse.dim_seller (
  seller_sk              SERIAL       PRIMARY KEY,
  seller_id              VARCHAR(50)  NOT NULL UNIQUE,
  seller_city            VARCHAR(100),
  seller_state           CHAR(2),
  seller_zip_code_prefix VARCHAR(10)
);

CREATE INDEX idx_dim_seller_id ON warehouse.dim_seller(seller_id);


-- dim_order_status: small lookup for order lifecycle states
CREATE TABLE warehouse.dim_order_status (
  order_status_sk SERIAL      PRIMARY KEY,
  order_status    VARCHAR(20) NOT NULL UNIQUE
);

CREATE INDEX idx_dim_order_status_name ON warehouse.dim_order_status(order_status);


-- dim_payment_type: small lookup for payment methods
CREATE TABLE warehouse.dim_payment_type (
  payment_type_sk SERIAL      PRIMARY KEY,
  payment_type    VARCHAR(20) NOT NULL UNIQUE
);

CREATE INDEX idx_dim_payment_type_name ON warehouse.dim_payment_type(payment_type);


-- FACT TABLE

-- fact_order_items
-- Grain: one row per item per order
-- Foreign keys enforce referential integrity against all dimensions
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

-- Indexes on foreign keys for fast analytical joins
CREATE INDEX idx_fact_customer_sk     ON warehouse.fact_order_items(customer_sk);
CREATE INDEX idx_fact_product_sk      ON warehouse.fact_order_items(product_sk);
CREATE INDEX idx_fact_seller_sk       ON warehouse.fact_order_items(seller_sk);
CREATE INDEX idx_fact_date_sk         ON warehouse.fact_order_items(date_sk);
CREATE INDEX idx_fact_order_status_sk ON warehouse.fact_order_items(order_status_sk);


-- Verification: confirm all 7 tables exist
SELECT table_schema, table_name 
FROM information_schema.tables 
WHERE table_schema = 'warehouse'
ORDER BY table_name;