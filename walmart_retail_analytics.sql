-- ================================================================
--  WALMART RETAIL SALES ANALYTICS
--  MySQL Project
--
--  Dataset : Walmart Store Sales Forecasting
--  Source  : https://www.kaggle.com/datasets/manjeetsingh/retaildataset
--
--  Sections:
--    1. Schema Creation
--    2. Data Loading
--    3. Data Cleaning & EDA
--    4. Business Analysis Queries
--    5. Views & Stored Procedures
-- ================================================================


-- ================================================================
-- SECTION 1 : SCHEMA CREATION
-- ================================================================

CREATE DATABASE IF NOT EXISTS walmart_retail;
USE walmart_retail;

DROP TABLE IF EXISTS sales;
DROP TABLE IF EXISTS features;
DROP TABLE IF EXISTS stores;

-- stores table
-- 45 stores with type (A = largest, C = smallest) and size in sq ft
-- Created first because features and sales both reference it via FK
CREATE TABLE stores (
    store   INT     PRIMARY KEY,
    type    CHAR(1) NOT NULL,
    size    INT     NOT NULL
);

-- features table
-- Weekly environmental data per store: temperature, fuel, CPI,
-- unemployment, 5 markdown columns, and holiday flag
-- Markdowns are heavily NULL — only available after Nov 2011
CREATE TABLE features (
    store        INT           NOT NULL,
    date         DATE          NOT NULL,
    temperature  DECIMAL(6,2),
    fuel_price   DECIMAL(6,3),
    markdown1    DECIMAL(10,2),
    markdown2    DECIMAL(10,2),
    markdown3    DECIMAL(10,2),
    markdown4    DECIMAL(10,2),
    markdown5    DECIMAL(10,2),
    cpi          DECIMAL(12,7),
    unemployment DECIMAL(5,3),
    is_holiday   TINYINT       NOT NULL DEFAULT 0,
    PRIMARY KEY (store, date),
    FOREIGN KEY (store) REFERENCES stores(store)
);

-- sales table
-- Weekly sales per store per department
-- 421,570 rows covering Feb 2010 to Oct 2012
-- weekly_sales can be negative (customer returns / corrections)
CREATE TABLE sales (
    store        INT           NOT NULL,
    dept         INT           NOT NULL,
    date         DATE          NOT NULL,
    weekly_sales DECIMAL(12,2),
    is_holiday   TINYINT       NOT NULL DEFAULT 0,
    PRIMARY KEY (store, dept, date),
    FOREIGN KEY (store) REFERENCES stores(store)
);


-- ================================================================
-- SECTION 2 : DATA LOADING
-- ================================================================
-- Copy the 3 CSV files to your MySQL secure upload folder:
--   C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/
--
-- Run stores first, then features, then sales (FK order)
--
-- Issues handled:
--   STR_TO_DATE  : CSV date format is DD/MM/YYYY
--   NULLIF       : 'NA' strings converted to proper NULLs
--   LINES '\r\n' : Windows line endings on sales file
--   TRIM         : Removes invisible \r from boolean values
--   IGNORE       : Skips duplicate (store,dept,date) rows
-- ================================================================

-- Load stores (no NULLs, no date conversion needed)
LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/stores_dataset.csv'
INTO TABLE stores
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(store, type, size);
-- Expected: 45 rows affected


-- Load features (handle NA in all numeric columns + date + holiday)
LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/features_dataset.csv'
INTO TABLE features
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(store, @raw_date, temperature, fuel_price,
 @md1, @md2, @md3, @md4, @md5,
 @cpi, @unemployment, @holiday)
SET
    date         = STR_TO_DATE(@raw_date,    '%d/%m/%Y'),
    markdown1    = NULLIF(@md1,              'NA'),
    markdown2    = NULLIF(@md2,              'NA'),
    markdown3    = NULLIF(@md3,              'NA'),
    markdown4    = NULLIF(@md4,              'NA'),
    markdown5    = NULLIF(@md5,              'NA'),
    cpi          = NULLIF(@cpi,              'NA'),
    unemployment = NULLIF(@unemployment,     'NA'),
    is_holiday   = IF(TRIM(@holiday) = 'TRUE', 1, 0);
