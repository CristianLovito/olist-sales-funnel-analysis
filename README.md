
# Olist Sales Funnel Analysis


## Languages Available:
- [English](README.md)
- [Español](README.español.md)

readme english

## 📖 Project Overview

This project analyzes the **Olist e-commerce dataset**, with the main goal of identifying key stages in the **sales funnel** and understanding where **customers drop off** in their journey. By **cleaning**, **processing**, and **analyzing** the data, the project aims to uncover insights that can help **improve customer retention**, **optimize marketing efforts**, **enhance overall sales performance** and, **reduce customer churn rate**.

### 🔍The analysis will focus on the following:
- Examining the customer fulfillment journey — from order placement to product review.

- Identifying drop-off points across each stage of the fulfillment funnel.

- Analyzing how review scores relate to operational issues (e.g., delivery delays).


## 📁 Project Structure

```
olist-sales-funnel-analysis/
├── data/
│ ├── charts/
│ └── raw/ # Contains original datasets from Olist
├── sql/ # SQL scripts for various analysis steps, 
├── .gitignore
├── README.español.md
└── README.md
```
## 🛠 Installation
No external dependencies for now. Just clone the repo and start exploring the data or running SQL queries.

---

## 🧹Data Cleaning

### 📊 Step 1: `order_status` and `order_approved_at` 

Valid Statuses and Approval Timestamps - 
This first step ensures I'm **only analyzing orders that reached a valid funnel stage** and passed basic quality checks.

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

#### 🔍 Step 1: Cleaning Order Status & Approval Timestamp

#### 📦 Cleaning `order_status`

- ❌ Dropped rows where `order_status` was in:
`canceled`, `unavailable`, `processing`, `invoiced`, `created`, `approved`
(These orders were not shipped or delivered, so they cannot proceed through the funnel)

- 📉 Rows Dropped: 1,856

#### 🕒 Cleaning order_approved_at
- 🧼 Dropped rows with NULL `order_approved_at`
(14 rows had no approval timestamp despite having other timestamps — invalid data)

- 📉 Rows Dropped: 14

#### 🕐 Approval Delay Outliers
- 🔍 Dropped rows where approval delay was > 20 days
(Approval delays greater than 20 days are likely anomalies and considered invalid)

- 📉 Rows Dropped: 4

#### ✅ Cleaned Data Summary
**1**. Kept only valid order statuses: `delivered`, `shipped`

- ❌ Dropped: 1,856 rows

**2**. Mandatory approval timestamp check

- ❌ Dropped: 14 rows with NULL order_approved_at

**3**. Approval delay outliers (approval delay > 20 days)

- ❌ Dropped: 4 rows

### ✅ Remaining clean data: 97,567 rows

---
### 🔍 order_approved_at logic 

This query was used to validate the logical consistency between `order_purchase_timestamp` and `order_approved_at`.

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

#### 🔍 Cleaning Logic Summary

- ❌ Rows with approval before purchase: 0

- 🟡 Rows with approval at same second: 1,265 (Kept as plausible)

- ✅  Rows approved after purchase: 96,306


- 📉 Rows Dropped: 0 ✅ Final Remaining: 97,567

### Remaining clean data ✅ 97,567 rows

*I didn't include this filter in the main CTE because the data was already clean — no rows had approval before purchase, and same-second approvals (1,265 rows) were considered plausible and kept. This validation step is shown here to demonstrate thorough data quality checks.*

---

### 📊 Step 2 : `order_delivered_carrier_date` & Carrier Pickup Time

In this step, I cleaned the `order_delivered_carrier_date` and `days_to_carrier` fields to ensure that no invalid or extreme values skew the analysis.

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

#### 🔍 Cleaning `order_delivered_carrier_date`


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

**2.** `days_to_carrier` acceptable range is **2 hours to 15 days**; all values outside this range are considered unrealistic.

- ❌ Dropped rows: 935 (Too fast - likely system/logging error) 
- ❌ Dropped rows: 1,334 (Too slow - likely operational failures or data issues)

### Remanining clean data ✅ 93,937 rows

---

### 📦 Step 3:  `order_delivered_customer_date` and Delivery Time Calculation

This step focuses on cleaning the **final delivery timestamp** to customers and computing **realistic delivery durations**. We apply quality filters to ensure logical delivery sequences and eliminate outliers in **delivery speed**.

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

