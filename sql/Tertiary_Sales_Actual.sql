CREATE OR REPLACE TABLE `shopify-pubsub-project.Product_SKU_Mapping.Tertiary_Master_Sales_Actual` AS 
WITH CTE1 AS(
SELECT  
'PILGRIM' as brand,
'Marketplace' as source_channel,
'FK Minutes' AS Channel, 
'Q-Com' as Com,
DATE(order_date) AS Order_date,  
product_id, 
Parent_SKU, 
Master_SKU, 
MP.Product_Title, 
Master_Title, 
MRP_OG,
Main_Category,
Sub_Category,
"null" as Region,
SUM(SAFE_CAST(gmv AS FLOAT64)) AS GMV, 
SUM(SAFE_CAST(gross_sales AS FLOAT64)) AS Gross_Sales, 
SUM(SAFE_CAST(units_sold AS INT64)) AS Units_Sold
FROM shopify-pubsub-project.Marketplaces_Staging_Dataset.fk_minutes fk 
LEFT JOIN `shopify-pubsub-project.Product_SKU_Mapping.Master_SKU_mapping` MP 
ON fk.Product_id = MP.Variant_ID
WHERE LOWER(MP.Channel) IN ('flipkart')
GROUP BY ALL 

UNION ALL

SELECT 
'PILGRIM' as brand,
'Marketplace' as source_channel,
'Big Basket' AS Channel,
'Q-Com' as Com,
DATE(date) AS date,
cast(source_sku_id as string) as SKU, 
Parent_SKU, 
Master_SKU, 
MP.Product_Title, 
Master_Title, 
MRP_OG,
Main_Category,
Sub_Category, 
"null" as Region,
SUM(cast(total_quantity*total_mrp as float64)) AS GMV,
SUM(cast(total_sales as float64)) AS Gross_sales, 
SUM(cast(total_quantity as float64)) AS Units_Sold
FROM `shopify-pubsub-project.Marketplaces_Staging_Dataset.BIGBASKET` i
LEFT JOIN `shopify-pubsub-project.Product_SKU_Mapping.Master_SKU_mapping` MP 
ON cast(i.source_sku_id as string) = MP.Variant_ID WHERE i.brand_name='Pilgrim'
GROUP BY ALL 

UNION ALL
        
SELECT 
'PILGRIM' as brand,
'Marketplace' as source_channel,
'Zepto' AS Channel, 
'Q-Com' as Com,
DATE(date) AS date,
product as SKU, 
Parent_SKU, 
Master_SKU, 
MP.Product_Title, 
Master_Title, 
MRP_OG,
Main_Category,
Sub_Category, 
"null" as Region,
SUM(COALESCE(IF(IS_NAN(SAFE_CAST(off_mrp AS FLOAT64)), NULL, SAFE_CAST(off_mrp AS FLOAT64)), 0)) AS GMV,
SUM(COALESCE(IF(IS_NAN(SAFE_CAST(off_sp AS FLOAT64)), NULL, SAFE_CAST(off_sp AS FLOAT64)), 0)) AS Gross_sales,
SUM(COALESCE(IF(IS_NAN(SAFE_CAST(off_qty AS FLOAT64)), NULL, SAFE_CAST(off_qty AS FLOAT64)), 0)) AS Units_Sold
FROM `shopify-pubsub-project.GC_Zepto_Staging.Zepto_Sales` i
LEFT JOIN `shopify-pubsub-project.Product_SKU_Mapping.Master_SKU_mapping` MP 
ON i.product = MP.Variant_ID WHERE brand='Pilgrim'
GROUP BY ALL

UNION ALL 

SELECT 
'PILGRIM' as brand,
'Marketplace' as source_channel,
'Instamart' AS Channel, 
'Q-Com' as Com,
DATE(date) AS date,
product as SKU, 
Parent_SKU, 
Master_SKU, 
MP.Product_Title, 
Master_Title, 
MRP_OG,
COALESCE(Main_Category, 'Not filled') AS Main_Category,
Sub_Category, 
"null" as Region,
SUM(COALESCE(IF(IS_NAN(SAFE_CAST(off_mrp AS FLOAT64)), NULL, SAFE_CAST(off_mrp AS FLOAT64)), 0)) AS GMV,
SUM(COALESCE(IF(IS_NAN(SAFE_CAST(off_sp AS FLOAT64)), NULL, SAFE_CAST(off_sp AS FLOAT64)), 0)) AS Gross_sales,
SUM(COALESCE(IF(IS_NAN(SAFE_CAST(off_qty AS FLOAT64)), NULL, SAFE_CAST(off_qty AS FLOAT64)), 0)) AS Units_Sold
FROM `shopify-pubsub-project.GC_Instamart_Staging.Instamart_Sales` i
LEFT JOIN `shopify-pubsub-project.Product_SKU_Mapping.Master_SKU_mapping` MP 
ON i.product = MP.Variant_ID WHERE LOWER(brand)='pilgrim'
GROUP BY ALL 

UNION ALL

SELECT 
'PILGRIM' as brand,
'Marketplace' as source_channel,
'Blinkit' AS Channel, 
'Q-Com' as Com,
DATE(date) AS date,
product as SKU, 
Parent_SKU, 
Master_SKU, 
MP.Product_Title, 
Master_Title, 
MRP_OG,
Main_Category,
Sub_Category, 
"null" as Region,
SUM(COALESCE(IF(IS_NAN(SAFE_CAST(off_mrp AS FLOAT64)), NULL, SAFE_CAST(off_mrp AS FLOAT64)), 0)) AS GMV,
SUM(COALESCE(IF(IS_NAN(SAFE_CAST(off_sp AS FLOAT64)), NULL, SAFE_CAST(off_sp AS FLOAT64)), 0)) AS Gross_sales,
SUM(COALESCE(IF(IS_NAN(SAFE_CAST(off_qty AS FLOAT64)), NULL, SAFE_CAST(off_qty AS FLOAT64)), 0)) AS Units_Sold
FROM `shopify-pubsub-project.GC_Blinkit_Staging.Blinkit_Sales` i
LEFT JOIN `shopify-pubsub-project.Product_SKU_Mapping.Master_SKU_mapping` MP 
ON i.product = MP.Variant_ID WHERE brand='Pilgrim'
GROUP BY ALL 

UNION ALL

SELECT 
'PILGRIM' as brand,
  'Marketplace' AS source_channel,
  'First Cry'   AS Channel,
  'E-Com'       AS Com,
  day           AS order_date,
  product_id, Parent_SKU, Master_SKU, 
  MP.Product_Title, Master_Title, 
  MRP_OG, Main_Category, Sub_Category, "null" as Region,
  SUM(gmv / DATE_DIFF(DATE_ADD(DATE_TRUNC(DATE(fc.date), MONTH), INTERVAL 1 MONTH), DATE_TRUNC(DATE(fc.date), MONTH), DAY)) AS GMV,
  SUM(gross_sales / DATE_DIFF(DATE_ADD(DATE_TRUNC(DATE(fc.date), MONTH), INTERVAL 1 MONTH), DATE_TRUNC(DATE(fc.date), MONTH), DAY)) AS Gross_Sales,
  SUM(CAST(units_sold AS INT64) / DATE_DIFF(DATE_ADD(DATE_TRUNC(DATE(fc.date), MONTH), INTERVAL 1 MONTH), DATE_TRUNC(DATE(fc.date), MONTH), DAY)) AS Units_Sold
FROM `shopify-pubsub-project.Marketplaces_Staging_Dataset.FIRST_CRY_SALES` fc 
CROSS JOIN UNNEST(GENERATE_DATE_ARRAY(DATE_TRUNC(DATE(fc.date), MONTH), DATE_SUB(DATE_ADD(DATE_TRUNC(DATE(fc.date), MONTH), INTERVAL 1 MONTH), INTERVAL 1 DAY))) AS day
LEFT JOIN `shopify-pubsub-project.Product_SKU_Mapping.Master_SKU_mapping` MP ON fc.Product_id = MP.Variant_ID
GROUP BY ALL 

UNION ALL 

SELECT  
'PILGRIM' as brand,
'Marketplace' as source_channel,
'Smytten' AS Channel, 
'E-Com' as Com,
DATE(date) AS Order_date, 
product_id, 
Parent_SKU, 
Master_SKU, 
MP.Product_Title, 
Master_Title, 
MRP_OG,
Main_Category,
Sub_Category,
"null" as Region,
SUM(gmv) AS GMV, 
SUM(gross_sales) AS Gross_Sales, 
SUM(CAST(units_sold AS INT64)) AS Units_Sold
FROM shopify-pubsub-project.Marketplaces_Staging_Dataset.Smytten s
LEFT JOIN shopify-pubsub-project.Product_SKU_Mapping.Master_SKU_mapping MP 
ON s.Product_id = MP.Variant_ID
WHERE date is not null
GROUP BY ALL 

UNION ALL 

SELECT 
'PILGRIM' as brand,
'Marketplace' as source_channel,
'Flipkart' AS Channel, 
'E-Com' as Com,
DATE(order_date) AS order_date, 
product_id, 
Parent_SKU, 
Master_SKU, 
MP.Product_Title, 
Master_Title, 
MRP_OG,
Main_Category,
Sub_Category,
"null" as Region,
sum(mrp_og*gross_units) AS GMV, 
SUM(gmv) AS Gross_Sales, 
SUM(CAST(gross_units AS INT64)) AS Units_Sold
FROM shopify-pubsub-project.Data_Warehouse_flipkart_seller_staging.earn_more_report fl 
LEFT JOIN shopify-pubsub-project.Product_SKU_Mapping.Master_SKU_mapping MP 
ON fl.Product_id = MP.Variant_ID 
WHERE fl.brand = 'Pilgrim'
GROUP BY ALL 

UNION ALL 

SELECT 
'PILGRIM' as brand,
'Marketplace' as source_channel,
'Myntra' AS Channel,
'E-Com' as Com,
DATE(order_date) AS Order_date, 
style_id, 
Parent_SKU, 
Master_SKU, 
MP.Product_Title, 
Master_Title, 
MRP_OG,
Main_Category,
Sub_Category,
"null" as Region,
SUM(item_mrp) AS GMV, 
SUM(item_mrp - vendor_funding) AS Gross_Sales, 
SUM(CAST(qty AS INT64)) AS Units_Sold
FROM shopify-pubsub-project.Marketplaces_Staging_Dataset.MYNTRA_MTD m 
LEFT JOIN shopify-pubsub-project.Product_SKU_Mapping.Master_SKU_mapping MP 
ON m.style_id = MP.Variant_ID
GROUP BY ALL 

UNION ALL

SELECT 
'PILGRIM' as brand,
'Marketplace' as source_channel,
'Purplle' AS Channel, 
'E-Com' as Com,
DATE(date) AS date, 
product_id, 
Parent_SKU, 
Master_SKU, 
MP.Product_Title, 
Master_Title, 
MRP_OG,
Main_Category,
Sub_Category,
"null" as Region,
sum(gmv) AS GMV, 
SUM(Gross_Sale) AS Gross_Sales, 
SUM(CAST(units_sold AS INT64)) AS Units_Sold
FROM shopify-pubsub-project.Marketplaces_Staging_Dataset.Purplle pu 
LEFT JOIN shopify-pubsub-project.Product_SKU_Mapping.Master_SKU_mapping MP 
ON pu.product_id = MP.Variant_ID 
GROUP BY ALL

UNION ALL   

SELECT 
'PILGRIM' as brand,
'Marketplace' as source_channel,
'Nykaa' AS Channel, 
'E-Com' as Com,
DATE(date) AS date,
`SKU CODE`, 
Parent_SKU, 
Master_SKU, 
MP.Product_Title, 
Master_Title, 
MRP_OG,
Main_Category,
Sub_Category, 
"null" as Region,
SUM(MRP) AS GMV,
SUM(`Display Price`) AS Gross_sales, 
SUM(CAST(`Total Qty` AS INT64)) AS Units_Sold
FROM shopify-pubsub-project.Marketplaces_Staging_Dataset.Nykaa NK 
LEFT JOIN `shopify-pubsub-project.Product_SKU_Mapping.Master_SKU_mapping` MP 
  ON NK.`SKU CODE` = MP.Variant_ID 
  AND MP.CHANNEL = 'Nykaa' WHERE nk.brand='Pilgrim'
GROUP BY ALL 

UNION ALL

(
WITH hector_recent AS (
  SELECT
  'PILGRIM' as brand,
    'Marketplace'               AS source_channel,
    'Amazon'                    AS Channel,
    'E-Com'                     AS Com,
    DATE(oi.purchase_date)      AS Order_date,
    oi.ASIN                     AS ASIN,
    MP.Parent_SKU,
    MP.Master_SKU,
    MP.Product_Title,
    MP.Master_Title,
    MP.MRP_OG,
    MP.Main_Category,
    MP.Sub_Category,
    "null" as Region,
    SUM(MP.MRP_OG * SAFE_CAST(oi.quantity AS FLOAT64))  AS GMV,
    SUM(SAFE_CAST(oi.item_price AS FLOAT64))             AS Gross_sales,
    SUM(SAFE_CAST(oi.quantity AS INT64))                 AS Units_Sold
  FROM `shopify-pubsub-project.Data_Warehouse_Amazon_Seller_Staging.Amazon_Orders_Report` oi
  LEFT JOIN shopify-pubsub-project.Product_SKU_Mapping.Master_SKU_mapping MP
    ON oi.asin = MP.Variant_ID AND MP.CHANNEL = 'Amazon'
  WHERE Order_status IN ('Shipping','Shipped - Picked Up','Shipped - Delivered to Buyer','Shipped - Out for Delivery','Pending','Pending - Waiting for Pick Up','Shipped') 
    AND LOWER(product_name) NOT LIKE '%phd%'
  GROUP BY ALL
),

rk_world_recent AS (
  SELECT
  'PILGRIM' as brand,
    'Marketplace'               AS source_channel,
    'Amazon'                    AS Channel,
    'E-Com'                     AS Com,
    DATE(oi.startDate)          AS Order_date,
    oi.ASIN,
    MP.Parent_SKU,
    MP.Master_SKU,
    MP.Product_Title,
    MP.Master_Title,
    MP.MRP_OG,
    MP.Main_Category,
    MP.Sub_Category,
    "null" as Region,
    SUM(MP.MRP_Rev * oi.orderedUnits)              AS GMV,
    SUM(oi.orderedUnits * MP.MRP_Rev) * (1-0.23)  AS Gross_sales,
    SUM(CAST(oi.orderedUnits AS INT64))            AS Units_Sold
  FROM shopify-pubsub-project.Data_Warehouse_Amazon_Seller_Staging.RK_WORLD_sales_report_new oi
  LEFT JOIN shopify-pubsub-project.Product_SKU_Mapping.Master_SKU_mapping MP
    ON oi.ASIN = MP.Variant_ID AND MP.CHANNEL = 'Amazon'
  GROUP BY ALL
)

SELECT * FROM hector_recent 
UNION ALL 
SELECT * FROM rk_world_recent
)

UNION ALL 

SELECT 
'PILGRIM' as brand,
'Marketplace' as source_channel,
'Tira' AS Channel, 
'E-Com' as Com,
DATE(R.date) AS order_date, 
R.product_id, 
Parent_SKU, 
Master_SKU, 
MP.Product_Title, 
Master_Title, 
MRP_OG,
Main_Category,
Sub_Category,
"null" as Region,
sum(GMV) as GMV, 
sum(case
    when R.date >= '2026-01-01' then R.gross_sale
    when t.discount is null then R.GMV
    else R.GMV * (1 - t.discount)
end) as Gross_sales,
SUM(CAST(Units_sold AS INT64)) AS Units_sold
FROM shopify-pubsub-project.Marketplaces_Staging_Dataset.RELIANCE R 
LEFT JOIN shopify-pubsub-project.Dashboard_category_pnl.Test_DISC_RELIANCE t
    ON t.date=R.date AND t.item_id=R.product_id AND t.customer_order_source=R.customer_order_source 
LEFT JOIN shopify-pubsub-project.Product_SKU_Mapping.Master_SKU_mapping MP 
ON R.product_id = MP.Variant_ID 
GROUP BY ALL

UNION ALL 

SELECT 
'PILGRIM' as brand,
'Marketplace' as source_channel,
'Meesho' AS Channel,
'E-Com' as Com,
DATE(Order_Date) AS Order_date, 
SKU, 
Parent_SKU, 
Master_SKU, 
MP.Product_Title, 
Master_Title,  
MRP_OG,
Main_Category,
Sub_Category, 
"null" as Region,
SUM(MRP_OG*Quantity) AS GMV,
SUM(gross_sale) AS Gross_sales, 
SUM(CAST(Quantity AS INT64)) AS Units_Sold
FROM `shopify-pubsub-project.Marketplaces_Staging_Dataset.meesho_staging` oi 
LEFT JOIN `shopify-pubsub-project.Product_SKU_Mapping.Master_SKU_mapping` MP 
  ON oi.sku = MP.Variant_ID AND MP.CHANNEL = 'Meesho' 
GROUP BY ALL  
        
UNION ALL

SELECT 
'PILGRIM' as brand,
  'D2C' AS source_channel,
  'Shopify' AS Channel, 
  'Shopify' as Com,
  DATE(Order_created_at) AS Order_date, 
  CAST(NULL AS STRING) AS product_id,  -- ← fixed
  MP.Parent_SKU, 
  MP.Master_SKU, 
  MP.Product_Title, 
  MP.Master_Title, 
  null as MRP_OG,
  COALESCE(MP.Main_Category, 'Not filled') AS Main_Category,
  MP.Sub_Category,
  "null" as Region,
  SUM(item_GMV) AS GMV, 
  SUM(item_gross_revenue) AS Gross_Sales, 
  SUM(CAST(item_quantity AS INT64)) AS Units_Sold
FROM shopify-pubsub-project.Data_Warehouse_Shopify_Staging.Order_items_master sh 
LEFT JOIN shopify-pubsub-project.Product_SKU_Mapping.Master_SKU_mapping MP 
  ON sh.item_variant_id = MP.Variant_ID
WHERE is_cancelled = 0
GROUP BY ALL  

UNION ALL

-- GT_BA
SELECT 
'PILGRIM' as brand,
  'Offline' AS source_channel,
  'GT_BA'   AS Channel, 
  'GT_BA'   AS Com,
  DATE(order_date) AS order_date, 
  CAST(NULL AS STRING) AS product_id,  -- ← fixed
  mp.SKU    AS Parent_SKU,
  CAST(NULL AS STRING) AS Master_SKU,  -- ← fixed
  mp.Product_Name AS Product_Title, 
  mp.Master_Title, 
  SAFE_CAST(mp.MRP AS FLOAT64) AS MRP_OG,
  mp.Main_Category,
  mp.Sub_Category, 
  "null" AS Region,  
  SUM(Sale_Value)              AS GMV,
  SUM(Sale_Value) * 0.74       AS Gross_Sales,
  SUM(CAST(Quantity AS INT64)) AS Units_Sold
FROM `shopify-pubsub-project.Data_WareHouse_Massist_Staging.GT_MT_BA_SKU_Sales` oi
LEFT JOIN (
  SELECT DISTINCT SKU, Product_Name, Master_Title, Main_Category, Sub_Category, MRP
  FROM `shopify-pubsub-project.Product_SKU_Mapping.Offline_New_Mapping`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY SKU ORDER BY SKU) = 1
) mp ON oi.VSKUCode = mp.SKU
WHERE Sub_Type IN ('GT-BA', 'GT-RBA') 
  AND oi.Client_Type = 'Retailer-BA'