-- Expected: 8190 rows affected


-- Load sales (Windows line endings + IGNORE for duplicate rows)
LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/sales_dataset.csv'
IGNORE
INTO TABLE sales
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 ROWS
(store, dept, @raw_date, weekly_sales, @holiday)
SET
    date       = STR_TO_DATE(@raw_date, '%d/%m/%Y'),
    is_holiday = IF(TRIM(@holiday) = 'TRUE', 1, 0);
-- Expected: 421570 rows affected


-- ================================================================
-- SECTION 3 : DATA CLEANING & EDA
-- ================================================================

-- 3.1 Verify row counts after loading
SELECT 'stores'   AS tbl, COUNT(*) AS total_rows FROM stores
UNION ALL
SELECT 'features' AS tbl, COUNT(*) AS total_rows FROM features
UNION ALL
SELECT 'sales'    AS tbl, COUNT(*) AS total_rows FROM sales;
-- Expected: 45 | 8190 | 421570


-- 3.2 Store type distribution
-- Type A = largest stores, Type C = smallest
-- Do not compare raw sales across types without normalizing for size
SELECT
    type,
    COUNT(*)            AS store_count,
    ROUND(AVG(size), 0) AS avg_size_sqft,
    MIN(size)           AS min_size,
    MAX(size)           AS max_size
FROM stores
GROUP BY type
ORDER BY avg_size_sqft DESC;
-- Result: A(22 stores, 177K sqft avg) > B(17, 101K) > C(6, 40K)


-- 3.3 Sales date range
SELECT
    MIN(date)            AS earliest_date,
    MAX(date)            AS latest_date,
    COUNT(DISTINCT date) AS total_weeks
FROM sales;
-- Result: 2010-02-05 to 2012-10-26 | 143 weeks


-- 3.4 NULL check on markdown columns
-- High NULL % is expected — markdowns only started Nov 2011
-- and were not applied to every store every week
SELECT
    COUNT(*) AS total_rows,
    SUM(CASE WHEN markdown1 IS NULL THEN 1 ELSE 0 END) AS md1_nulls,
    SUM(CASE WHEN markdown2 IS NULL THEN 1 ELSE 0 END) AS md2_nulls,
    SUM(CASE WHEN markdown3 IS NULL THEN 1 ELSE 0 END) AS md3_nulls,
    SUM(CASE WHEN markdown4 IS NULL THEN 1 ELSE 0 END) AS md4_nulls,
    SUM(CASE WHEN markdown5 IS NULL THEN 1 ELSE 0 END) AS md5_nulls
FROM features;
-- Result: 50-64% NULL across all markdown columns — handled via NULLIF on load


-- 3.5 Negative sales check
-- Negative values = customer returns/corrections
-- Only 0.3% of rows — excluded from revenue queries using WHERE weekly_sales > 0
SELECT
    COUNT(*)                                           AS total_rows,
    SUM(CASE WHEN weekly_sales < 0 THEN 1 ELSE 0 END) AS negative_rows,
    ROUND(MIN(weekly_sales), 2)                        AS min_sales,
    ROUND(MAX(weekly_sales), 2)                        AS max_sales,
    ROUND(AVG(weekly_sales), 2)                        AS avg_weekly_sales
FROM sales;
-- Result: 1285 negative rows | min: -4988.94 | max: 693099.36 | avg: 15981.26


-- ================================================================
-- SECTION 4 : BUSINESS ANALYSIS QUERIES
-- ================================================================

-- 4.1 Top 10 Stores by Total Revenue
SELECT
    s.store,
    st.type                       AS store_type,
    st.size                       AS store_size_sqft,
    ROUND(SUM(s.weekly_sales), 2) AS total_revenue,
    ROUND(AVG(s.weekly_sales), 2) AS avg_weekly_sales,
    COUNT(DISTINCT s.dept)        AS active_depts
FROM sales s
JOIN stores st ON s.store = st.store
WHERE s.weekly_sales > 0
GROUP BY s.store, st.type, st.size
ORDER BY total_revenue DESC
LIMIT 10;
-- Insight: Store 20 leads at $30.1Cr. Store 10 (Type B) breaks into top 10
--          — strong overperformer for its size class.


