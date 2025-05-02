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
