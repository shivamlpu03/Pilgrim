create or replace table `shopify-pubsub-project.Customer_Experience.Daily_Shipment_tracking_report` as

WITH BASE_TRACK AS (
  SELECT
    bt.Normalized_Order_ID AS Order_ID,
    DATETIME(TIMESTAMP(bt.Created_at))                                                    AS Created_at,
    DATETIME(TIMESTAMP(bt.Pickup_Date), "Asia/Kolkata")                                   AS Pickup_Date,
    DATETIME(TIMESTAMP(bt.Latest_Timestamp), "Asia/Kolkata")                              AS Latest_Timestamp,
    bt.Latest_Remark,
    DATETIME(TIMESTAMP(bt.Delivery_Date), "Asia/Kolkata")                                 AS Delivery_Date,
    DATETIME(TIMESTAMP(bt.Expected_delivery_date_by_Courier_Partner), "Asia/Kolkata")     AS Expected_delivery_date_by_Courier_Partner,
    DATETIME(TIMESTAMP(bt.Expected_Date_Of_Delivery_Min), "Asia/Kolkata")                 AS Expected_Date_Of_Delivery_Min,
    DATETIME(TIMESTAMP(bt.Expected_Date_Of_Delivery_Max), "Asia/Kolkata")                 AS Expected_Date_Of_Delivery_Max,
    DATETIME(TIMESTAMP(bt.Out_For_Delivery_1st_Attempt), "Asia/Kolkata")                  AS Out_For_Delivery_1st_Attempt,
    DATETIME(TIMESTAMP(bt.Out_For_Delivery_2nd_Attempt), "Asia/Kolkata")                  AS Out_For_Delivery_2nd_Attempt,
    DATETIME(TIMESTAMP(bt.Out_For_Delivery_3rd_Attempt), "Asia/Kolkata")                  AS Out_For_Delivery_3rd_Attempt,
    DATETIME(TIMESTAMP(bt.Out_For_Delivery_4th_Attempt), "Asia/Kolkata")                  AS Out_For_Delivery_4th_Attempt,
    DATETIME(TIMESTAMP(bt.Out_For_Delivery_5th_Attempt), "Asia/Kolkata")                  AS Out_For_Delivery_5th_Attempt,
    bt.Out_For_Delivery_Attempts,
    bt.Reason_For_Last_Failed_Delivery,
    bt.Remark_Of_Last_Failed_Delivery,
    bt.Ingestion_Date,
    COALESCE(ac.AWB_COUNT, 0) AS AWB_COUNT,
    CASE
      WHEN COALESCE(ac.AWB_COUNT, 0) > 1 THEN 1
      ELSE 0
    END AS Multiple_AWB_Tag
  FROM (
    SELECT
      *,
      LPAD(Order_ID, 13, '0') AS Normalized_Order_ID
    FROM `shopify-pubsub-project.Data_Warehouse_ClickPost_Staging.Tracking`
    QUALIFY ROW_NUMBER() OVER (
      PARTITION BY LPAD(Order_ID, 13, '0')
      ORDER BY LATEST_TIMESTAMP DESC
    ) = 1
  ) bt
  LEFT JOIN (
    SELECT
      LPAD(ORDER_ID, 13, '0') AS Normalized_Order_ID,
      COUNT(DISTINCT AWB)     AS AWB_COUNT
    FROM `shopify-pubsub-project.Data_Warehouse_ClickPost_Staging.Tracking_Master`
    GROUP BY 1
  ) ac ON bt.Normalized_Order_ID = ac.Normalized_Order_ID
),


BASE_SHIP AS (
  SELECT
    LPAD(Order_ID, 13, '0')    AS Order_ID,
    Courier_Partner,
    Carrier_via_Aggregator,
    Clickpost_Unified_Status,
    STRING_AGG(DISTINCT AWB, ', ') AS AWB_List
  FROM (
    SELECT *
    FROM `shopify-pubsub-project.Data_Warehouse_ClickPost_Staging.Shipping`
    QUALIFY ROW_NUMBER() OVER (
      PARTITION BY LPAD(Order_ID, 13, '0')
      ORDER BY Ingestion_Date DESC
    ) = 1
  )
  GROUP BY 1, 2, 3, 4
),


