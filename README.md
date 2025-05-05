# Olist Sales Funnel Analysis

## 📖 Project Overview

This project analyzes the Olist e-commerce dataset, with the main goal of identifying key stages in the sales funnel and understanding where customers drop off in their journey. By cleaning, processing, and analyzing the data, the project aims to uncover insights that can help improve customer retention, optimize marketing efforts, and enhance overall sales performance.

The analysis will focus on the following:
- Examining the customer journey from initial interaction to purchase.
- Identifying drop-off points and stages where customers abandon the funnel.
- Analyzing factors influencing these drop-offs, such as product types, payment methods, and review ratings.


## 📁 Project Structure

```
olist-sales-funnel-analysis/
├── data/
│ ├── raw/ # Contains original datasets from Olist
│ └── cleaned/ # Contains any cleaned datasets, temporary or final
├── sql/ # SQL scripts for various analysis steps, each project has its own folder
│ ├── funnel-analysis/
│ ├── price-analysis/
│ └── segmentation-analysis/
├── notebooks/ # Jupyter notebooks (if any) for exploratory data analysis (EDA)
│ ├── funnel-analysis/
│ ├── price-analysis/
│ └── segmentation-analysis/
├── reports/ # Contains any generated reports, graphs, or final conclusions
├── .gitignore
├── README.md
```
## 🛠 Installation
No external dependencies for now. Just clone the repo and start exploring the data or running SQL queries.

Now, let’s move on to the next section whenever you're ready. We could cover Usage next, or you can let me know if you'd like to adjust anything before proceeding!

## 📊 Analysis

### Data Cleaning

### 📊 Step 1: `order_status` and `order_approved_at` 

Valid Statuses, Approval Timestamps, and Delay Threshold
This first step ensures we’re only analyzing orders that reached a valid funnel stage and passed basic quality checks.

```sql
WITH cleaned_orders_step1 AS (
SELECT *
FROM olist_orders
WHERE
-- ✅ Keep only meaningful order statuses
order_status IN ('delivered', 'shipped')

    -- ❌ Drop rows with missing approval timestamp
    AND order_approved_at IS NOT NULL 

    -- ⏱️ Remove extreme outliers with approval delay > 20 days
    AND EXTRACT(EPOCH FROM (order_approved_at - order_purchase_timestamp)) / 86400 <= 20 
)

SELECT *
FROM cleaned_orders_step1
```

#### 🔍 Cleaning Logic Summary

❌ Dropped rows where `order_status` was in:

`'canceled'`, `'unavailable'`, `'processing'`, `'invoiced'`, `'created'`, `'approved'`

✅ Kept only:

`'delivered'`, `'shipped'` (only these can reach key funnel stages)

📉 Rows Dropped: 1,856
✅ Remaining: 97,585

🧹 Approval Timestamp Cleaning
🔍 14 rows had NULL `order_approved_at`, despite having other timestamps

🧠 Approval is mandatory to progress — these rows are invalid

📉 Rows Dropped: 14 ✅ Remaining: 97,571

🕐 Approval Delay Outliers
🔍 Dropped rows where approval delay was > 20 days

Reason: Unreasonably long approval times are likely anomalies

📉 Rows Dropped: 4 ✅ Final Remaining: 97,567

---
```sql
SELECT
    CASE 
        WHEN order_approved_at < order_purchase_timestamp THEN '❌ Approval BEFORE Purchase'
        WHEN order_approved_at = order_purchase_timestamp THEN '🟡 Approval at SAME Second'
        WHEN order_approved_at > order_purchase_timestamp THEN '✅ Approval AFTER Purchase'
    END AS approval_timing_category,
    COUNT(*) AS row_count
FROM cleaned_orders_step1
GROUP BY approval_timing_category
ORDER BY row_count DESC
```
❌ Rows with approval before purchase: 0

🟡 Rows with approval at same second: 1,265 (Kept as plausible)

✅ Rows approved after purchase: 96,306


📉 Rows Dropped: 0 ✅ Final Remaining: 97,567

### Remaining clean data ✅ 97,567 rows