-- 4.2 Bottom 10 Stores by Total Revenue
SELECT
    s.store,
    st.type                       AS store_type,
    st.size                       AS store_size_sqft,
    ROUND(SUM(s.weekly_sales), 2) AS total_revenue,
    ROUND(AVG(s.weekly_sales), 2) AS avg_weekly_sales
FROM sales s
JOIN stores st ON s.store = st.store
WHERE s.weekly_sales > 0
GROUP BY s.store, st.type, st.size
ORDER BY total_revenue ASC
LIMIT 10;
-- Insight: Store 33 generates only $3.7Cr — 8x less than Store 20.
--          It is a Type A store underperforming like a Type C — red flag.


-- 4.3 Store Performance Ranked within Type and Overall
WITH store_revenue AS (
    SELECT
        s.store,
        st.type,
        st.size,
        ROUND(SUM(s.weekly_sales), 2) AS total_revenue
    FROM sales s
    JOIN stores st ON s.store = st.store
    WHERE s.weekly_sales > 0
    GROUP BY s.store, st.type, st.size
)
SELECT
    store,
    type,
    size,
    total_revenue,
    RANK()       OVER (PARTITION BY type ORDER BY total_revenue DESC) AS rank_in_type,
    DENSE_RANK() OVER (ORDER BY total_revenue DESC)                   AS overall_rank
FROM store_revenue
ORDER BY type, rank_in_type;
-- Insight: Store 20 = #1 in Type A. Store 10 = #1 in Type B (overall rank 6).


-- 4.4 Top 10 Departments by Total Revenue
SELECT
    dept,
    ROUND(SUM(weekly_sales), 2) AS total_revenue,
    ROUND(AVG(weekly_sales), 2) AS avg_weekly_sales,
    COUNT(DISTINCT store)       AS stores_carrying_dept
FROM sales
WHERE weekly_sales > 0
GROUP BY dept
ORDER BY total_revenue DESC
LIMIT 10;
-- Insight: Dept 92 is #1 at $48.3Cr with avg weekly sales of $75,204 — 5x company avg.
--          All top 10 depts present in all 45 stores — these are core categories.


-- 4.5 Holiday vs Normal Week Sales per Store
SELECT
    store,
    ROUND(AVG(CASE WHEN is_holiday = 1 THEN weekly_sales END), 2) AS avg_holiday_sales,
    ROUND(AVG(CASE WHEN is_holiday = 0 THEN weekly_sales END), 2) AS avg_normal_sales,
    ROUND(
        (AVG(CASE WHEN is_holiday = 1 THEN weekly_sales END) -
         AVG(CASE WHEN is_holiday = 0 THEN weekly_sales END))
        * 100.0 /
        NULLIF(AVG(CASE WHEN is_holiday = 0 THEN weekly_sales END), 0)
    , 1)                                                           AS holiday_lift_pct
FROM sales
GROUP BY store
ORDER BY holiday_lift_pct DESC;
-- Insight: Store 35 shows highest lift at +18%, Store 7 at +17.9%.


-- 4.6 Which Markdown drives the most sales?
SELECT
    'MarkDown1' AS markdown,
    ROUND(AVG(CASE WHEN f.markdown1 IS NOT NULL THEN s.weekly_sales END), 2) AS avg_sales_with,
    ROUND(AVG(CASE WHEN f.markdown1 IS NULL     THEN s.weekly_sales END), 2) AS avg_sales_without
FROM sales s
JOIN features f ON s.store = f.store AND s.date = f.date
UNION ALL
SELECT 'MarkDown2',
    ROUND(AVG(CASE WHEN f.markdown2 IS NOT NULL THEN s.weekly_sales END), 2),
    ROUND(AVG(CASE WHEN f.markdown2 IS NULL     THEN s.weekly_sales END), 2)
FROM sales s JOIN features f ON s.store = f.store AND s.date = f.date
UNION ALL
SELECT 'MarkDown3',
    ROUND(AVG(CASE WHEN f.markdown3 IS NOT NULL THEN s.weekly_sales END), 2),
    ROUND(AVG(CASE WHEN f.markdown3 IS NULL     THEN s.weekly_sales END), 2)