BASE_OM AS (
  SELECT
    LPAD(m1.ORDER_ID, 13, '0') AS ORDER_ID,
    m1.Payment_Mode,
    m1.Drop_Pincode,
    m1.Order_Date,
    m2.state,
    m2.Main_city
  FROM `shopify-pubsub-project.Data_Warehouse_ClickPost_Staging.Order_Master` m1
  LEFT JOIN `shopify-pubsub-project.adhoc_data_asia.City_mapping` m2
    ON REGEXP_REPLACE(m1.Drop_Pincode, r'\.0$', '') = CAST(m2.pincode AS STRING)
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY LPAD(m1.ORDER_ID, 13, '0')
    ORDER BY m1.INGESTION_DATE DESC
  ) = 1
),


EASYCOM AS (
  SELECT
    LPAD(Order_Number, 13, '0') AS Order_Number,
    Order_Status
  FROM `shopify-pubsub-project.Data_Warehouse_Easyecom_Staging.Mini_Sales_report_B2C`
  WHERE MP_Name = 'Shopify'
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY LPAD(Order_Number, 13, '0')
    ORDER BY ee_extracted_at DESC
  ) = 1
),


FINAL AS (
  SELECT
    bt.Order_ID,
    bt.Created_at,
    bo.Order_Date,
    bt.Pickup_Date,
    bt.Latest_Timestamp,
    bt.Latest_Remark,
    bt.Delivery_Date,
    bt.Expected_delivery_date_by_Courier_Partner,
    bt.Expected_Date_Of_Delivery_Min,
    bt.Expected_Date_Of_Delivery_Max,
    bt.Out_For_Delivery_1st_Attempt,
    bt.Out_For_Delivery_2nd_Attempt,
    bt.Out_For_Delivery_3rd_Attempt,
    bt.Out_For_Delivery_4th_Attempt,
    bt.Out_For_Delivery_5th_Attempt,
    bt.Out_For_Delivery_Attempts,
    bt.Reason_For_Last_Failed_Delivery,
    bt.Remark_Of_Last_Failed_Delivery,
    bt.Ingestion_Date,
    bt.Multiple_AWB_Tag,

    -- from base_ship
    bs.Courier_Partner,
    bs.Carrier_via_Aggregator,
    bs.Clickpost_Unified_Status,
    bs.AWB_List,

    -- from base_om
    bo.Payment_Mode,
    bo.Drop_Pincode,
    bo.state,
    bo.Main_city,

    -- O2S / S2D / O2D (hours)
    CASE
      WHEN bo.Order_Date IS NOT NULL AND bt.Pickup_Date IS NOT NULL
      THEN ROUND(TIMESTAMP_DIFF(bt.Pickup_Date, DATETIME(TIMESTAMP(bo.Order_Date)), HOUR) / 24.0, 2)
    END AS O2S,

    CASE
      WHEN bt.Pickup_Date IS NOT NULL AND bt.Delivery_Date IS NOT NULL
      THEN ROUND(TIMESTAMP_DIFF(bt.Delivery_Date, bt.Pickup_Date, HOUR) / 24.0, 2)
    END AS S2D,

    CASE
      WHEN bo.Order_Date IS NOT NULL AND bt.Delivery_Date IS NOT NULL
      THEN ROUND(TIMESTAMP_DIFF(bt.Delivery_Date, DATETIME(TIMESTAMP(bo.Order_Date)), HOUR) / 24.0, 2)
    END AS O2D,

    -- O2S / S2D / O2D (days)
    CASE
      WHEN bo.Order_Date IS NOT NULL AND bt.Pickup_Date IS NOT NULL
      THEN DATE_DIFF(DATE(bt.Pickup_Date), DATE(bo.Order_Date), DAY)
    END AS O2S_d,

    CASE
      WHEN bt.Pickup_Date IS NOT NULL AND bt.Delivery_Date IS NOT NULL
      THEN DATE_DIFF(DATE(bt.Delivery_Date), DATE(bt.Pickup_Date), DAY)
    END AS S2D_d,

    CASE
      WHEN bo.Order_Date IS NOT NULL AND bt.Delivery_Date IS NOT NULL
      THEN DATE_DIFF(DATE(bt.Delivery_Date), DATE(bo.Order_Date), DAY)
    END AS O2D_d,

    -- TAT
    CASE
      WHEN bt.Delivery_Date IS NULL THEN 'others'
      WHEN bt.Expected_delivery_date_by_Courier_Partner IS NOT NULL THEN
        CASE
          WHEN bt.Out_For_Delivery_1st_Attempt IS NOT NULL
               AND DATE(bt.Out_For_Delivery_1st_Attempt) <= DATE(bt.Expected_delivery_date_by_Courier_Partner)
               AND DATE(bt.Delivery_Date) > DATE(bt.Expected_delivery_date_by_Courier_Partner)
          THEN 'after_tat_but_attempt'
          WHEN DATE(bt.Delivery_Date) = DATE(bt.Expected_delivery_date_by_Courier_Partner) THEN 'on_tat'
          WHEN DATE(bt.Delivery_Date) < DATE(bt.Expected_delivery_date_by_Courier_Partner) THEN 'before_tat'
          WHEN DATE(bt.Delivery_Date) > DATE(bt.Expected_delivery_date_by_Courier_Partner) THEN 'after_tat'
        END
      WHEN bt.Expected_Date_Of_Delivery_Max IS NOT NULL THEN
        CASE
          WHEN bt.Out_For_Delivery_1st_Attempt IS NOT NULL
               AND DATE(bt.Out_For_Delivery_1st_Attempt) <= DATE(bt.Expected_Date_Of_Delivery_Max)
               AND DATE(bt.Delivery_Date) > DATE(bt.Expected_Date_Of_Delivery_Max)
          THEN 'after_tat_but_attempt'
          WHEN DATE(bt.Delivery_Date) = DATE(bt.Expected_Date_Of_Delivery_Max) THEN 'on_tat'
          WHEN DATE(bt.Delivery_Date) < DATE(bt.Expected_Date_Of_Delivery_Max) THEN 'before_tat'
          WHEN DATE(bt.Delivery_Date) > DATE(bt.Expected_Date_Of_Delivery_Max) THEN 'after_tat'
        END
      WHEN bt.Expected_Date_Of_Delivery_Min IS NOT NULL THEN
        CASE
          WHEN bt.Out_For_Delivery_1st_Attempt IS NOT NULL
               AND DATE(bt.Out_For_Delivery_1st_Attempt) <= DATE(bt.Expected_Date_Of_Delivery_Min)
               AND DATE(bt.Delivery_Date) > DATE(bt.Expected_Date_Of_Delivery_Min)
          THEN 'after_tat_but_attempt'
          WHEN DATE(bt.Delivery_Date) = DATE(bt.Expected_Date_Of_Delivery_Min) THEN 'on_tat'
          WHEN DATE(bt.Delivery_Date) < DATE(bt.Expected_Date_Of_Delivery_Min) THEN 'before_tat'
          WHEN DATE(bt.Delivery_Date) > DATE(bt.Expected_Date_Of_Delivery_Min) THEN 'after_tat'
        END
      ELSE 'tat_not_assigned'
    END AS TAT,

    -- delivery_delay_category
    CASE
      WHEN bt.Out_For_Delivery_1st_Attempt IS NULL THEN 'not_attempted'
      WHEN bt.Expected_Date_Of_Delivery_Max IS NOT NULL THEN
        CASE
          WHEN DATE(bt.Out_For_Delivery_1st_Attempt) <= DATE(bt.Expected_Date_Of_Delivery_Max)
          THEN 'on_time_or_early'
          WHEN DATE_DIFF(DATE(bt.Out_For_Delivery_1st_Attempt), DATE(bt.Expected_Date_Of_Delivery_Max), DAY) = 1 THEN '1_day_late'
          WHEN DATE_DIFF(DATE(bt.Out_For_Delivery_1st_Attempt), DATE(bt.Expected_Date_Of_Delivery_Max), DAY) = 2 THEN '2_days_late'
          WHEN DATE_DIFF(DATE(bt.Out_For_Delivery_1st_Attempt), DATE(bt.Expected_Date_Of_Delivery_Max), DAY) = 3 THEN '3_days_late'
          WHEN DATE_DIFF(DATE(bt.Out_For_Delivery_1st_Attempt), DATE(bt.Expected_Date_Of_Delivery_Max), DAY) = 4 THEN '4_days_late'
          WHEN DATE_DIFF(DATE(bt.Out_For_Delivery_1st_Attempt), DATE(bt.Expected_Date_Of_Delivery_Max), DAY) > 4 THEN '4plus_days_late'
        END
      ELSE 'no_expected_date'
    END AS delivery_delay_category,

    -- Final_Status
    CASE
      WHEN bt.Pickup_Date IS NULL
           AND e.Order_Status IN ('Returned','Assigned','Cancelled','Printed','CANCELLED','Manifest Scanned')
      THEN 'Cancelled'
      WHEN bt.Pickup_Date IS NULL                                                                         THEN 'Not Picked'
      WHEN bs.Clickpost_Unified_Status IN ('Damaged','Lost')                                             THEN 'Damaged'
      WHEN bs.Clickpost_Unified_Status IN ('DestinationHubIn','InTransit','OriginCityIn','OriginCityOut') THEN 'InTransit'
      WHEN bs.Clickpost_Unified_Status IN ('PickupPending','PickupFailed')                               THEN 'Pickup failed'
      WHEN bs.Clickpost_Unified_Status LIKE 'RTO%'                                                       THEN 'RTO'
      ELSE bs.Clickpost_Unified_Status
    END AS Final_Status,

    -- Delivered_day_count
    CASE
      WHEN bt.Delivery_Date IS NOT NULL AND bo.Order_Date IS NOT NULL
      THEN DATE_DIFF(DATE(bt.Delivery_Date), DATE(bo.Order_Date), DAY)
    END AS Delivered_day_count,

    -- Alert_1_VS_2
    CASE
      WHEN bt.Out_For_Delivery_1st_Attempt IS NOT NULL
           AND bt.Out_For_Delivery_2nd_Attempt IS NOT NULL
           AND TIMESTAMP_DIFF(bt.Out_For_Delivery_2nd_Attempt, bt.Out_For_Delivery_1st_Attempt, HOUR) >= 48
      THEN 1
      ELSE 0
    END AS Alert_1_VS_2,

    -- Alert
    CASE
      WHEN EXTRACT(HOUR FROM bt.Created_at) < 14
           AND DATE(bt.Created_at) != DATE(bt.Pickup_Date)
      THEN 1
      WHEN EXTRACT(HOUR FROM bt.Created_at) >= 14
           AND DATE_DIFF(DATE(bt.Pickup_Date), DATE(bt.Created_at), DAY) > 1
      THEN 1
      ELSE 0
    END AS Alert,

    -- O2S Bucket
    CASE
      WHEN CASE
             WHEN bt.Pickup_Date IS NULL
                  AND e.Order_Status IN ('Returned','Assigned','Cancelled','Printed','CANCELLED','Manifest Scanned')
             THEN 'Cancelled'
             WHEN bt.Pickup_Date IS NULL THEN 'Not Picked'
             WHEN bs.Clickpost_Unified_Status LIKE 'RTO%' THEN 'RTO'
             ELSE bs.Clickpost_Unified_Status
           END = 'Not Picked' THEN 'Not Picked'
      WHEN CASE
             WHEN bt.Pickup_Date IS NULL
                  AND e.Order_Status IN ('Returned','Assigned','Cancelled','Printed','CANCELLED','Manifest Scanned')
             THEN 'Cancelled'
             WHEN bt.Pickup_Date IS NULL THEN 'Not Picked'
             WHEN bs.Clickpost_Unified_Status LIKE 'RTO%' THEN 'RTO'
             ELSE bs.Clickpost_Unified_Status
           END = 'Cancelled' THEN 'Cancelled'
      WHEN DATE_DIFF(DATE(bt.Pickup_Date), DATE(bo.Order_Date), DAY) IN (0, 1) THEN 'DAY 1'
      WHEN DATE_DIFF(DATE(bt.Pickup_Date), DATE(bo.Order_Date), DAY) = 2       THEN 'DAY 2'
      WHEN DATE_DIFF(DATE(bt.Pickup_Date), DATE(bo.Order_Date), DAY) = 3       THEN 'DAY 3'
      WHEN DATE_DIFF(DATE(bt.Pickup_Date), DATE(bo.Order_Date), DAY) = 4       THEN 'DAY 4'
      WHEN DATE_DIFF(DATE(bt.Pickup_Date), DATE(bo.Order_Date), DAY) = 5       THEN 'DAY 5'
      WHEN DATE_DIFF(DATE(bt.Pickup_Date), DATE(bo.Order_Date), DAY) = 6       THEN 'DAY 6'
      WHEN DATE_DIFF(DATE(bt.Pickup_Date), DATE(bo.Order_Date), DAY) = 7       THEN 'DAY 7'
      WHEN DATE_DIFF(DATE(bt.Pickup_Date), DATE(bo.Order_Date), DAY) = 8       THEN 'DAY 8'
      WHEN DATE_DIFF(DATE(bt.Pickup_Date), DATE(bo.Order_Date), DAY) = 9       THEN 'DAY 9'
      WHEN DATE_DIFF(DATE(bt.Pickup_Date), DATE(bo.Order_Date), DAY) >= 10     THEN 'DAY 10+'
      ELSE 'Cancelled'
    END AS O2S_Bucket,

    -- O2S Bucket Sort
    CASE
      WHEN CASE
             WHEN bt.Pickup_Date IS NULL
                  AND e.Order_Status IN ('Returned','Assigned','Cancelled','Printed','CANCELLED','Manifest Scanned')
             THEN 'Cancelled'
             WHEN bt.Pickup_Date IS NULL THEN 'Not Picked'
             WHEN bs.Clickpost_Unified_Status LIKE 'RTO%' THEN 'RTO'
             ELSE bs.Clickpost_Unified_Status
           END = 'Not Picked' THEN 98
      WHEN CASE
             WHEN bt.Pickup_Date IS NULL
                  AND e.Order_Status IN ('Returned','Assigned','Cancelled','Printed','CANCELLED','Manifest Scanned')
             THEN 'Cancelled'
             WHEN bt.Pickup_Date IS NULL THEN 'Not Picked'
             WHEN bs.Clickpost_Unified_Status LIKE 'RTO%' THEN 'RTO'
             ELSE bs.Clickpost_Unified_Status
           END = 'Cancelled' THEN 99
      WHEN DATE_DIFF(DATE(bt.Pickup_Date), DATE(bo.Order_Date), DAY) IN (0, 1) THEN 1
      WHEN DATE_DIFF(DATE(bt.Pickup_Date), DATE(bo.Order_Date), DAY) = 2       THEN 2
      WHEN DATE_DIFF(DATE(bt.Pickup_Date), DATE(bo.Order_Date), DAY) = 3       THEN 3
      WHEN DATE_DIFF(DATE(bt.Pickup_Date), DATE(bo.Order_Date), DAY) = 4       THEN 4
      WHEN DATE_DIFF(DATE(bt.Pickup_Date), DATE(bo.Order_Date), DAY) = 5       THEN 5
      WHEN DATE_DIFF(DATE(bt.Pickup_Date), DATE(bo.Order_Date), DAY) = 6       THEN 6
      WHEN DATE_DIFF(DATE(bt.Pickup_Date), DATE(bo.Order_Date), DAY) = 7       THEN 7
      WHEN DATE_DIFF(DATE(bt.Pickup_Date), DATE(bo.Order_Date), DAY) = 8       THEN 8
      WHEN DATE_DIFF(DATE(bt.Pickup_Date), DATE(bo.Order_Date), DAY) = 9       THEN 9
      WHEN DATE_DIFF(DATE(bt.Pickup_Date), DATE(bo.Order_Date), DAY) >= 10     THEN 10
      ELSE 99
    END AS O2S_Bucket_Sort

  FROM BASE_TRACK bt
  LEFT JOIN BASE_SHIP  bs ON bt.Order_ID = bs.Order_ID
  LEFT JOIN BASE_OM    bo ON bt.Order_ID = bo.ORDER_ID
  LEFT JOIN EASYCOM    e  ON bt.Order_ID = e.Order_Number
  WHERE DATE(bo.Order_Date) > '2024-12-31'
),