*This query was used to validate the logical consistency between `order_purchase_timestamp` and `order_approved_at`.*

*I didn't include this filter in the main CTE because the data was already clean — no rows had approval before purchase, and same-second approvals (1,265 rows) were considered plausible and kept. This validation step is shown here to demonstrate thorough data quality checks.*

---

### 📊 Step 2 : `order_delivered_carrier_date` & Carrier Pickup Time

In this step, I cleaned the order_delivered_carrier_date and days_to_carrier fields to ensure that no invalid or extreme values skew the analysis.

```sql
WITH cleaned_orders_step2 AS (
    SELECT 
        o.*, 
        ROUND(EXTRACT(EPOCH FROM (o.order_approved_at - o.order_purchase_timestamp)) / 86400, 2) AS days_to_approve,
        ROUND(EXTRACT(EPOCH FROM (o.order_delivered_carrier_date - o.order_approved_at)) / 86400, 2) AS days_to_carrier
    FROM olist_orders o
    WHERE 
        order_status IN ('delivered', 'shipped')  -- ✅ Only orders that could continue through the funnel

        -- 🧹 Drop rows with missing timestamps
        AND order_approved_at IS NOT NULL  
        AND order_delivered_carrier_date IS NOT NULL  

        -- 🧹 Remove logically invalid sequences
        AND o.order_delivered_carrier_date > o.order_approved_at  
        
        -- ⏱️ Keep orders with approval delays ≤ 20 days
        AND ROUND(EXTRACT(EPOCH FROM (o.order_approved_at - o.order_purchase_timestamp)) / 86400, 2) <= 20 
        
        -- ⏱️ Keep realistic pickup times (2 hours to 15 days)
        AND ROUND(EXTRACT(EPOCH FROM (o.order_delivered_carrier_date - o.order_approved_at)) / 86400, 2) 
            BETWEEN 0.08 AND 15         
)

SELECT * 
FROM cleaned_orders_step2
```

#### 🔍 Cleaning Logic Summary

📦 Cleaning `order_delivered_carrier_date`

- 🔍 Null values in `order_delivered_carrier_date`:
❌ Dropped: 2 rows

- 🔍 Invalid sequencing: Delivered to carrier before approval
❌ Dropped: 1,359 rows


#### ⏱️ Cleaning days_to_carrier
- ⚡ Too fast carrier pickup (< 0.08 days ≈ under 2 hours):
🧹 Dropped rows: 935 (likely system/logging error)

- 🐢 Too slow carrier pickup (> 15 days):
🧹 Dropped rows: 1,334 (likely operational failures or data issues)

#### ✅ Cleaned Data Summary

**1.** Null values or invalid sequencing  
- ❌ Dropped 1,361 rows

**2.** `days_to_carrier` acceptable range is 2 hours to 15 days; all values outside this range are considered unrealistic.

- ❌ Dropped rows: 935 (Too fast - likely system/logging error) 
- ❌ Dropped rows: 1,334 (Too slow - likely operational failures or data issues)

### Remanining clean data ✅ 93,937 rows

---

### 📦 Step 3:  `order_delivered_customer_date` and Delivery Time Calculation

This step focuses on cleaning the final delivery timestamp to customers and computing realistic delivery durations. We apply quality filters to ensure logical delivery sequences and eliminate outliers in delivery speed.

