MERGE INTO `shopify-pubsub-project.Data_Warehouse_flipkart_seller_staging.earn_more_report` AS target
USING (
  WITH ranked_data AS (
    SELECT *,
      ROW_NUMBER() OVER (
        PARTITION BY 
          product_id, sku_id, category, brand, vertical, order_date, 
          fulfillment_type, location_id
        ORDER BY runid DESC
      ) AS row_rank
    FROM `shopify-pubsub-project.pilgrim_bi_flipkart_seller.earn_more_report`
    WHERE order_date > (
      SELECT IFNULL(MAX(order_date), DATE('2000-01-01'))
      FROM `shopify-pubsub-project.Data_Warehouse_flipkart_seller_staging.earn_more_report`
    )
  )
  SELECT DISTINCT 
    product_id, sku_id, category, brand, vertical, order_date, 
    fulfillment_type, location_id, gross_units, gmv, 
    cancellation_units, cancellation_amount, 
    return_units, return_amount, 
    final_sale_units, final_sale_amount
  FROM ranked_data
  WHERE row_rank = 1
) AS source

ON FALSE  -- Always inserts, no match condition
WHEN NOT MATCHED THEN 
  INSERT (
    product_id,
    sku_id,
    category,
    brand,
    vertical,
    order_date,
    fulfillment_type,
    location_id,
    gross_units,
    gmv,
    cancellation_units,
    cancellation_amount,
    return_units,
    return_amount,
    final_sale_units,
    final_sale_amount
  )
  VALUES (
    source.product_id,
    source.sku_id,
    source.category,
    source.brand,
    source.vertical,
    source.order_date,
    source.fulfillment_type,
    source.location_id,
    source.gross_units,
    source.gmv,
    source.cancellation_units,
    source.cancellation_amount,
    source.return_units,
    source.return_amount,
    source.final_sale_units,
    source.final_sale_amount
  );
