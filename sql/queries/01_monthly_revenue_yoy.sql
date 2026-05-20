-- 01_monthly_revenue_yoy.sql
-- Question: How did monthly revenue change year-over-year?
-- Technique: CTE chain + LAG() window function
-- Filter: delivered orders only (excludes canceled/failed)

WITH 
-- Step 1: Aggregate revenue to (year, month) grain
monthly_revenue AS (
  SELECT 
    dd.year,
    dd.month,
    dd.month_name,
    ROUND(SUM(foi.price), 2) AS revenue,
    COUNT(*) AS items_sold,
    COUNT(DISTINCT foi.order_id) AS orders_count
  FROM warehouse.fact_order_items foi
  JOIN warehouse.dim_date dd ON foi.date_sk = dd.date_sk
  JOIN warehouse.dim_order_status dos ON foi.order_status_sk = dos.order_status_sk
  WHERE dos.order_status = 'delivered'
  GROUP BY dd.year, dd.month, dd.month_name
),

-- Step 2: Use LAG() to bring "same month, previous year" alongside each row
-- The window is PARTITION BY month (so January 2018 looks back to January 2017)
-- ORDER BY year (so "previous" means earlier year)
with_prev_year AS (
  SELECT 
    year,
    month,
    month_name,
    revenue,
    items_sold,
    orders_count,
    LAG(revenue) OVER (PARTITION BY month ORDER BY year) AS prev_year_revenue,
    LAG(items_sold) OVER (PARTITION BY month ORDER BY year) AS prev_year_items
  FROM monthly_revenue
)

-- Step 3: Compute YoY % change
SELECT 
  year,
  month,
  month_name,
  revenue,
  items_sold,
  orders_count,
  prev_year_revenue,
  CASE 
    WHEN prev_year_revenue IS NULL THEN NULL
    WHEN prev_year_revenue = 0 THEN NULL
    ELSE ROUND(((revenue - prev_year_revenue) / prev_year_revenue) * 100, 1)
  END AS yoy_growth_pct
FROM with_prev_year
ORDER BY year, month;