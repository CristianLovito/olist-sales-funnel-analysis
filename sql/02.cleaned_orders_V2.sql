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

