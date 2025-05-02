WITH cleaned_orders_step1 AS (
    SELECT 
        *
    FROM olist_orders
    WHERE 
        order_status IN ('delivered', 'shipped')  -- ✅ Only orders that could reach the delivery stage

        -- 🧹 Drop rows with missing timestamps
        AND order_approved_at IS NOT NULL 

        -- ⏱️ Keep only orders with approval delays ≤ 20 days
        AND EXTRACT(EPOCH FROM (order_approved_at - order_purchase_timestamp)) / 86400 <= 20 
)

SELECT * 
FROM cleaned_orders_step1