#### 🔍 Cleaning `order_delivered_customer_date`

- 🧼 Dropped rows with NULL `order_delivered_customer_date`
📉 Rows Dropped: 1,070

- ⛔ Dropped rows where delivery to customer was before carrier pickup
📉 Rows Dropped: 23

#### ⏱️ Cleaning `days_to_customer` (Delivery Time)

- ⚡ Dropped deliveries that were too fast (**less than 1 day**) → implausible for real-world shipping
📉 Rows Dropped: 2,499

- 🐢 Dropped deliveries that took over **60 days** → likely extreme cases or data issues
📉 Rows Dropped: 217

#### ✅ Cleaned Data Summary
**1**. Null values or invalid sequencing

- ❌ Dropped rows: 1,070 (`order_delivered_customer_date` is NULL)

- ❌ Dropped rows: 23 (`order_delivered_customer_date` before `order_delivered_carrier_date`)

**2**. `days_to_customer` acceptable range is **1 to 60 days**; all values outside this range are considered unrealistic.

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
I was curious about this aspect, but it doesn’t fit directly into the current step. I wanted to show this data as part of a future analysis. Specifically, I plan to explore if the orders delivered later than estimated are linked to customer complaints.*

---

### ✅ Step 4: Join with Reviews — Customer Satisfaction Analysis

In this step, we integrated the `olist_order_reviews` table to incorporate **customer satisfaction scores** and focus on orders with positive feedback.

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

This next table visualizes the progressive drop-offs through each major stage of the **e-commerce fulfillment funnel**. From the initial **99,441 orders**, each cleaning step eliminates rows due to **missing values, unrealistic timeframes, or unsatisfactory review scores**.

**The most significant drop** occurred when filtering only **positively reviewed orders (review_score ≥ 4)**, representing a **20.74%** drop in rows at that stage.

| **Stage**             | **Remaining Rows** | **Dropped Rows (%)** | **Cumulative % Kept** | **Step** |
| --------------------- | ------------------ | -------------------- | --------------------- | -------- |
| Initial (No Cleaning) | 99,441             | -                    | 100%                  | -        |
| Order Created         | 97,585             | 1.86%                | 98.14%                | Step 1   |
| Order Approved        | 97,567             | 0.02%                | 98.12%                | Step 1   |
| Order Shipped         | 93,937             | 3.71%                | 94.42%                | Step 2   |
| Order Delivered       | 90,128             | 4.03%                | 90.66%                | Step 3   |
| Reviews Join          | 89,339             | 0.88%                | 89.97%                | Step 4   |
| Positively Reviewed   | 70,818             | 20.74%               | 71.32%                | Step 4   |


#### *Or a graph if you like more*

![Sales Funnel Graph](data\charts\sales-funnel-graph.png)
*Note:* The chart was created 100% using AI after 20 minutes of iterations with python. The AI helped in generating and optimizing the visual representation of the data cleaning process efficiently.

---

### 📉Funnel Drop-off Analysis:

Exploring the **20.74%** Drop
As part of the analysis, I investigated the reasons behind the **20.74%** drop in the funnel, focusing specifically on the **1-2 score reviews**. Below is the breakdown of the most common complaints raised by customers.

### Key Findings from 1-2 Star Reviews:
#### Issue	Percentage of Total Complaints	Count (300 Valid Reviews)


#### 🚚Shipping/Delivery Issues (Total)	63.41%	190
- Missing orders when ordering multiple products	9.76%	30
- Delayed orders or not received	51.83%	155
- Product blocked in customs	2.44%	7


#### 📦Product Issues (Total)	30.49%	91
- Incorrect version of the product	4.27%	13
- Sent incorrect product	4.27%	13
- Product received with missing pieces	3.66%	11
- Product received broken	10.98%	33
- Misleading product	1.83%	6
- Bad quality of the products	5.49%	17


#### 🧑‍💼Order/Customer Service Issues (Total)	3.05%	9
- Could not cancel the order	1.83%	5
- Bad attention (poor customer service)	1.22%	4


#### ❓Review/Score Confusion (Total)	2.44%	7
- Good review, bad score?	2.44%	7


---


### 🧠 Summary of 1–2 Star Review Analysis