FROM sales s JOIN features f ON s.store = f.store AND s.date = f.date
UNION ALL
SELECT 'MarkDown4',
    ROUND(AVG(CASE WHEN f.markdown4 IS NOT NULL THEN s.weekly_sales END), 2),
    ROUND(AVG(CASE WHEN f.markdown4 IS NULL     THEN s.weekly_sales END), 2)
FROM sales s JOIN features f ON s.store = f.store AND s.date = f.date
UNION ALL
SELECT 'MarkDown5',
    ROUND(AVG(CASE WHEN f.markdown5 IS NOT NULL THEN s.weekly_sales END), 2),
    ROUND(AVG(CASE WHEN f.markdown5 IS NULL     THEN s.weekly_sales END), 2)
FROM sales s JOIN features f ON s.store = f.store AND s.date = f.date;
-- Insight: MarkDown4 (+9.9%) and MarkDown2 (+9.3%) are most effective.
--          MarkDown1 and MarkDown5 show only ~2% lift — poor ROI.


-- 4.7 Holiday Event Breakdown
SELECT
    CASE
        WHEN MONTH(date) = 2  THEN 'Super Bowl (Feb)'
        WHEN MONTH(date) = 9  THEN 'Labour Day (Sep)'
        WHEN MONTH(date) = 11 THEN 'Thanksgiving (Nov)'
        WHEN MONTH(date) = 12 THEN 'Christmas (Dec)'
        ELSE 'Other Holiday'
    END                          AS holiday_event,
    COUNT(DISTINCT date)         AS holiday_weeks,
    ROUND(AVG(weekly_sales), 2)  AS avg_weekly_sales,
    ROUND(SUM(weekly_sales), 2)  AS total_sales
FROM sales
WHERE is_holiday = 1
GROUP BY holiday_event
ORDER BY avg_weekly_sales DESC;
-- Insight: Thanksgiving is the strongest holiday ($22,220 avg).
--          Christmas ranks last ($14,543) — spending spreads across multiple weeks.


-- 4.8 Year-over-Year Sales Growth using LAG()
WITH yearly_sales AS (
    SELECT
        store,
        YEAR(date)                  AS yr,
        ROUND(SUM(weekly_sales), 2) AS annual_sales
    FROM sales
    WHERE weekly_sales > 0
    GROUP BY store, YEAR(date)
)
SELECT
    store,
    yr,
    annual_sales,
    LAG(annual_sales) OVER (PARTITION BY store ORDER BY yr) AS prev_year_sales,
    ROUND(
        (annual_sales - LAG(annual_sales) OVER (PARTITION BY store ORDER BY yr))
        * 100.0 /
        NULLIF(LAG(annual_sales) OVER (PARTITION BY store ORDER BY yr), 0)
    , 1)                                                     AS yoy_growth_pct
FROM yearly_sales
ORDER BY store, yr;
-- Insight: Almost every store grew in 2011 (Store 4: +16.1%, Store 1: +10.4%).
--          2012 decline is partly due to incomplete year (data ends Oct 2012).


-- 4.9 Monthly Sales Seasonality
SELECT
    MONTH(date)                 AS month_num,
    MONTHNAME(date)             AS month_name,
    ROUND(AVG(weekly_sales), 2) AS avg_weekly_sales,
    ROUND(SUM(weekly_sales), 2) AS total_sales
FROM sales
WHERE weekly_sales > 0
GROUP BY MONTH(date), MONTHNAME(date)
ORDER BY month_num;
-- Insight: December peaks at $19,425 avg — 37% higher than January ($14,182).
--          July performs well — likely back-to-school shopping season.


-- 4.10 Does Unemployment affect Sales?
SELECT
    CASE
        WHEN f.unemployment < 7  THEN 'Low (<7%)'
        WHEN f.unemployment < 10 THEN 'Medium (7-10%)'
        ELSE                          'High (>10%)'
    END                             AS unemployment_band,
    COUNT(*)                        AS week_store_count,
    ROUND(AVG(s.weekly_sales), 2)   AS avg_weekly_sales