GROUP BY ALL

UNION ALL

-- MT-BA
(
WITH sale3_data AS (
  SELECT
    day                                          AS order_date,
    gt.SKU_Code                                  AS product_id,
    gt.month,
    SUM(gt.revenue / DATE_DIFF(DATE_ADD(DATE_TRUNC(gt.month, MONTH), INTERVAL 1 MONTH), DATE_TRUNC(gt.month, MONTH), DAY))       AS GMV,
    SUM(gt.revenue / DATE_DIFF(DATE_ADD(DATE_TRUNC(gt.month, MONTH), INTERVAL 1 MONTH), DATE_TRUNC(gt.month, MONTH), DAY))*0.60  AS Gross_Sales,
    SUM(CAST(gt.units AS INT64) / DATE_DIFF(DATE_ADD(DATE_TRUNC(gt.month, MONTH), INTERVAL 1 MONTH), DATE_TRUNC(gt.month, MONTH), DAY)) AS Units_Sold
  FROM (
    SELECT EAN, SKU_Code, CAST(month AS DATE) AS month, units, revenue
    FROM `shopify-pubsub-project.Offline_Offtakes_SOB_Sales.MT_BA_Sale3_New`
    UNPIVOT (
      (units, revenue) FOR month IN (
        (Jan_25_Units, Jan_25_Revenue)  AS '2025-01-01',
        (Feb_25_Units, Feb_25_Revenue)  AS '2025-02-01',
        (Mar_25_Units, Mar_25_Revenue)  AS '2025-03-01',
        (Apr_25_Units, Apr_25_Revenue)  AS '2025-04-01',
        (May_25_Units, May_25_Revenue)  AS '2025-05-01',
        (Jun_25_Units, Jun_25_Revenue)  AS '2025-06-01',
        (Jul_25_Units, Jul_25_Revenue)  AS '2025-07-01',
        (Aug_25_Units, Aug_25_Revenue)  AS '2025-08-01',
        (Sep_25_Units, Sep_25_Revenue)  AS '2025-09-01',
        (Oct_25_Units, Oct_25_Revenue)  AS '2025-10-01',
        (Nov_25_Units, Nov_25_Revenue)  AS '2025-11-01',
        (Dec_25_Units, Dec_25_Revenue)  AS '2025-12-01',
        (Jan_26_Units, Jan_26_Revenue)  AS '2026-01-01',
        (Feb_26_Units, Feb_26_Revenue)  AS '2026-02-01',
        (Mar_26_Units, Mar_26_Revenue)  AS '2026-03-01',
        (Apr_26_Units, Apr_26_Revenue)  AS '2026-04-01'
      )
    )
  ) gt
  CROSS JOIN UNNEST(GENERATE_DATE_ARRAY(DATE_TRUNC(gt.month, MONTH), DATE_SUB(DATE_ADD(DATE_TRUNC(gt.month, MONTH), INTERVAL 1 MONTH), INTERVAL 1 DAY))) AS day
  GROUP BY ALL
),

main_data AS (
  SELECT
    DATE(Date)                    AS order_date,
    CAST(SKU AS STRING)           AS product_id,
    DATE_TRUNC(DATE(Date), MONTH) AS month,
    GMV_MRP_QTY_                  AS GMV,
    Gross_Sales                   AS Gross_Sales,
    QTY                           AS Units_Sold
  FROM `shopify-pubsub-project.Offline_Offtakes_SOB_Sales.MT_BA_Sheet_Main`
  WHERE DATE(Date) >= '2026-05-01'
),

combined AS (
  SELECT * FROM sale3_data
  UNION ALL
  SELECT * FROM main_data
)

SELECT
'PILGRIM' as brand,
  'Offline'            AS source_channel,
  'MT_BA'              AS Channel,
  'MT_BA'              AS Com,
  c.order_date,
  CAST(NULL AS STRING) AS product_id,  -- ← fixed
  mp.SKU               AS Parent_SKU,
  CAST(NULL AS STRING) AS Master_SKU,  -- ← fixed
  mp.Product_Name      AS Product_Title,
  mp.Master_Title,
  SAFE_CAST(mp.MRP AS FLOAT64) AS MRP_OG,
  mp.Main_Category,
  mp.Sub_Category,
  "null"               AS Region,
  SUM(c.GMV)           AS GMV,
  SUM(c.Gross_Sales)   AS Gross_Sales,
  SUM(c.Units_Sold)    AS Units_Sold
FROM combined c
LEFT JOIN (
  SELECT DISTINCT SKU, Product_Name, Master_Title, Main_Category, Sub_Category, MRP
  FROM `shopify-pubsub-project.Product_SKU_Mapping.Offline_New_Mapping`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY SKU ORDER BY SKU) = 1
) mp ON c.product_id = mp.SKU
GROUP BY ALL
)