BASSE_ADDRESS AS (
  SELECT DISTINCT
    Order_ID,
    Pickup_City,
    REGEXP_REPLACE(Pickup_Pincode, r'\.0$', '') AS Pickup_Pincode
  FROM `shopify-pubsub-project.Data_Warehouse_ClickPost_Staging.Addresses`
  WHERE Pickup_Pincode IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY ORDER_ID ORDER BY Ingestion_Date DESC) = 1
),


BASE_WH AS (
  SELECT
    WH_NAME,
    PINCODE_PICKUP,
    City_pickup,
    State_pickup
  FROM `shopify-pubsub-project.Data_Warehouse_ClickPost_Staging.Wharehouse Zone Mapping Master`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY PINCODE_PICKUP ORDER BY WH_NAME) = 1
),


WAREHOUSE AS (
  SELECT
    ba.Order_ID,
    ba.Pickup_Pincode,
    bw.WH_NAME,
    bw.City_pickup,
    bw.State_pickup
  FROM BASSE_ADDRESS ba
  LEFT JOIN BASE_WH bw ON ba.Pickup_Pincode = bw.PINCODE_PICKUP
)


SELECT
  f.Order_ID        AS Order_id,        -- ← fixed casing for Looker
  f.Created_at,
  f.Order_Date,
  f.Pickup_Date,
  f.Latest_Timestamp,
  f.Latest_Remark,
  f.Delivery_Date,
  f.Expected_delivery_date_by_Courier_Partner,
  f.Expected_Date_Of_Delivery_Min,
  f.Expected_Date_Of_Delivery_Max,
  f.Out_For_Delivery_1st_Attempt,
  f.Out_For_Delivery_2nd_Attempt,
  f.Out_For_Delivery_3rd_Attempt,
  f.Out_For_Delivery_4th_Attempt,
  f.Out_For_Delivery_5th_Attempt,
  f.Out_For_Delivery_Attempts,
  f.Reason_For_Last_Failed_Delivery,
  f.Remark_Of_Last_Failed_Delivery,
  f.Ingestion_Date,
  f.Courier_Partner,
  f.Carrier_via_Aggregator,
  f.Clickpost_Unified_Status,
  f.AWB_List,
  f.Payment_Mode,
  f.Drop_Pincode,
  f.State,
  f.Main_City,
  f.O2S,
  f.S2D,
  f.O2D,
  f.O2S_d,
  f.S2D_d,
  f.O2D_d,
  f.TAT,
  f.delivery_delay_category,
  f.Final_Status    AS final_status,    -- ← fixed casing for Looker
  f.Delivered_day_count,
  f.Alert_1_VS_2,
  f.Alert,
  f.O2S_Bucket,
  f.O2S_Bucket_Sort,
  w.WH_NAME,
  w.Pickup_Pincode,
  w.City_pickup,
  w.State_pickup,
  CASE
    WHEN DATETIME_DIFF(DATETIME(CURRENT_TIMESTAMP()), f.Latest_Timestamp, HOUR) > 48
         AND f.Final_Status IN ('InTransit','FailedDelivery','OutForDelivery','ShipmentDelayed')
    THEN 1
    ELSE 0
  END AS SLA_breach,                    -- ← fixed casing for Looker
  f.Multiple_AWB_Tag

FROM FINAL f
LEFT JOIN WAREHOUSE w ON f.Order_ID = w.Order_ID
GROUP BY ALL
