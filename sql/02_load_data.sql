-- 02_load_data.sql
-- Purpose: Bulk-load all 9 Olist CSVs into staging tables

-- Run from WSL terminal with:
--   psql -h localhost -p 5433 -U postgres -d ecommerce_dw -f sql/02_load_data.sql
--
-- Note: \copy is a psql meta-command — it MUST run from psql.
-- You cannot run this file from pgAdmin (pgAdmin doesn't support \copy).

-- Truncate first so this script is idempotent (re-runnable safely)
TRUNCATE TABLE 
  staging.customers,
  staging.orders,
  staging.order_items,
  staging.order_payments,
  staging.order_reviews,
  staging.products,
  staging.sellers,
  staging.geolocation,
  staging.category_translation
RESTART IDENTITY;

-- 1. Customers (~99K rows)
\copy staging.customers FROM '/home/psssa/projects/ecommerce-dw/data/olist_customers_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

-- 2. Orders (~99K rows)
\copy staging.orders FROM '/home/psssa/projects/ecommerce-dw/data/olist_orders_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

-- 3. Order Items (~112K rows — finest grain)
\copy staging.order_items FROM '/home/psssa/projects/ecommerce-dw/data/olist_order_items_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

-- 4. Order Payments (~104K rows)
\copy staging.order_payments FROM '/home/psssa/projects/ecommerce-dw/data/olist_order_payments_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

-- 5. Order Reviews (~99K rows)
\copy staging.order_reviews FROM '/home/psssa/projects/ecommerce-dw/data/olist_order_reviews_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

-- 6. Products (~33K rows)
\copy staging.products FROM '/home/psssa/projects/ecommerce-dw/data/olist_products_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

-- 7. Sellers (~3K rows)
\copy staging.sellers FROM '/home/psssa/projects/ecommerce-dw/data/olist_sellers_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

-- 8. Geolocation (~1M rows — the biggest file)
\copy staging.geolocation FROM '/home/psssa/projects/ecommerce-dw/data/olist_geolocation_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

-- 9. Category Translation (~71 rows — tiny lookup)
\copy staging.category_translation FROM '/home/psssa/projects/ecommerce-dw/data/product_category_name_translation.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

-- Row count verification
SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM staging.customers
UNION ALL
SELECT 'orders', COUNT(*) FROM staging.orders
UNION ALL
SELECT 'order_items', COUNT(*) FROM staging.order_items
UNION ALL
SELECT 'order_payments', COUNT(*) FROM staging.order_payments
UNION ALL
SELECT 'order_reviews', COUNT(*) FROM staging.order_reviews
UNION ALL
SELECT 'products', COUNT(*) FROM staging.products
UNION ALL
SELECT 'sellers', COUNT(*) FROM staging.sellers
UNION ALL
SELECT 'geolocation', COUNT(*) FROM staging.geolocation
UNION ALL
SELECT 'category_translation', COUNT(*) FROM staging.category_translation
ORDER BY row_count DESC;