UNION ALL

-- GT_NBA
SELECT 
'PILGRIM' as brand,
  'Offline'            AS source_channel,
  'GT_NBA'             AS Channel,
  'GT_NBA'             AS Com,
  DATE(gt.order_date)  AS order_date,
  CAST(NULL AS STRING) AS product_id,  -- ← fixed
  mp.SKU               AS Parent_SKU,
  CAST(NULL AS STRING) AS Master_SKU,  -- ← fixed
  mp.Product_Name      AS Product_Title,
  mp.Master_Title,
  SAFE_CAST(mp.MRP AS FLOAT64) AS MRP_OG,
  mp.Main_Category,
  mp.Sub_Category,
  "null"               AS Region,
  SUM(TotalOrderValueMRP)               AS GMV,
  SUM(TotalOrderValueMRP) * 0.664       AS Gross_Sales,
  SUM(CAST(TotalQuantitySale AS INT64)) AS Units_Sold
FROM `shopify-pubsub-project.Offline_Offtakes_SOB_Sales.GT_NON_BA_SALES` gt
LEFT JOIN (
  SELECT DISTINCT CAST(Product_Id AS STRING) AS Product_Id, VSKU_Code
  FROM `shopify-pubsub-project.Product_SKU_Mapping.Product_Listing_Offline`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY Product_Id ORDER BY Product_Id) = 1
) pl ON REGEXP_REPLACE(CAST(gt.Product_Id AS STRING), r"\.0$", "") = pl.Product_Id
LEFT JOIN (
  SELECT DISTINCT SKU, Product_Name, Master_Title, Main_Category, Sub_Category, MRP
  FROM `shopify-pubsub-project.Product_SKU_Mapping.Offline_New_Mapping`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY SKU ORDER BY SKU) = 1
) mp ON pl.VSKU_Code = mp.SKU
WHERE gt.Client_Type = 'Retailer-NBA'
GROUP BY ALL

