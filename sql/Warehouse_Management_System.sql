-- Daily Shipment Tracking Report - Easyecom (Fixed + Shopify1 routed to phd-database-475011 ClickPost tables)
CREATE OR REPLACE TABLE `shopify-pubsub-project.Supply_Chain.Daily_Shipment_tracking_report_Easyecom` AS
WITH
  Easyecom AS (
    SELECT
      Client_Location,
      -- FIX: Use LPAD to pad to exactly 13 chars (was CONCAT('000',...) which over/under-pads)
      LPAD(order_number, 13, '0') AS order_number,
      -- Keep the raw/unpadded order_number too -- needed to join Shopify1 against
      -- phd-database-475011, where Order_ID is stored unpadded (e.g. '206070')
      order_number AS order_number_raw,
      Order_Status,
      Shipping_Status,
      Import_Date,
      Order_Date,
      Assigned_At,
      Cancelled_At,
      Delivered_At,
      Handover_At,
      Shipping_Zip_Code,
      Payment_Mode,
      Shipping_City,
      Shipping_State,
      Expected_Delivery_Date,
      AWB_No AS Tracking_Number,
      Courier AS Courier_Name,
      Courier_Aggregator_Name,
      QC_Confirmed_At,
      Confirmed_At,
      Printed_At,
      Manifested_At,
      Invoice_Date,
      TAT,
      Batch_ID,
      MP_Name,
      manifest_id,
      suborder_quantity
    FROM `shopify-pubsub-project.Data_Warehouse_Easyecom_Staging.Mini_Sales_report_B2C`
    WHERE
      MP_Name IN ('Shopify', 'Shopify1')
      AND DATE_TRUNC(DATE(order_date), MONTH) >= '2025-01-01'
    QUALIFY ROW_NUMBER() OVER (PARTITION BY Order_Number, Tracking_Number ORDER BY ee_extracted_at DESC) = 1
  ),

  Return_cn AS (
    SELECT Order_Number, Creditnote_Number
    FROM `shopify-pubsub-project.Data_Warehouse_Easyecom_Staging.Returns_report`
    QUALIFY ROW_NUMBER() OVER (PARTITION BY Order_Number ORDER BY ee_extracted_at DESC) = 1
  ),

  Easyecom_cn AS (
    SELECT
      e.Client_Location,
      e.Order_Number,
      e.order_number_raw,
      e.Order_Status,
      e.Shipping_Status,
      e.Import_Date,
      e.Order_Date,
      e.Assigned_At,
      e.Cancelled_At,
      e.Delivered_At,
      e.Handover_At,
      e.Shipping_Zip_Code,
      e.Payment_Mode,
      e.Shipping_City,
      e.Shipping_State,
      e.Expected_Delivery_Date,
      e.Tracking_Number,
      e.Courier_Name,
      e.Courier_Aggregator_Name,
      e.QC_Confirmed_At,
      e.Confirmed_At,
      e.Printed_At,
      e.Manifested_At,
      e.Invoice_Date,
      e.TAT,
      r.Creditnote_Number,
      e.Batch_ID,
      e.MP_Name,
      e.manifest_id,
      e.suborder_quantity
    FROM Easyecom e
    LEFT JOIN Return_cn r
      -- FIX: Cleaner REGEXP_REPLACE to strip any leading backtick from returns order number
      ON e.Order_Number = REGEXP_REPLACE(r.Order_Number, r'^\`', '')
  ),

  -- Tracking data from ClickPost
  -- Shopify  -> shopify-pubsub-project.Data_Warehouse_ClickPost_Staging  (Order_ID padded to 13 chars)
  -- Shopify1 -> phd-database-475011.Data_Warehouse_ClickPost_Staging     (Order_ID stored unpadded)
  base_track_shopify AS (
    SELECT DISTINCT
      Order_ID,
      DATETIME(TIMESTAMP(Created_at)) AS Created_at,
      DATETIME(TIMESTAMP(Pickup_Date), 'Asia/Kolkata') AS Pickup_Date,
      DATETIME(TIMESTAMP(Delivery_Date), 'Asia/Kolkata') AS Delivery_Date,
      DATETIME(TIMESTAMP(Expected_delivery_date_by_Courier_Partner), 'Asia/Kolkata') AS Expected_delivery_date_by_Courier_Partner,
      DATETIME(TIMESTAMP(Expected_Date_Of_Delivery_Min), 'Asia/Kolkata') AS Expected_Date_Of_Delivery_Min,
      DATETIME(TIMESTAMP(Expected_Date_Of_Delivery_Max), 'Asia/Kolkata') AS Expected_Date_Of_Delivery_Max,
      DATETIME(TIMESTAMP(Out_For_Delivery_1st_Attempt), 'Asia/Kolkata') AS Out_For_Delivery_1st_Attempt,
      DATETIME(TIMESTAMP(Out_For_Delivery_2nd_Attempt), 'Asia/Kolkata') AS Out_For_Delivery_2nd_Attempt,
      DATETIME(TIMESTAMP(Out_For_Delivery_3rd_Attempt), 'Asia/Kolkata') AS Out_For_Delivery_3rd_Attempt,
      DATETIME(TIMESTAMP(Out_For_Delivery_4th_Attempt), 'Asia/Kolkata') AS Out_For_Delivery_4th_Attempt,
      DATETIME(TIMESTAMP(Out_For_Delivery_5th_Attempt), 'Asia/Kolkata') AS Out_For_Delivery_5th_Attempt,
      Out_For_Delivery_Attempts,
      Reason_For_Last_Failed_Delivery,
      AWB
    FROM `shopify-pubsub-project.Data_Warehouse_ClickPost_Staging.Tracking_Master`
    QUALIFY ROW_NUMBER() OVER (PARTITION BY Order_ID, AWB ORDER BY ingestion_date DESC) = 1
  ),

  base_track_shopify1 AS (
    SELECT DISTINCT
      Order_ID,
      DATETIME(TIMESTAMP(Created_at)) AS Created_at,
      DATETIME(TIMESTAMP(Pickup_Date), 'Asia/Kolkata') AS Pickup_Date,
      DATETIME(TIMESTAMP(Delivery_Date), 'Asia/Kolkata') AS Delivery_Date,
      DATETIME(TIMESTAMP(Expected_delivery_date_by_Courier_Partner), 'Asia/Kolkata') AS Expected_delivery_date_by_Courier_Partner,
      DATETIME(TIMESTAMP(Expected_Date_Of_Delivery_Min), 'Asia/Kolkata') AS Expected_Date_Of_Delivery_Min,
      DATETIME(TIMESTAMP(Expected_Date_Of_Delivery_Max), 'Asia/Kolkata') AS Expected_Date_Of_Delivery_Max,
      DATETIME(TIMESTAMP(Out_For_Delivery_1st_Attempt), 'Asia/Kolkata') AS Out_For_Delivery_1st_Attempt,
      DATETIME(TIMESTAMP(Out_For_Delivery_2nd_Attempt), 'Asia/Kolkata') AS Out_For_Delivery_2nd_Attempt,
      DATETIME(TIMESTAMP(Out_For_Delivery_3rd_Attempt), 'Asia/Kolkata') AS Out_For_Delivery_3rd_Attempt,
      DATETIME(TIMESTAMP(Out_For_Delivery_4th_Attempt), 'Asia/Kolkata') AS Out_For_Delivery_4th_Attempt,
      DATETIME(TIMESTAMP(Out_For_Delivery_5th_Attempt), 'Asia/Kolkata') AS Out_For_Delivery_5th_Attempt,
      Out_For_Delivery_Attempts,
      Reason_For_Last_Failed_Delivery,
      AWB
    FROM `phd-database-475011.Data_Warehouse_ClickPost_Staging.Tracking_Master`
    QUALIFY ROW_NUMBER() OVER (PARTITION BY Order_ID, AWB ORDER BY ingestion_date DESC) = 1
  ),

  clickpost_shopify AS (
    SELECT
      -- FIX: Use LPAD to pad to exactly 13 chars (consistent with Easyecom CTE)
      LPAD(Order_ID, 13, '0') AS Order_ID,
      Courier_Partner,
      Carrier_via_Aggregator,
      Clickpost_Unified_Status,
      AWB
    FROM (
      SELECT *
      FROM `shopify-pubsub-project.Data_Warehouse_ClickPost_Staging.Shipping`
      QUALIFY ROW_NUMBER() OVER (PARTITION BY Order_ID, AWB ORDER BY Ingestion_Date DESC) = 1
    )
  ),

  clickpost_shopify1 AS (
    SELECT
      -- No padding: Order_ID in this table is already stored unpadded (e.g. '206070')
      Order_ID,
      Courier_Partner,
      Carrier_via_Aggregator,
      Clickpost_Unified_Status,
      AWB
    FROM (
      SELECT *
      FROM `phd-database-475011.Data_Warehouse_ClickPost_Staging.Shipping`
      QUALIFY ROW_NUMBER() OVER (PARTITION BY Order_ID, AWB ORDER BY Ingestion_Date DESC) = 1
    )
  ),

  -- FIX: Also apply LPAD to base_track_shopify Order_ID so it joins correctly against the
  -- padded Shopify order_number. Shopify1's tracking table keeps its raw Order_ID, since it
  -- joins against the unpadded order_number_raw column.
  base_track_padded AS (
    SELECT
      LPAD(Order_ID, 13, '0') AS Order_ID,
      Created_at,
      Pickup_Date,
      Delivery_Date,
      Expected_delivery_date_by_Courier_Partner,
      Expected_Date_Of_Delivery_Min,
      Expected_Date_Of_Delivery_Max,
      Out_For_Delivery_1st_Attempt,
      Out_For_Delivery_2nd_Attempt,
      Out_For_Delivery_3rd_Attempt,
      Out_For_Delivery_4th_Attempt,
      Out_For_Delivery_5th_Attempt,
      Out_For_Delivery_Attempts,
      Reason_For_Last_Failed_Delivery,
      AWB
    FROM base_track_shopify

    UNION ALL

    SELECT
      Order_ID,
      Created_at,
      Pickup_Date,
      Delivery_Date,
      Expected_delivery_date_by_Courier_Partner,
      Expected_Date_Of_Delivery_Min,
      Expected_Date_Of_Delivery_Max,
      Out_For_Delivery_1st_Attempt,
      Out_For_Delivery_2nd_Attempt,
      Out_For_Delivery_3rd_Attempt,
      Out_For_Delivery_4th_Attempt,
      Out_For_Delivery_5th_Attempt,
      Out_For_Delivery_Attempts,
      Reason_For_Last_Failed_Delivery,
      AWB
    FROM base_track_shopify1
  ),

  clickpost AS (
    SELECT Order_ID, Courier_Partner, Carrier_via_Aggregator, Clickpost_Unified_Status, AWB
    FROM clickpost_shopify

    UNION ALL

    SELECT Order_ID, Courier_Partner, Carrier_via_Aggregator, Clickpost_Unified_Status, AWB
    FROM clickpost_shopify1
  ),

  Final AS (
    SELECT
      e.*,
      c.Courier_Partner,
      c.Carrier_via_Aggregator,
      c.Clickpost_Unified_Status,
      bt.Created_at,
      bt.Pickup_Date,
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
      bt.Reason_For_Last_Failed_Delivery
    FROM Easyecom_cn e
    -- Shopify joins on the LPAD-13 order_number; Shopify1 joins on the raw/unpadded
    -- order_number_raw, since phd-database-475011's Order_ID is stored unpadded.
    LEFT JOIN clickpost c
      ON (
           (e.MP_Name = 'Shopify'  AND e.order_number     = c.order_id) OR
           (e.MP_Name = 'Shopify1' AND e.order_number_raw = c.order_id)
         )
      AND e.Tracking_Number = c.AWB
    LEFT JOIN base_track_padded bt
      ON (
           (e.MP_Name = 'Shopify'  AND e.order_number     = bt.order_id) OR
           (e.MP_Name = 'Shopify1' AND e.order_number_raw = bt.order_id)
         )
      AND e.Tracking_Number = bt.awb
  )