FROM sales s
JOIN features f ON s.store = f.store AND s.date = f.date
WHERE s.weekly_sales > 0
  AND f.unemployment IS NOT NULL
GROUP BY unemployment_band
ORDER BY avg_weekly_sales DESC;
-- Insight: Medium unemployment areas (7-10%) outsell low unemployment areas.
--          Walmart's value positioning resonates most with budget-conscious shoppers.


-- ================================================================
-- SECTION 5 : VIEWS & STORED PROCEDURES
-- ================================================================

-- 5.1 View: Store summary snapshot
CREATE OR REPLACE VIEW vw_store_summary AS
SELECT
    s.store,
    st.type                       AS store_type,
    st.size                       AS store_size_sqft,
    COUNT(DISTINCT s.dept)        AS active_depts,
    COUNT(DISTINCT s.date)        AS total_weeks,
    ROUND(SUM(s.weekly_sales), 2) AS total_revenue,
    ROUND(AVG(s.weekly_sales), 2) AS avg_weekly_sales,
    ROUND(MAX(s.weekly_sales), 2) AS best_week_sales
FROM sales s
JOIN stores st ON s.store = st.store
WHERE s.weekly_sales > 0
GROUP BY s.store, st.type, st.size;

SELECT * FROM vw_store_summary ORDER BY total_revenue DESC;


-- 5.2 View: Holiday impact per store
CREATE OR REPLACE VIEW vw_holiday_impact AS
SELECT
    store,
    ROUND(AVG(CASE WHEN is_holiday = 1 THEN weekly_sales END), 2) AS avg_holiday_sales,
    ROUND(AVG(CASE WHEN is_holiday = 0 THEN weekly_sales END), 2) AS avg_normal_sales,
    ROUND(
        (AVG(CASE WHEN is_holiday = 1 THEN weekly_sales END) -
         AVG(CASE WHEN is_holiday = 0 THEN weekly_sales END))
        * 100.0 /
        NULLIF(AVG(CASE WHEN is_holiday = 0 THEN weekly_sales END), 0)
    , 1)                                                           AS holiday_lift_pct
FROM sales
GROUP BY store;

SELECT * FROM vw_holiday_impact ORDER BY holiday_lift_pct DESC;


-- 5.3 Stored Procedure: Full performance report for any store
-- Usage: CALL sp_store_report(20);
DELIMITER $$
CREATE PROCEDURE sp_store_report(IN p_store INT)
BEGIN
    -- Basic store info
    SELECT store, type, size
    FROM stores
    WHERE store = p_store;

    -- Year-wise revenue breakdown
    SELECT
        YEAR(date)                  AS yr,
        ROUND(SUM(weekly_sales), 2) AS annual_revenue,
        ROUND(AVG(weekly_sales), 2) AS avg_weekly_sales,
        COUNT(DISTINCT dept)        AS active_depts
    FROM sales
    WHERE store = p_store AND weekly_sales > 0
    GROUP BY YEAR(date)
    ORDER BY yr;

    -- Top 5 departments for this store
    SELECT
        dept,
        ROUND(SUM(weekly_sales), 2) AS dept_revenue
    FROM sales
    WHERE store = p_store AND weekly_sales > 0
    GROUP BY dept
    ORDER BY dept_revenue DESC
    LIMIT 5;

    -- Holiday vs normal week comparison
    SELECT
        CASE WHEN is_holiday = 1 THEN 'Holiday' ELSE 'Normal' END AS week_type,
        ROUND(AVG(weekly_sales), 2)                                AS avg_sales
    FROM sales
    WHERE store = p_store
    GROUP BY is_holiday;
END$$
DELIMITER ;

CALL sp_store_report(20);