UNION ALL

-- MT_CORE
SELECT
'PILGRIM' as brand,
  'Offline'            AS source_channel,
  'MT_CORE'            AS Channel,
  'MT_CORE'            AS Com,
  DATE(t.Invoice_Date) AS order_date,
  CAST(NULL AS STRING) AS product_id,  -- ← fixed
  mp.SKU               AS Parent_SKU,
  CAST(NULL AS STRING) AS Master_SKU,  -- ← fixed
  mp.Product_Name      AS Product_Title,
  mp.Master_Title,
  SAFE_CAST(t.Component_SKU_MRP AS FLOAT64) AS MRP_OG,
  mp.Main_Category,
  mp.Sub_Category,
  "null"               AS Region,
  SUM(t.Component_SKU_MRP * t.Item_Quantity)         AS GMV,
  SUM(t.Component_SKU_MRP * t.Item_Quantity) * 0.444 AS Gross_Sales,
  SUM(t.Item_Quantity)                               AS Units_Sold
FROM `shopify-pubsub-project.Offline_Offtakes_SOB_Sales.PO_Tracker_MT_Core_BQ` po
LEFT JOIN `shopify-pubsub-project.Data_Warehouse_Easyecom_Staging.Tax_report_new` t
  ON TRIM(po.PO_NO) = TRIM(t.MP_Ref_No)