#### 🚚Main source of negative reviews (Shipping)

The biggest issue by far **(63.4%)** is the **shipping and delivery process**, with over half **(51.8%)** of total complaints related to products arriving **extremely late** or not arriving at all. Many customers mention that they don’t even receive updates on the delivery status, which leads to complete **frustration, loss of trust**, and giving up on the order.

#### 📦Product-related issues
The second most frequent cause **(30.5%)** is **the product itself** — whether it arrives **broken**, is of **poor quality**, or it's **the wrong item**. Even when the product is delivered, there’s a significant **1 in 3 risk** that it disappoints. Many users state outright that they **would not order again** due to this.

#### 🧑‍💼Customer service perception
Only **3%** of reviews directly complain about **customer service**, but many reviews from other categories imply a **lack of support** when problems arise. **The silence or inaction from the company when customers need help** severely worsens the experience, even if it’s not always directly mentioned.

#### ❓Review interface confusion
Finally, **2.4%** of the reviews appear to be **user errors** — people leaving good comments but assigning bad scores. This seems like an **interface or user experience flaw**, but it’s minor and not a core issue.


---


## Final Recomendations
### 🚚 Shipping & Delivery Recommendations

- **1**. Implement a **Basic Order Tracking System**
Customers are repeatedly **left in the dark** about their order status. Even a simple tracking panel (on web/app) that shows if the product is shipped, in transit, or delayed would **dramatically reduce frustration**. Visibility builds trust — and right now, that **trust is broken**.

- **2**. Audit and **Improve Carrier Performance**
Based on the analysis, delays and damaged/missing products are the two most common complaints. This points to **poor coordination between Olist and external delivery partners**. Olist should run a performance audit on their last-mile delivery operations and enforce stricter SLAs (Service Level Agreements) with carriers.

- **3**. Take Control of Packaging Standards
**Too many orders** are arriving **broken** or **incomplete**. Olist should define and **enforce packaging quality guidelines** for all sellers — or centralize packaging in fulfillment hubs where possible. **Prevention** is better than **refund** policies.

- **4**. **Focus on Prevention**, Not Just Apologies
Don't just offer return/refund policies — customers would rather not have the problem at all. Olist must invest in **upstream logistics improvements** rather than relying on compensation to handle **service failures**.

---

### 🛒 Product Quality & Seller Oversight Recommendations

- **1**. **Reduce misleading listings through stricter product listing audits**. Olist should tighten the control over product descriptions, enforcing a clear, standardized format. Many customer complaints stem from **items that don’t match expectations**, which likely means sellers are overselling or misrepresenting their products. A small percentage of poor listings can have a **large negative impact** on customer trust.

- **2** **Seller quality audits** + **penalties for repeat issues**. Implement automatic seller scoring based on review trends, returns, and complaints. Sellers with frequent issues (e.g., inaccurate descriptions, low review averages) should face **visibility penalties**, reduced priority in listings, or even suspension if issues persist. This **shifts pressure to the seller** side and helps **protect the Olist brand**.

- **3** **Customer-visible seller trust indicators**. Add a simple “Trusted Seller” badge system or “Verified Product Quality” tag for listings with good **long-term performance**. Customers need reassurance that Olist has vetted what’s being sold, not just acting as a middleman. This **boosts perceived reliability** of the platform and lowers **buyer anxiety**.


### Final Thoughts

- This analysis showed how operational inefficiencies, especially in delivery and product oversight, directly impact customer satisfaction. Even with limited data, I extracted meaningful insights and actionable suggestions. There’s still room for deeper supply chain analysis and user experience audits — but this is a strong starting point.

### 📌 Clarification: 
*This analysis was built using available timestamps from the Olist dataset to recreate key funnel stages. Industry-standard metrics and average expectations for delivery timelines, such as typical approval-to-shipping and shipping-to-delivery windows, were used to define realistic thresholds. While exact SLA benchmarks from Olist were not available, the cleaning and logic applied here align with e-commerce best practices for identifying delays and operational issues.*


---
---

*This project was built through grit, trial and error, and a relentless drive to improve.
By Cristian Lovito — not a data expert, yet. But damn sure on the way.*

[GitHub](https://github.com/CristianLovito) · [LinkedIn](https://www.linkedin.com/in/cristian-lovito-06386521a/)
