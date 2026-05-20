-- 02_top_sellers_per_state.sql
-- Question: Who are the top 3 sellers in each Brazilian state by revenue?
-- Technique: ROW_NUMBER() OVER (PARTITION BY state ORDER BY revenue DESC)
-- Filter: delivered orders only

WITH 
-- Step 1: Aggregate revenue per (seller, state)
seller_revenue AS (
  SELECT 
    ds.seller_state,
    ds.seller_id,
    ds.seller_city,
    ROUND(SUM(foi.price), 2) AS total_revenue,
    COUNT(*) AS items_sold,
    COUNT(DISTINCT foi.order_id) AS orders_count
  FROM warehouse.fact_order_items foi
  JOIN warehouse.dim_seller ds ON foi.seller_sk = ds.seller_sk
  JOIN warehouse.dim_order_status dos ON foi.order_status_sk = dos.order_status_sk
  WHERE dos.order_status = 'delivered'
  AND ds.seller_state IS NOT NULL
  GROUP BY ds.seller_state, ds.seller_id, ds.seller_city
),

-- Step 2: Rank sellers within each state
ranked_sellers AS (
  SELECT 
    seller_state,
    seller_id,
    seller_city,
    total_revenue,
    items_sold,
    orders_count,
    ROW_NUMBER() OVER (PARTITION BY seller_state ORDER BY total_revenue DESC) AS rank_in_state
  FROM seller_revenue
)

-- Step 3: Keep only top 3 per state
SELECT 
  seller_state,
  rank_in_state,
  seller_id,
  seller_city,
  total_revenue,
  items_sold,
  orders_count
FROM ranked_sellers
WHERE rank_in_state <= 3
ORDER BY seller_state, rank_in_state;