LEFT JOIN (
  SELECT DISTINCT SKU, Product_Name, Master_Title, Main_Category, Sub_Category, MRP
  FROM `shopify-pubsub-project.Product_SKU_Mapping.Offline_New_Mapping`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY SKU ORDER BY SKU) = 1
) mp ON REPLACE(TRIM(t.Component_SKU), '`', '') = mp.SKU
WHERE po.Channel IN ('MT-Core', 'Mt-Core', 'Mt-core')
GROUP BY ALL

UNION ALL

-- Salon
SELECT 
'PILGRIM' as brand,
  'Offline' AS source_channel,
  'SALON'   AS Channel, 
  'SALON'   AS Com,
  DATE(PARSE_TIMESTAMP('%d/%m/%Y %I:%M:%S %p', Order_Date)) AS order_date, 
  REGEXP_REPLACE(CAST(Product_Id AS STRING), r"\.0$", "") AS product_id, 
  Parent_SKU, 
  Master_SKU, 
  MP.Product_Title, 
  Master_Title, 
  MRP_OG,
  Main_Category,
  Sub_Category,
  EmpZone AS Region,
  SUM(SAFE_CAST(GrossAmount AS INT64)) AS GMV, 
  SUM(SAFE_CAST(Order_Amt AS INT64))   AS Gross_Sales, 
  SUM(SAFE_CAST(Quantity AS INT64))    AS Units_Sold