```sql
WITH cleaned_orders_step3 AS (
    SELECT 
        o.*, 
        -- ⏱️ Time from purchase to approval
        ROUND(EXTRACT(EPOCH FROM (o.order_approved_at - o.order_purchase_timestamp)) / 86400, 2) AS days_to_approve,

        -- ⏱️ Time from approval to carrier pickup
        ROUND(EXTRACT(EPOCH FROM (o.order_delivered_carrier_date - o.order_approved_at)) / 86400, 2) AS days_to_carrier,

        -- ⏱️ Time from carrier pickup to customer delivery
        ROUND(EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_delivered_carrier_date)) / 86400, 2) AS days_to_customer
    FROM olist_orders o
    WHERE 
        order_status IN ('delivered', 'shipped')  -- ✅ Only orders that could continue through the funnel

        -- 🧹 Drop rows with missing timestamps
        AND order_approved_at IS NOT NULL                      
        AND order_delivered_carrier_date IS NOT NULL           
        AND order_delivered_customer_date IS NOT NULL      

        -- 🧹 Remove invalid time sequences
        AND o.order_delivered_carrier_date > o.order_approved_at 
        AND o.order_delivered_customer_date >= o.order_delivered_carrier_date 

        -- ⏱️ Keep orders with approval delays ≤ 20 days
        AND ROUND(EXTRACT(EPOCH FROM (o.order_approved_at - o.order_purchase_timestamp)) / 86400, 2) <= 20 

        -- ⏱️ Keep realistic pickup times (2 hours to 15 days)
        AND ROUND(EXTRACT(EPOCH FROM (o.order_delivered_carrier_date - o.order_approved_at)) / 86400, 2) 
            BETWEEN 0.08 AND 15         

        -- ⏱️ Keep delivery times between 1 and 60 days
        AND ROUND(EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_delivered_carrier_date)) / 86400, 2) 
            BETWEEN 1 AND 60            
)

SELECT * 
FROM cleaned_orders_step3
```

#### 🔍 Cleaning order_delivered_customer_date

- 🧼 Dropped rows with NULL order_delivered_customer_date
📉 Rows Dropped: 1,070

- ⛔ Dropped rows where delivery to customer was before carrier pickup
📉 Rows Dropped: 23

#### ⏱️ Cleaning days_to_customer (Delivery Time)

- ⚡ Dropped deliveries that were too fast (less than 1 day) → implausible for real-world shipping
📉 Rows Dropped: 2,499

- 🐢 Dropped deliveries that took over 60 days → likely extreme cases or data issues
📉 Rows Dropped: 217

#### ✅ Cleaned Data Summary
**1**. Null values or invalid sequencing

- ❌ Dropped rows: 1,070 (order_delivered_customer_date is NULL)

- ❌ Dropped rows: 23 (order_delivered_customer_date before order_delivered_carrier_date)

**2**. days_to_customer acceptable range is 1 to 60 days; all values outside this range are considered unrealistic.

- ❌ Dropped rows: 2,499 (Delivery too fast: less than 1 day)

- ❌ Dropped rows: 217 (Delivery took more than 60 days - likely extreme cases or data issues)

### ✅ Remaining clean data: 90,128 rows

---
### 🔍 Additional Curiosity -  Delivery Timing Analysis

```sql
SELECT 
    CASE 
        WHEN order_delivered_customer_date < order_estimated_delivery_date THEN 'Delivered Before Estimated Date'
        WHEN order_delivered_customer_date > order_estimated_delivery_date THEN 'Delivered After Estimated Date'
    END AS delivery_timing,
    COUNT(*) AS row_count
FROM cleaned_orders_step3

GROUP BY delivery_timing
ORDER BY row_count DESC
```

**1**. Orders delivered before the estimated delivery date
- ✅ 83,221 rows

**2**. Orders delivered after the estimated delivery date

- ❌ 6,907 rows

*Note:
I was also curious about this aspect, but it doesn’t fit directly into the current step. I wanted to show this data as part of a future step. Specifically, I plan to explore if the orders delivered later than estimated are linked to customer complaints.*

---

### ✅ Step 4: Join with Reviews — Customer Satisfaction Analysis

In this step, we integrated the `olist_order_reviews` table to incorporate customer satisfaction scores and focus on orders with positive feedback.

