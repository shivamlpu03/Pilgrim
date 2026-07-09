CREATE OR REPLACE TABLE `shopify-pubsub-project.Data_Warehouse_flipkart_seller_staging.earn_more_report` AS
WITH ranked_data AS (
  SELECT *,
    ROW_NUMBER() OVER (
      PARTITION BY 
        product_id, sku_id, category, brand, vertical, order_date, 
        fulfillment_type, location_id
      ORDER BY runid
    ) AS row_rank
  FROM `shopify-pubsub-project.pilgrim_bi_flipkart_seller.earn_more_report`
  -- WHERE DATE_TRUNC(order_date, MONTH) = '2025-01-01'
)

SELECT product_id, sku_id, category, brand, vertical, order_date, 
        fulfillment_type, location_id, gross_units, gmv, 
        cancellation_units, cancellation_amount, 
        return_units, return_amount, 
        final_sale_units, final_sale_amount
FROM ranked_data
WHERE row_rank = 1;