FROM (
  SELECT *
  FROM `shopify-pubsub-project.Data_WareHouse_Massist_Staging.Order_DMS_Sale_Details`
  WHERE Client_Type IN ('Salon')
    AND LOWER(client_name) NOT LIKE '%dummy%'
    AND LOWER(OrderType) NOT LIKE '%credit%'
  QUALIFY
    COUNTIF(LOWER(OrderType) NOT LIKE '%credit%') OVER (PARTITION BY Order_Id) > 0
) t
LEFT JOIN (
  SELECT *
  FROM `shopify-pubsub-project.Product_SKU_Mapping.Master_SKU_mapping`
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY Variant_ID 
    ORDER BY IF(Channel = 'Salon', 0, 1)
  ) = 1
) mp
  ON REGEXP_REPLACE(CAST(t.Product_Id AS STRING), r"\.0$", "") = mp.Variant_ID 
GROUP BY ALL

UNION ALL

-- EBO
SELECT 
'PILGRIM' as brand,
  'Offline' AS source_channel,
  'EBO'     AS Channel, 
  'EBO'     AS Com,
  DATE(order_date) AS order_date, 
  REGEXP_REPLACE(CAST(Product_Id AS STRING), r"\.0$", "") AS product_id, 
  Parent_SKU, 
  Master_SKU, 
  MP.Product_Title, 
  Master_Title, 
  MRP_OG,
  Main_Category,
  Sub_Category,
  "null" AS Region,
  SUM(Sale_Value)        AS GMV, 
  SUM(Sale_Value) * 0.65 AS Gross_Sales, 
  SUM(CAST(Quantity AS INT64)) AS Units_Sold
FROM `shopify-pubsub-project.Data_WareHouse_Massist_Staging.EBO`
LEFT JOIN `shopify-pubsub-project.Product_SKU_Mapping.Master_SKU_mapping` mp 
  ON REGEXP_REPLACE(CAST(Product_Id AS STRING), r"\.0$", "") = mp.Variant_ID 
  AND Division = mp.Channel
WHERE Division = 'EBO'
GROUP BY ALL

UNION ALL

-- Export
SELECT 
'PILGRIM' as brand,
  'Offline' AS source_channel,
  'Export'  AS Channel,
  'Export'  AS Com,
  day       AS order_date,
  REGEXP_REPLACE(CAST(e.Product_Id AS STRING), r"\.0$", "") AS product_id,
  Parent_SKU, mp.Master_SKU, MP.Product_Title,
  mp.Master_Title,
  SAFE_CAST(MRP AS FLOAT64) AS MRP_OG,
  COALESCE(Main_Category, 'Not filled') AS Main_Category,
  Sub_Category, "null" AS Region,
  SUM(SAFE_CAST(mrp AS FLOAT64) * SAFE_CAST(e.Quantity AS FLOAT64) / DATE_DIFF(DATE_ADD(DATE_TRUNC(DATE(e.order_date), MONTH), INTERVAL 1 MONTH), DATE_TRUNC(DATE(e.order_date), MONTH), DAY)) AS GMV,
  SUM(SAFE_CAST(e.Sale_Value AS FLOAT64) / DATE_DIFF(DATE_ADD(DATE_TRUNC(DATE(e.order_date), MONTH), INTERVAL 1 MONTH), DATE_TRUNC(DATE(e.order_date), MONTH), DAY)) AS Gross_Sales,
  SUM(SAFE_CAST(e.Quantity AS FLOAT64) / DATE_DIFF(DATE_ADD(DATE_TRUNC(DATE(e.order_date), MONTH), INTERVAL 1 MONTH), DATE_TRUNC(DATE(e.order_date), MONTH), DAY)) AS Units_Sold
FROM `shopify-pubsub-project.Data_WareHouse_Massist_Staging.Export` e
CROSS JOIN UNNEST(GENERATE_DATE_ARRAY(DATE_TRUNC(DATE(e.order_date), MONTH), DATE_SUB(DATE_ADD(DATE_TRUNC(DATE(e.order_date), MONTH), INTERVAL 1 MONTH), INTERVAL 1 DAY))) AS day
LEFT JOIN (
  SELECT *
  FROM `shopify-pubsub-project.Product_SKU_Mapping.Offline_SKU_Mapping`
  WHERE LOWER(division) LIKE '%export%'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY Product_Id ORDER BY Product_Id) = 1
) mp ON REGEXP_REPLACE(CAST(e.Product_Id AS STRING), r"\.0$", "") = mp.Product_Id
GROUP BY ALL