```sql
WITH cleaned_orders_step4 AS ( 
    SELECT 
        o.*, 
        r.review_score,

        -- ⏱️ Time from purchase to approval
        ROUND(EXTRACT(EPOCH FROM (o.order_approved_at - o.order_purchase_timestamp)) / 86400, 2) AS days_to_approve,

        -- ⏱️ Time from approval to carrier pickup
        ROUND(EXTRACT(EPOCH FROM (o.order_delivered_carrier_date - o.order_approved_at)) / 86400, 2) AS days_to_carrier,

        -- ⏱️ Time from carrier pickup to customer delivery
        ROUND(EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_delivered_carrier_date)) / 86400, 2) AS days_to_customer
    FROM olist_orders o

    -- 🔗 Join with reviews to get customer satisfaction
    JOIN olist_order_reviews r ON o.order_id = r.order_id

    WHERE 
        order_status IN ('delivered', 'shipped')  -- ✅ Only orders that could continue through the funnel

        -- 🧹 Drop rows with missing timestamps
        AND order_approved_at IS NOT NULL                      
        AND order_delivered_carrier_date IS NOT NULL           
        AND order_delivered_customer_date IS NOT NULL            

        -- 🧹 Remove invalid time sequences
        AND o.order_delivered_carrier_date > o.order_approved_at 
        AND o.order_delivered_customer_date >= o.order_delivered_carrier_date 

        -- ⏱️ Keep orders with approval delays ≤ 20 days
        AND ROUND(EXTRACT(EPOCH FROM (o.order_approved_at - o.order_purchase_timestamp)) / 86400, 2) <= 20 
        
        -- ⏱️ Keep realistic pickup times (2 hours to 15 days)
        AND ROUND(EXTRACT(EPOCH FROM (o.order_delivered_carrier_date - o.order_approved_at)) / 86400, 2) 
            BETWEEN 0.08 AND 15         

        -- ⏱️ Keep delivery times between 1 and 60 days
        AND ROUND(EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_delivered_carrier_date)) / 86400, 2) 
            BETWEEN 1 AND 60            

        -- 🌟 Only include satisfied customers (review score ≥ 4)
        AND r.review_score >= 4         
)

SELECT * 
FROM cleaned_orders_step4
```


### 📦 Joining with olist_order_reviews

#### 🔍 Rows with no matching order review:

- ❌ Dropped 789 rows

These orders did not have a corresponding entry in the reviews table.

#### ✅ Remaining rows after join 89,339 rows

### ⭐ Review Score Analysis

#### 📈 Orders with a review score of 4 or higher (indicating satisfaction) ✅ Kept 70,818 rows

These orders reflect a positive customer experience and were kept for further analysis.

### ✅ Cleaned Data Summary
**1**. Rows without matching reviews

- ❌ Dropped 789 rows

**2**. Review score filter (only satisfied customers, review score ≥ 4)

- ❌ Dropped 18,521 rows

- ✅ Kept rows: 70,818

*This process enables us to focus on the subset of orders with positive customer feedback and ensures that we are analyzing only those transactions with sufficient data to understand both operational and customer satisfaction aspects.*

### Remanining clean data ✅ 70,818 rows

---
### 📉 Funnel Drop-off Summary

This next table visualizes the progressive drop-offs through each major stage of the e-commerce fulfillment funnel. From the initial 99,441 orders, each cleaning step eliminates rows due to missing values, unrealistic timeframes, or unsatisfactory review scores.

The most significant drop occurred when filtering only positively reviewed orders (review_score ≥ 4), representing a 20.74% drop in rows at that stage.

| **Stage**             | **Remaining Rows** | **Dropped Rows (%)** | **Cumulative % Kept** | **Step** |
| --------------------- | ------------------ | -------------------- | --------------------- | -------- |
| Initial (No Cleaning) | 99,441             | -                    | 100%                  | -        |
| Order Created         | 97,585             | 1.86%                | 98.14%                | Step 1   |
| Order Approved        | 97,567             | 0.02%                | 98.12%                | Step 1   |
| Order Shipped         | 93,937             | 3.71%                | 94.42%                | Step 2   |
| Order Delivered       | 90,128             | 4.03%                | 90.66%                | Step 3   |
| Reviews Join          | 89,339             | 0.88%                | 89.97%                | Step 4   |
| Positively Reviewed   | 70,818             | 20.74%               | 71.32%                | Step 4   |


*Or a graph if you like more*

![Sales Funnel Graph](data\Graphs\sales-funnel-graph.png)

