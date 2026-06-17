# Walmart Retail Sales Analytics — SQL Project

A complete end-to-end SQL analysis of Walmart's weekly store sales data across 45 stores, 99 departments, and 143 weeks. The project covers data loading, cleaning, exploratory analysis, business insights, and reusable views and stored procedures — all written in MySQL.

---

## About the Dataset

**Source:** [Walmart Store Sales Forecasting — Kaggle](https://www.kaggle.com/datasets/manjeetsingh/retaildataset)

The dataset contains three tables:

| Table | Rows | Description |
|---|---|---|
| stores | 45 | Store type (A/B/C) and size in sq ft |
| features | 8,190 | Weekly temperature, fuel price, CPI, unemployment, markdowns |
| sales | 4,21,570 | Weekly sales per store per department (Feb 2010 – Oct 2012) |

Walmart runs promotional markdown events before major holidays — Super Bowl, Labour Day, Thanksgiving, and Christmas. Holiday weeks are weighted 5x higher in business importance than normal weeks.

---

## Business Problems

The project addresses three core business questions:

1. **Which stores and departments are performing well — and which aren't?**
2. **Are promotional markdowns actually driving more sales, especially during holidays?**
3. **What do sales trends look like year over year, and what should the business do next?**

---

## Project Structure

```
walmart-retail-sql/
│
├── walmart_retail_analytics.sql   # Complete SQL file (all 5 sections)
├── README.md                      # This file
│
└── datasets/
    ├── stores_dataset.csv
    ├── features_dataset.csv
    └── sales_dataset.csv
```

---

## How to Run

**Step 1** — Open MySQL Workbench and create the database:
```sql
CREATE DATABASE walmart_retail;
USE walmart_retail;
```

**Step 2** — Run Section 1 of the SQL file to create the three tables.

**Step 3** — Copy the three CSV files into your MySQL secure upload folder:
```
C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/
```

**Step 4** — Run Section 2 to load data. The queries handle:
- `STR_TO_DATE` for DD/MM/YYYY date format conversion
- `NULLIF` to convert NA strings to proper NULLs in markdown and CPI columns
- `LINES TERMINATED BY '\r\n'` to fix Windows line endings on the sales file
- `TRIM()` to remove invisible `\r` characters from boolean IsHoliday values
- `LOAD DATA IGNORE` to skip duplicate `(store, dept, date)` rows in sales

**Step 5** — Run Sections 3, 4, and 5 in order.

---

## SQL Concepts Used

| Concept | Where used |
|---|---|
| `JOIN` | Linking sales ↔ stores ↔ features |
| `CTE` (WITH clause) | Store revenue ranking, YoY growth |
| `CASE` | Holiday segmentation, unemployment bands |
| `RANK()`, `DENSE_RANK()` | Store performance ranking within type and overall |
| `LAG()` | Year-over-year growth calculation |
| `NULLIF` | Handling markdown and CPI NULLs, safe division |
| `STR_TO_DATE` | Date format conversion on load |
| `GROUP BY`, `HAVING` | Aggregations across stores and departments |
| `UNION ALL` | Markdown comparison across 5 columns |
| `CREATE VIEW` | Reusable store summary and holiday impact snapshots |
| `STORED PROCEDURE` | On-demand store and markdown reports |

---

## Key Findings

**Store Performance**

Store 20 is the top performer with $30.1 crore in total revenue and $29,627 average weekly sales, despite not being the largest store by size. Store 4 follows closely at $29.9 crore. Store 33 is the weakest — generating only $3.7 crore total, nearly 8x less than Store 20, despite being classified as a Type A store. This mismatch between store type and revenue is a red flag worth investigating. Store 10 is a standout Type B store, ranking 6th overall and outperforming several Type A stores.

**Department Performance**

Department 92 is the highest revenue generator across all 45 stores at $48.3 crore with an average weekly sales of $75,204 — roughly 5x the company average. Department 95 follows at $44.9 crore. All top 10 departments are present in every one of the 45 stores, confirming these are core categories that must be protected in inventory planning and markdown campaigns.

**Holiday Impact**

Holiday weeks generate 5–18% more sales than normal weeks depending on the store. Store 35 shows the highest holiday lift at +18%, followed by Store 7 at +17.9%. Thanksgiving (November) is the strongest holiday event with an average weekly sales of $22,220 — higher than Christmas ($14,543), Super Bowl ($16,378), and Labour Day ($15,881). Christmas ranking last is counterintuitive but makes sense — December spending is spread across multiple weeks, diluting the weekly average.

**Markdown Effectiveness**

All 5 markdowns show a positive impact on sales when active. MarkDown4 and MarkDown2 are the most effective, driving 9.9% and 9.3% higher average sales respectively compared to weeks without them. MarkDown1 and MarkDown5 show the weakest lift at around 2% — budget allocated to these would have better ROI if redirected toward MD2 and MD4 campaigns.

**Year-over-Year Trends**

Nearly every store grew in 2011 compared to 2010 — Store 4 grew 16.1%, Store 1 grew 10.4%. The 2012 data shows a decline across stores, but this is partly due to incomplete data (only up to October 2012). A fair year-on-year comparison requires adjusting for the missing November and December period.

**Seasonality**

December is the peak month with $19,425 average weekly sales — 37% higher than January ($14,182) which is the lowest month. July performs well, likely driven by back-to-school shopping. September dips despite Labour Day, suggesting the holiday alone does not sustain sales for the full month.

**External Factors**

Stores in medium unemployment regions (7–10%) generate the highest average weekly sales at $16,810, outperforming even low unemployment areas ($15,146). This suggests Walmart's value-for-money positioning resonates most with shoppers in mid-tier economic conditions — a useful insight for regional expansion decisions.

---

## Reusable Objects

**Views**
```sql
-- Quick snapshot of all 45 stores
SELECT * FROM vw_store_summary ORDER BY total_revenue DESC;

-- Holiday performance across stores
SELECT * FROM vw_holiday_impact ORDER BY holiday_lift_pct DESC;
```

**Stored Procedures**
```sql
-- Full performance report for any store
CALL sp_store_report(20);

-- Markdown effectiveness for any store
CALL sp_markdown_report(20);
```

---

## Data Quality Notes

- **Negative sales** — 1,285 rows (0.3%) have negative weekly sales due to customer returns and corrections. Excluded from revenue aggregations using `WHERE weekly_sales > 0`.
- **Markdown NULLs** — 50–64% of markdown values are NULL. Expected — markdowns only started after November 2011 and were not applied uniformly. Handled using `NULLIF` on load.
- **CPI and Unemployment NULLs** — A small number of rows had NA values in these columns too. Same `NULLIF` approach applied on load.
- **Duplicate rows** — A small number of duplicate `(store, dept, date)` combinations existed in the raw sales CSV. Handled using `LOAD DATA INFILE ... IGNORE`.
- **Date format** — Source CSV uses DD/MM/YYYY. Converted using `STR_TO_DATE(@raw_date, '%d/%m/%Y')` on load.
- **Windows line endings** — The IsHoliday column in the sales file had invisible `\r` characters causing all values to load as FALSE. Fixed using `LINES TERMINATED BY '\r\n'` and `TRIM()`.

---

## Tools Used

- MySQL 8.0
- MySQL Workbench
- Dataset: [Walmart Store Sales Forecasting — Kaggle](https://www.kaggle.com/datasets/manjeetsingh/retaildataset)