union all
(
WITH 
AMZ_CTE AS (
    SELECT  
        'PHD' as Brand,
        'Marketplace'                                           AS source_channel,
        'Amazon'                                               AS Channel,
        'E-Com'                                                AS Com,
        DATE(C1.purchase_date)                                 AS Order_date, 
        Asin                                                   AS Asin, 
        MP.Sku                                                 AS Parent_SKU, 
        MP.Main_SKU                                            AS Master_SKU, 
        MP.Product_Name                                        AS Product_Title,
        MP.Product_Name                                        AS Master_title,
        mrp,
        CASE WHEN LOWER(Category) = 'skincare' THEN 'Skin Care' ELSE Category END AS Category,
        'null'                                                 AS sub_Category,
        "null" AS Region,
        SUM(MP.MRP * SAFE_CAST(C1.quantity AS FLOAT64))       AS GMV,
        SUM(SAFE_CAST(C1.item_price AS FLOAT64))              AS Gross_Sales,
        SUM(SAFE_CAST(C1.quantity AS INT64))                   AS Units_Sold
    FROM phd-database-475011.Marketplace_Dataset.Amazon_ALL_Orders_Report C1 
    LEFT JOIN `phd-database-475011.Marketplace_Dataset.MP_Mapping` MP 
        ON C1.asin = MP.Identifier 
    WHERE MP.Channel = 'Amazon'
    AND Order_status IN ('Shipping','Shipped - Picked Up','Shipped - Delivered to Buyer','Shipped - Out for Delivery','Pending','Pending - Waiting for Pick Up','Shipped') 
    GROUP BY ALL
), 

Flipkart_CTE AS (
    SELECT  
        'PHD' as Brand,
        'Marketplace'                                          AS source_channel,
        'Flipkart'                                             AS Channel,
        'E-Com'                                                AS Com,
        DATE(C1.order_date)                                    AS Order_date, 
        C1.product_id                                          AS Product_id, 
        MP.Sku                                                 AS Parent_SKU, 
        MP.Main_SKU                                            AS Master_SKU, 
        MP.Product_Name                                        AS Product_Title,
        MP.Product_Name                                        AS Master_title,
        mrp,
        CASE WHEN LOWER(mp.Category) = 'skincare' THEN 'Skin Care' ELSE mp.Category END AS Category,
        'null'                                                 AS sub_Category,
        "null" AS Region,
        SUM(mrp * gross_units)                                 AS GMV, 
        SUM(gmv)                                               AS Gross_Sales, 
        SUM(CAST(gross_units AS INT64))                        AS Units_Sold
    FROM phd-database-475011.Marketplace_Dataset.Flipkart_Sales C1 
    LEFT JOIN phd-database-475011.Marketplace_Dataset.MP_Mapping MP 
        ON C1.Product_id = MP.Identifier 
    WHERE MP.Channel = 'Flipkart'
    GROUP BY ALL
), 

Nykaa_CTE AS (
    SELECT 
        'PHD' as Brand, 
        'Marketplace'                                          AS source_channel,
        'Nykaa'                                                AS Channel,
        'E-Com'                                                AS Com,
        DATE(C1.date)                                          AS Order_date, 
        C1.`SKU Code`                                          AS Product_id, 
        MP.Sku                                                 AS Parent_SKU, 
        MP.Main_SKU                                            AS Master_SKU, 
        MP.Product_Name                                        AS Product_Title,
        MP.Product_Name                                        AS Master_title,
        mp.mrp,
        CASE WHEN LOWER(mp.Category) = 'skincare' THEN 'Skin Care' ELSE mp.Category END AS Category,
        'null'                                                 AS sub_Category,
        "null" AS Region,
        SUM(C1.MRP)                                            AS GMV,
        SUM(C1.`Display Price`)                                AS Gross_Sales, 
        SUM(CAST(C1.`Total Qty` AS INT64))                     AS Units_Sold
    FROM phd-database-475011.Marketplace_Dataset.Nykaa_Sales C1 
    LEFT JOIN phd-database-475011.Marketplace_Dataset.MP_Mapping MP 
        ON C1.`SKU Code` = MP.Identifier 
    WHERE MP.Channel = 'Nykaa'
    AND LOWER(C1.Brand) = 'pilgrim'
    GROUP BY ALL
), 

Myntra_CTE AS (
    SELECT  
        'PHD' as Brand, 
        'Marketplace'                                          AS source_channel,
        'Myntra'                                               AS Channel,
        'E-Com'                                                AS Com,
        DATE(C1.order_date)                                    AS Order_date, 
        C1.style_id                                            AS Product_id, 
        MP.Sku                                                 AS Parent_SKU, 
        MP.Main_SKU                                            AS Master_SKU, 
        MP.Product_Name                                        AS Product_Title,
        MP.Product_Name                                        AS Master_title,
        mrp,
        CASE WHEN LOWER(mp.Category) = 'skincare' THEN 'Skin Care' ELSE mp.Category END AS Category,
        'null'                                                 AS sub_Category,
        "null" AS Region,
        SUM(C1.item_mrp)                                       AS GMV, 
        SUM(C1.item_mrp - C1.vendor_funding)                   AS Gross_Sales, 
        SUM(CAST(C1.qty AS INT64))                             AS Units_Sold
    FROM phd-database-475011.Marketplace_Dataset.Myntra_Sales C1 
    LEFT JOIN phd-database-475011.Marketplace_Dataset.MP_Mapping MP 
        ON C1.style_id = MP.Identifier 
    WHERE MP.Channel = 'Myntra'
    GROUP BY ALL
), 

Blinkit_CTE AS (
    SELECT  
        'PHD' as Brand, 
        'Marketplace'                                          AS source_channel,
        'Blinkit'                                              AS Channel,
        'Q-Com'                                                AS Com,
        DATE(C1.date)                                          AS Order_date, 
        C1.item_id                                             AS Product_id, 
        MP.Sku                                                 AS Parent_SKU, 
        MP.Main_SKU                                            AS Master_SKU, 
        MP.Product_Name                                        AS Product_Title,
        MP.Product_Name                                        AS Master_title,
        mrp,
        CASE WHEN LOWER(mp.Category) = 'skincare' THEN 'Skin Care' ELSE mp.Category END AS Category,
        'null'                                                 AS sub_Category,
        "null" AS Region,
        SUM(CAST(C1.mrp_gmv AS FLOAT64))                      AS GMV,
        SUM(CAST(C1.mrp_gmv AS FLOAT64) - CAST(C1.total_brand_fund AS FLOAT64))  AS Gross_Sales,
        SUM(CAST(C1.qty_sold AS FLOAT64))                      AS Units_Sold
    FROM phd-database-475011.Marketplace_Dataset.Blinkit_Sales C1 
    LEFT JOIN phd-database-475011.Marketplace_Dataset.MP_Mapping MP 
        ON C1.item_id = MP.Identifier 
    WHERE MP.Channel = 'Blinkit'
    GROUP BY ALL
), 

Purplle_CTE AS (
    SELECT  
        'PHD' as Brand, 
        'Marketplace'                                          AS source_channel,
        'Purplle'                                              AS Channel,
        'E-Com'                                                AS Com,
        DATE(C1.order_date)                                    AS Order_date, 
        C1.sku                                                 AS Product_id, 
        MP.Sku                                                 AS Parent_SKU, 
        MP.Main_SKU                                            AS Master_SKU, 
        MP.Product_Name                                        AS Product_Title,
        MP.Product_Name                                        AS Master_title,
        mp.mrp,
        CASE WHEN LOWER(mp.Category) = 'skincare' THEN 'Skin Care' ELSE mp.Category END AS Category,
        'null'                                                 AS sub_Category,
        "null" AS Region,
        SUM(C1.mrp)                                            AS GMV, 
        SUM(C1.Gross_Sales)                                    AS Gross_Sales, 
        NULL                                                   AS Units_Sold
    FROM phd-database-475011.Marketplace_Dataset.Purplle_Sales C1 
    LEFT JOIN phd-database-475011.Marketplace_Dataset.MP_Mapping MP 
        ON C1.sku = MP.Identifier 
    WHERE MP.Channel = 'Purplle'
    GROUP BY ALL
),

Instamart_CTE AS (
    SELECT  
        'PHD' as Brand, 
        'Marketplace'                                          AS source_channel,
        'Instamart'                                            AS Channel,
        'Q-Com'                                                AS Com,
        DATE(C1.order_date)                                    AS Order_date, 
        CAST(C1.item_code AS STRING)                           AS Product_id, 
        MP.Sku                                                 AS Parent_SKU, 
        MP.Main_SKU                                            AS Master_SKU, 
        MP.Product_Name                                        AS Product_Title,
        MP.Product_Name                                        AS Master_title,
        mrp,
        CASE WHEN LOWER(mp.Category) = 'skincare' THEN 'Skin Care' ELSE mp.Category END AS Category,
        'null'                                                 AS sub_Category,
        "null" AS Region,
        SUM(C1.gmv)                                            AS GMV, 
        SUM(C1.gmv - C1.discount_spend)                        AS Gross_Sales, 
        SUM(C1.units_sold)                                     AS Units_Sold
    FROM phd-database-475011.Marketplace_Dataset.Instamart_Sales C1 
    LEFT JOIN phd-database-475011.Marketplace_Dataset.MP_Mapping MP 
        ON CAST(C1.item_code AS STRING) = MP.Identifier 
    WHERE MP.Channel = 'Instamart'
    GROUP BY ALL
),
d2c_cte as(
  SELECT 
  'PHD' as brand,
  'D2C' AS source_channel,
  'Shopify' AS Channel, 
  'Shopify' as Com,
  DATE(Order_created_at) AS Order_date, 
  CAST(NULL AS STRING) AS product_id,
  MP.Parent_SKU, 
  MP.Master_SKU, 
  MP.Product_Title, 
  MP.Master_Title, 
  null as MRP_OG,
  CASE WHEN LOWER(COALESCE(MP.Main_Category, 'Not filled')) = 'skincare' THEN 'Skin Care' ELSE COALESCE(MP.Main_Category, 'Not filled') END AS Main_Category,
  MP.Sub_Category,
  "null" as Region,
  SUM(item_GMV) AS GMV, 
  SUM(item_gross_revenue) AS Gross_Sales, 
  SUM(CAST(item_quantity AS INT64)) AS Units_Sold
FROM phd-database-475011.Data_Warehouse_Shopify_Staging.Order_items_master sh 
LEFT JOIN `phd-database-475011.Data_Warehouse_Shopify_Staging.PHD_SKU_Mapping` MP 
  ON (sh.item_variant_id) = cast(MP.Variant_ID as String)
WHERE is_cancelled = 0
GROUP BY ALL  
),

UNION_CTE AS(
SELECT * FROM AMZ_CTE
UNION ALL 
SELECT * FROM Flipkart_CTE
UNION ALL
SELECT * FROM Nykaa_CTE
UNION ALL
SELECT * FROM Myntra_CTE
UNION ALL
SELECT * FROM Blinkit_CTE
UNION ALL
SELECT * FROM Purplle_CTE
UNION ALL
SELECT * FROM Instamart_CTE
union all 
select* from d2c_cte

) 
SELECT * FROM UNION_CTE
)




),

final_cte AS (
  SELECT 
    Brand,
    Com,
    source_channel,
    Channel,
    Order_date,
    Parent_sku,
    Product_Title,
    Master_Title,
    Main_Category,
    Sub_Category,
    Region,
    COALESCE(SAFE_CAST(SUM(GMV) AS FLOAT64), 0)         AS GMV,
    COALESCE(SAFE_CAST(SUM(Gross_Sales) AS FLOAT64), 0)  AS Gross_Sales,
    COALESCE(SAFE_CAST(SUM(Units_Sold) AS FLOAT64), 0)   AS Units_Sold
  FROM cte1 
  -- WHERE LOWER(Product_title) NOT LIKE '%phd%'
  GROUP BY ALL
)

SELECT a.*
FROM final_cte a 
WHERE a.order_date < CURRENT_DATE();