SELECT
  *,

  -- Mismatch RTO
  CASE
    WHEN Pickup_Date IS NULL
         AND LOWER(Order_Status) IN ('returned', 'assigned', 'cancelled', 'printed', 'manifest scanned')
         AND Clickpost_Unified_Status IS NULL THEN 1
    WHEN LOWER(Order_Status) IN ('returned', 'cancelled')
         AND Clickpost_Unified_Status IS NOT NULL
         AND LOWER(Clickpost_Unified_Status) NOT LIKE 'rto%'
         AND LOWER(Clickpost_Unified_Status) != 'cancelled' THEN 1
    ELSE 0
  END AS mismatch_rto,

  -- Warehouse
  Client_Location AS Warehouse,

  -- O2S (Order to Ship in decimal days)
  CASE
    WHEN Created_at IS NOT NULL AND Pickup_Date IS NOT NULL
    THEN ROUND(TIMESTAMP_DIFF(Pickup_Date, Created_at, HOUR) / 24.0, 2)
    ELSE NULL
  END AS O2S,

  -- S2D (Ship to Delivery in decimal days)
  CASE
    WHEN Pickup_Date IS NOT NULL AND Delivery_Date IS NOT NULL
    THEN ROUND(TIMESTAMP_DIFF(Delivery_Date, Pickup_Date, HOUR) / 24.0, 2)
    ELSE NULL
  END AS S2D,

  -- O2D (Order to Delivery in decimal days)
  CASE
    WHEN Created_at IS NOT NULL AND Delivery_Date IS NOT NULL
    THEN ROUND(TIMESTAMP_DIFF(Delivery_Date, Created_at, HOUR) / 24.0, 2)
    ELSE NULL
  END AS O2D,

  -- O2S_d (Order to Ship in whole days)
  CASE
    WHEN Created_at IS NOT NULL AND Pickup_Date IS NOT NULL
    THEN DATE_DIFF(DATE(Pickup_Date), DATE(Created_at), DAY)
    ELSE NULL
  END AS O2S_d,

  -- S2D_d (Ship to Delivery in whole days)
  CASE
    WHEN Pickup_Date IS NOT NULL AND Delivery_Date IS NOT NULL
    THEN DATE_DIFF(DATE(Delivery_Date), DATE(Pickup_Date), DAY)
    ELSE NULL
  END AS S2D_d,

  -- O2D_d (Order to Delivery in whole days)
  CASE
    WHEN Created_at IS NOT NULL AND Delivery_Date IS NOT NULL
    THEN DATE_DIFF(DATE(Delivery_Date), DATE(Created_at), DAY)
    ELSE NULL
  END AS O2D_d,

  -- Alert for pickup delay
  CASE
    WHEN Created_at IS NOT NULL AND Pickup_Date IS NOT NULL THEN
      CASE
        WHEN EXTRACT(HOUR FROM Created_at) < 14
             AND DATE(Created_at) != DATE(Pickup_Date) THEN 1
        WHEN EXTRACT(HOUR FROM Created_at) >= 14
             AND DATE_DIFF(DATE(Pickup_Date), DATE(Created_at), DAY) > 1 THEN 1
        ELSE 0
      END
    ELSE 0
  END AS Alert,

  -- Final Status
  CASE
    WHEN Clickpost_Unified_Status = 'Delivered' OR Shipping_Status = 'Delivered' THEN 'Delivered'
    WHEN LOWER(Clickpost_Unified_Status) LIKE 'rto%' OR LOWER(order_status) = 'returned' THEN 'RTO'
    WHEN LOWER(Order_Status) = 'cancelled' THEN 'Cancelled'
    WHEN LOWER(order_Status) LIKE '%lost%'
         OR LOWER(Clickpost_Unified_Status) LIKE 'damaged%'
         OR LOWER(Clickpost_Unified_Status) LIKE '%lost%'
         OR LOWER(Shipping_Status) LIKE '%lost%' THEN 'Lost'
    WHEN LOWER(Clickpost_Unified_Status) IN ('intransit', 'outfordelivery', 'pickedup', 'destinationhubin', 'faileddelivery') THEN 'Pending'
    WHEN LOWER(Order_Status) IN ('confirmed', 'manifest scanned', 'pending', 'printed', 'ready to dispatch', 'assigned') THEN 'Pending for Packing'
    WHEN Order_Status = 'Shipped'
         AND Shipping_Status = 'Shipment Created'
         AND Clickpost_Unified_Status IN ('Awb Registered', 'OrderPlaced', 'OutForPickup', 'PickupFailed', 'PickupPending') THEN 'Questionable'
    WHEN Order_Status = 'Shipped' AND Shipping_Status = 'Picked Up' THEN 'Pending'
    ELSE CONCAT(Order_Status, '-', Shipping_Status, '-', IFNULL(Clickpost_Unified_Status, 'NULL'))
  END AS final_status

FROM Final