-- 5.4 Stored Procedure: Markdown effectiveness for any store
-- Usage: CALL sp_markdown_report(20);
DELIMITER $$
CREATE PROCEDURE sp_markdown_report(IN p_store INT)
BEGIN
    SELECT
        'MarkDown1' AS markdown,
        ROUND(AVG(CASE WHEN f.markdown1 IS NOT NULL THEN s.weekly_sales END), 2) AS avg_with_markdown,
        ROUND(AVG(CASE WHEN f.markdown1 IS NULL     THEN s.weekly_sales END), 2) AS avg_without_markdown,
        ROUND(
            (AVG(CASE WHEN f.markdown1 IS NOT NULL THEN s.weekly_sales END) -
             AVG(CASE WHEN f.markdown1 IS NULL     THEN s.weekly_sales END))
            * 100.0 /
            NULLIF(AVG(CASE WHEN f.markdown1 IS NULL THEN s.weekly_sales END), 0)
        , 1)                                                                      AS lift_pct
    FROM sales s
    JOIN features f ON s.store = f.store AND s.date = f.date
    WHERE s.store = p_store
    UNION ALL
    SELECT 'MarkDown2',
        ROUND(AVG(CASE WHEN f.markdown2 IS NOT NULL THEN s.weekly_sales END), 2),
        ROUND(AVG(CASE WHEN f.markdown2 IS NULL     THEN s.weekly_sales END), 2),
        ROUND(
            (AVG(CASE WHEN f.markdown2 IS NOT NULL THEN s.weekly_sales END) -
             AVG(CASE WHEN f.markdown2 IS NULL     THEN s.weekly_sales END))
            * 100.0 /
            NULLIF(AVG(CASE WHEN f.markdown2 IS NULL THEN s.weekly_sales END), 0)
        , 1)
    FROM sales s JOIN features f ON s.store = f.store AND s.date = f.date
    WHERE s.store = p_store
    UNION ALL
    SELECT 'MarkDown3',
        ROUND(AVG(CASE WHEN f.markdown3 IS NOT NULL THEN s.weekly_sales END), 2),
        ROUND(AVG(CASE WHEN f.markdown3 IS NULL     THEN s.weekly_sales END), 2),
        ROUND(
            (AVG(CASE WHEN f.markdown3 IS NOT NULL THEN s.weekly_sales END) -
             AVG(CASE WHEN f.markdown3 IS NULL     THEN s.weekly_sales END))
            * 100.0 /
            NULLIF(AVG(CASE WHEN f.markdown3 IS NULL THEN s.weekly_sales END), 0)
        , 1)
    FROM sales s JOIN features f ON s.store = f.store AND s.date = f.date
    WHERE s.store = p_store
    UNION ALL
    SELECT 'MarkDown4',
        ROUND(AVG(CASE WHEN f.markdown4 IS NOT NULL THEN s.weekly_sales END), 2),
        ROUND(AVG(CASE WHEN f.markdown4 IS NULL     THEN s.weekly_sales END), 2),
        ROUND(
            (AVG(CASE WHEN f.markdown4 IS NOT NULL THEN s.weekly_sales END) -
             AVG(CASE WHEN f.markdown4 IS NULL     THEN s.weekly_sales END))
            * 100.0 /
            NULLIF(AVG(CASE WHEN f.markdown4 IS NULL THEN s.weekly_sales END), 0)
        , 1)
    FROM sales s JOIN features f ON s.store = f.store AND s.date = f.date
    WHERE s.store = p_store
    UNION ALL
    SELECT 'MarkDown5',
        ROUND(AVG(CASE WHEN f.markdown5 IS NOT NULL THEN s.weekly_sales END), 2),
        ROUND(AVG(CASE WHEN f.markdown5 IS NULL     THEN s.weekly_sales END), 2),
        ROUND(
            (AVG(CASE WHEN f.markdown5 IS NOT NULL THEN s.weekly_sales END) -
             AVG(CASE WHEN f.markdown5 IS NULL     THEN s.weekly_sales END))
            * 100.0 /
            NULLIF(AVG(CASE WHEN f.markdown5 IS NULL THEN s.weekly_sales END), 0)
        , 1)
    FROM sales s JOIN features f ON s.store = f.store AND s.date = f.date
    WHERE s.store = p_store;
END$$
DELIMITER ;

CALL sp_markdown_report(20);

-- ================================================================
-- END OF PROJECT
-- SQL concepts used:
--   JOIN, CTE, CASE, RANK(), DENSE_RANK(), LAG(),
--   NULLIF, STR_TO_DATE, UNION ALL,
--   CREATE VIEW, STORED PROCEDURE
-- ================================================================
