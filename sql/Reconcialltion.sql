CREATE OR REPLACE TABLE shopify-pubsub-project.Data_Warehouse_Shopify_Staging.reconciliation AS

WITH Shopify_oi AS (
  SELECT
    order_name,
    order_item_id,
    order_created_at,
    Order_fulfillment_status,
    Order_financial_status,
    is_cancelled,
    ROUND(item_gross_revenue, 0) AS Shopify_sale_value
  FROM `shopify-pubsub-project.Data_Warehouse_Shopify_Staging.Order_items_master`
  WHERE DATE_TRUNC(DATE(order_created_at), MONTH) >= DATE '2025-04-01'
),

-- ✅ FIX: single source only (Mini_Sales_report_B2C). The old UNION ALL with
-- Tax_report_new had no upper date bound on the tax branch, so every order
-- from Apr 2026 onward existed in BOTH branches → each Shopify item joined
-- to 2 EE rows → row fanout → order-level Shopify & EasyEcom values doubled.
Easyecom_tr AS (
  SELECT
    Invoice_Date,
    Order_Number,
    Suborder_No,
    DATETIME(Order_Date, 'Asia/Kolkata') AS Order_Date_IST,
    Order_Status,
    Client_Location AS Warehouse,
    EE_Invoice_No,
    -- ✅ clean AWB at source (Mini Sales has real AWB_No; old 'null' literal removed)
    REPLACE(AWB_No, '`', '') AS AWB,
    CASE
      WHEN AWB_No = 'nan' OR AWB_No IS NULL OR TRIM(REPLACE(AWB_No, '`', '')) = '' THEN NULL
      ELSE REPLACE(AWB_No, '`', '')
    END AS tracking_number,
    ROUND(SUM(
      CASE
        WHEN SAFE_CAST(Selling_price AS FLOAT64) IS NULL THEN 0
        WHEN IS_NAN(SAFE_CAST(Selling_price AS FLOAT64)) THEN 0
        ELSE SAFE_CAST(Selling_price AS FLOAT64)
      END
    ), 0) AS Easyecom_sale_value,
    Payment_Mode
  FROM (
    SELECT
      Invoice_Date, Order_Number, Suborder_No, SKU,
      Order_Date, Order_Status, Payment_Mode, ee_extracted_at,
      Client_Location,
      AWB_No,
      Selling_Price,
      EE_Invoice_No,
      ROW_NUMBER() OVER (
        PARTITION BY Order_Number, Suborder_No, SKU
        ORDER BY ee_extracted_at DESC
      ) AS rn
    FROM `shopify-pubsub-project.Data_Warehouse_Easyecom_Staging.Mini_Sales_report_B2C`
    WHERE DATE(Order_Date, 'Asia/Kolkata') >= DATE '2025-04-01'
      AND MP_Name = 'Shopify'
  )
  WHERE rn = 1
  GROUP BY ALL
),

-- ✅ FIX: returns now from Tax_return_report (Suborder_No = Shopify order_item_id).
-- Deduped to one row per (order, suborder) — table is at SKU grain, so without
-- GROUP BY, combo SKUs would fan out the join.
Returned_orders_add AS (
  SELECT
    REPLACE(Reference_Code, '`', '') AS Order_Number,
    REPLACE(Suborder_No, '`', '')   AS Order_Item_ID,
    MAX(DATETIME(Return_Date, 'Asia/Kolkata')) AS Return_Date
  FROM `shopify-pubsub-project.Data_Warehouse_Easyecom_Staging.Tax_return_report`
  WHERE MP_Name = 'Shopify'
  GROUP BY 1, 2
),

Clickpost_om AS (
  SELECT
    order_id,
    awb,
    Order_Date,
    Clickpost_Unified_Status,
    Courier_Partner,
    Invoice_Value AS Clickpost_sale_value
  FROM (
    SELECT
      order_id,
      -- ✅ clean AWB at source
      REPLACE(awb, '`', '') AS awb,
      Order_Date,
      Courier_Partner,
      Clickpost_Unified_Status,

      Invoice_Value,
      ROW_NUMBER() OVER (
        PARTITION BY REPLACE(awb, '`', '')
        ORDER BY Ingestion_Date DESC
      ) AS rn
    FROM `shopify-pubsub-project.Data_Warehouse_ClickPost_Staging.Order_Master`
    WHERE DATE_TRUNC(DATE(Order_Date), MONTH) >= DATE '2025-04-01'
      AND awb IS NOT NULL
      AND awb != 'nan'
  )
  WHERE rn = 1
),

Clickpost_tm AS (
  SELECT
    AWB,
    RTO_Delivery_Date
  FROM (
    SELECT
      -- ✅ clean AWB at source
      REPLACE(AWB, '`', '') AS AWB,
      RTO_Delivery_Date,
      ROW_NUMBER() OVER (
        PARTITION BY REPLACE(AWB, '`', '')
        ORDER BY Ingestion_Date DESC
      ) AS rn
    FROM `shopify-pubsub-project.Data_Warehouse_ClickPost_Staging.Tracking_Master`
    WHERE DATE_TRUNC(DATE(Order_date), MONTH) >= DATE '2025-04-01'
      AND RTO_Delivery_Date IS NOT NULL
  )
  WHERE rn = 1
),

final AS (
  SELECT
    e.Invoice_Date,
    e.EE_Invoice_No,
    -- Shopify
    s.order_name                      AS Shopify_order_name,
    s.order_item_id                   AS Shopify_order_item_id,
    s.order_created_at                AS Order_Placed_Date,

    CASE
      WHEN s.Order_fulfillment_status IS NULL
        OR TRIM(s.Order_fulfillment_status) = '' THEN 'Unfulfilled'
      ELSE s.Order_fulfillment_status
    END                               AS Order_Status_Shopify,

    s.Order_financial_status,
    s.is_cancelled                    AS Shopify_is_cancelled,
    s.Shopify_sale_value,

    CASE
      WHEN s.is_cancelled = 1                               THEN 'Cancelled'
      WHEN LOWER(s.Order_fulfillment_status) = 'fulfilled'  THEN 'Shipped'
      WHEN LOWER(s.Order_fulfillment_status) = 'partial'    THEN 'Processing'
      WHEN LOWER(s.Order_fulfillment_status) = 'unknown'    THEN 'Order Created'
      WHEN s.Order_fulfillment_status IS NULL
        OR TRIM(s.Order_fulfillment_status) = ''            THEN 'Unfulfilled'
      ELSE s.Order_fulfillment_status
    END                               AS Shopify_Unified_Status,

    -- EasyEcom
    e.Order_Number                    AS Easyecom_reference_code,
    e.Suborder_No                     AS Easyecom_Suborder_No,
    e.Order_Date_IST                  AS Easyecom_Order_Date_IST,

    -- ✅ Returns override via Shopify item ID join
    CASE
      WHEN r.Order_Number IS NOT NULL THEN 'Returned'
      ELSE e.Order_Status
    END                               AS Order_Status_Easyecom,

    e.tracking_number                 AS Easyecom_tracking_number,
    e.Easyecom_sale_value,

    CASE
      WHEN r.Order_Number IS NOT NULL                       THEN 'Returned (RTO)'
      WHEN LOWER(e.Order_Status) IN (
        'assign pending','approve pending','pending','confirmed',
        'assigned','printed','manifest scanned','upcoming','on hold'
      )                                                     THEN 'Processing'
      WHEN LOWER(e.Order_Status) = 'ready to dispatch'     THEN 'Ready to Dispatch'
      WHEN LOWER(e.Order_Status) = 'shipped'               THEN 'Shipped'
      WHEN LOWER(e.Order_Status) = 'returned'              THEN 'Returned (RTO)'
      WHEN LOWER(e.Order_Status) = 'cancelled'             THEN 'Cancelled'
      ELSE e.Order_Status
    END                               AS Easyecom_Unified_Status,

    -- ClickPost
    c.order_id                        AS Clickpost_order_id,
    c.awb                             AS Clickpost_AWB,
    c.Order_Date                      AS Clickpost_Order_Date,
    Courier_Partner,

    CASE
      WHEN c.awb IS NOT NULL THEN c.Clickpost_Unified_Status
      ELSE NULL
    END                               AS Order_Status_Clickpost,

    CASE
      WHEN c.awb IS NOT NULL THEN c.Clickpost_sale_value
      ELSE NULL
    END                               AS Clickpost_sale_value,

    -- ✅ Return_Date from Tax_return_report first, fallback to Clickpost RTO
    COALESCE(r.Return_Date, tm.RTO_Delivery_Date) AS RTO_Delivery_Date,

    -- Unified Status
    CASE
      WHEN c.awb IS NULL              THEN NULL
      WHEN REPLACE(LOWER(c.Clickpost_Unified_Status), '-', ' ') IN (
        'orderplaced','awb registered','awbregistered',
        'pickuppending','pickup pending','outforpickup','out for pickup',
        'pickupfailed','pickup failed','nostatusexist','no status exist'
      )                                                     THEN 'Processing'
      WHEN REPLACE(LOWER(c.Clickpost_Unified_Status), '-', ' ') IN (
        'pickedup','picked up','origincityout','origin city out'
      )                                                     THEN 'Shipped'
      WHEN REPLACE(LOWER(c.Clickpost_Unified_Status), '-', ' ') IN (
        'origincityin','origin city in','intransit','in transit',
        'destinationhubin','destination hub in',
        'shipmentdelayed','shipment delayed'
      )                                                     THEN 'In Transit'
      WHEN REPLACE(LOWER(c.Clickpost_Unified_Status), '-', ' ') IN (
        'outfordelivery','out for delivery'
      )                                                     THEN 'Out For Delivery'
      WHEN REPLACE(LOWER(c.Clickpost_Unified_Status), '-', ' ') = 'delivered'
                                                            THEN 'Delivered'
      WHEN REPLACE(LOWER(c.Clickpost_Unified_Status), '-', ' ') IN (
        'rto requested','rtorequested','rto intransit','rtointransit',
        'rto outfordelivery','rtooutfordelivery','rto delivered','rtodelivered',
        'rto marked','rtomarked','rto failed','rtofailed'
      )                                                     THEN 'Returned (RTO)'
      WHEN REPLACE(LOWER(c.Clickpost_Unified_Status), '-', ' ') IN (
        'faileddelivery','failed delivery'
      )                                                     THEN 'Delivery Failed'
      WHEN REPLACE(LOWER(c.Clickpost_Unified_Status), '-', ' ') = 'cancelled'
                                                            THEN 'Cancelled'
      WHEN REPLACE(LOWER(c.Clickpost_Unified_Status), '-', ' ') IN (
        'lost','damaged','contactcustomercare','contact customer care'
      )                                                     THEN 'Exception'
      ELSE c.Clickpost_Unified_Status
    END                               AS Unified_Status,

    -- Sale value diff flags (suborder level)
    CASE
      WHEN ROUND(s.Shopify_sale_value - e.Easyecom_sale_value, 0) = 0 THEN 0
      WHEN s.Shopify_sale_value - e.Easyecom_sale_value > 0           THEN 1
      ELSE 0
    END AS S_VS_E,

    CASE
      WHEN c.awb IS NULL                                                THEN NULL
      WHEN ROUND(s.Shopify_sale_value - c.Clickpost_sale_value, 0) = 0 THEN 0
      WHEN s.Shopify_sale_value - c.Clickpost_sale_value > 0           THEN 1
      ELSE 0
    END AS S_VS_C,

    CASE
      WHEN c.awb IS NULL                                                THEN NULL
      WHEN ROUND(e.Easyecom_sale_value - c.Clickpost_sale_value, 0) = 0 THEN 0
      WHEN e.Easyecom_sale_value - c.Clickpost_sale_value > 0           THEN 1
      ELSE 0
    END AS E_VS_C,

    -- Order presence flags
    CASE WHEN s.order_name IS NOT NULL AND e.Order_Number IS NULL THEN 1 ELSE 0 END
      AS SHOPIFY_NOT_IN_EASYE,
    CASE WHEN s.order_name IS NOT NULL AND c.order_id IS NULL     THEN 1 ELSE 0 END
      AS SHOPIFY_NOT_IN_CLICKPOST,
    CASE WHEN e.Order_Number IS NOT NULL AND c.awb IS NULL        THEN 1 ELSE 0 END
      AS EASYE_NOT_IN_CLICKPOST,

    -- Severity
    CASE
      WHEN s.is_cancelled = 1
        AND c.awb IS NOT NULL
        AND REPLACE(LOWER(c.Clickpost_Unified_Status), '-', ' ') = 'delivered'
                                                                         THEN 'ALERT'
      WHEN s.is_cancelled = 1
        AND LOWER(e.Order_Status) = 'shipped'
                                                                         THEN 'ALERT'
      WHEN LOWER(s.Order_fulfillment_status) != 'fulfilled'
        AND s.is_cancelled = 0
        AND c.awb IS NOT NULL
        AND REPLACE(LOWER(c.Clickpost_Unified_Status), '-', ' ') = 'delivered'
                                                                         THEN 'ALERT'
      WHEN c.awb IS NOT NULL
        AND REPLACE(LOWER(c.Clickpost_Unified_Status), '-', ' ') IN ('lost','damaged')
                                                                         THEN 'ALERT'
      WHEN LOWER(e.Order_Status) = 'cancelled'
        AND c.awb IS NOT NULL
        AND REPLACE(LOWER(c.Clickpost_Unified_Status), '-', ' ') = 'delivered'
                                                                         THEN 'ALERT'
      WHEN LOWER(e.Order_Status) = 'shipped'
        AND LOWER(s.Order_fulfillment_status) NOT IN ('fulfilled', 'partial')
        AND s.is_cancelled = 0
                                                                         THEN 'ALERT'
      -- ✅ Returned check uses r.Order_Number
      WHEN r.Order_Number IS NOT NULL
        AND c.awb IS NOT NULL
        AND REPLACE(LOWER(c.Clickpost_Unified_Status), '-', ' ') NOT IN (
              'rto requested','rtorequested',
              'rto intransit','rtointransit',
              'rto outfordelivery','rtooutfordelivery',
              'rto delivered','rtodelivered',
              'rto marked','rtomarked',
              'rto failed','rtofailed'
            )
                                                                         THEN 'ALERT'
      WHEN c.awb IS NOT NULL
        AND REPLACE(LOWER(c.Clickpost_Unified_Status), '-', ' ') IN (
              'rto delivered','rtodelivered')
        AND r.Order_Number IS NULL
        AND LOWER(e.Order_Status) NOT IN ('returned','cancelled')
                                                                         THEN 'ALERT'
      WHEN LOWER(e.Order_Status) = 'ready to dispatch'
        AND DATETIME_DIFF(
              CURRENT_DATETIME('Asia/Kolkata'),
              e.Order_Date_IST, HOUR) > 48                               THEN 'WARNING'
      WHEN c.awb IS NOT NULL
        AND REPLACE(LOWER(c.Clickpost_Unified_Status), '-', ' ') IN (
              'pickuppending','pickup pending')
        AND DATETIME_DIFF(
              CURRENT_DATETIME('Asia/Kolkata'),
              DATETIME(TIMESTAMP(c.Order_Date, 'Asia/Kolkata')), HOUR) > 24
                                                                         THEN 'WARNING'
      WHEN c.awb IS NOT NULL
        AND REPLACE(LOWER(c.Clickpost_Unified_Status), '-', ' ') IN (
              'intransit','in transit','shipmentdelayed','shipment delayed')
        AND DATE_DIFF(
              CURRENT_DATE('Asia/Kolkata'),
              c.Order_Date, DAY) > 7                                     THEN 'WARNING'
      WHEN c.awb IS NOT NULL
        AND REPLACE(LOWER(c.Clickpost_Unified_Status), '-', ' ') IN (
              'faileddelivery','failed delivery')                         THEN 'WARNING'
      WHEN c.awb IS NOT NULL
        AND REPLACE(LOWER(c.Clickpost_Unified_Status), '-', ' ') IN (
              'shipmentdelayed','shipment delayed')                       THEN 'WARNING'
      ELSE 'OK'
    END AS Severity,

    -- Reason
    CASE
      WHEN s.is_cancelled = 1
        AND c.awb IS NOT NULL
        AND REPLACE(LOWER(c.Clickpost_Unified_Status), '-', ' ') = 'delivered'
        THEN 'Order cancelled in Shopify yet delivered'
      WHEN s.is_cancelled = 1
        AND LOWER(e.Order_Status) = 'shipped'
        THEN 'Order cancelled in Shopify yet shipped'
      WHEN LOWER(s.Order_fulfillment_status) != 'fulfilled'
        AND s.is_cancelled = 0
        AND c.awb IS NOT NULL
        AND REPLACE(LOWER(c.Clickpost_Unified_Status), '-', ' ') = 'delivered'
        THEN 'Order not fulfilled in Shopify yet delivered'
      WHEN c.awb IS NOT NULL
        AND REPLACE(LOWER(c.Clickpost_Unified_Status), '-', ' ') = 'lost'
        THEN 'Shipment lost in transit'
      WHEN c.awb IS NOT NULL
        AND REPLACE(LOWER(c.Clickpost_Unified_Status), '-', ' ') = 'damaged'
        THEN 'Shipment damaged in transit'
      WHEN LOWER(e.Order_Status) = 'cancelled'
        AND c.awb IS NOT NULL
        AND REPLACE(LOWER(c.Clickpost_Unified_Status), '-', ' ') = 'delivered'
        THEN 'Order cancelled in EasyEcom yet delivered'
      WHEN LOWER(e.Order_Status) = 'shipped'
        AND LOWER(s.Order_fulfillment_status) NOT IN ('fulfilled', 'partial')
        AND s.is_cancelled = 0
        THEN 'EasyEcom shows Shipped but Shopify fulfillment not updated'
      -- ✅ Returned reason uses r.Order_Number
      WHEN r.Order_Number IS NOT NULL
        AND c.awb IS NOT NULL
        AND REPLACE(LOWER(c.Clickpost_Unified_Status), '-', ' ') NOT IN (
              'rto requested','rtorequested',
              'rto intransit','rtointransit',
              'rto outfordelivery','rtooutfordelivery',
              'rto delivered','rtodelivered',
              'rto marked','rtomarked',
              'rto failed','rtofailed'
            )
        THEN 'EasyEcom shows Returned but Clickpost RTO status not updated'
      WHEN c.awb IS NOT NULL
        AND REPLACE(LOWER(c.Clickpost_Unified_Status), '-', ' ') IN (
              'rto delivered','rtodelivered')
        AND r.Order_Number IS NULL
        AND LOWER(e.Order_Status) NOT IN ('returned','cancelled')
        THEN 'Clickpost RTO Delivered but EasyEcom status not updated to Returned'
      WHEN LOWER(e.Order_Status) = 'ready to dispatch'
        AND DATETIME_DIFF(
              CURRENT_DATETIME('Asia/Kolkata'),
              e.Order_Date_IST, HOUR) > 48
        THEN 'Ready to dispatch for more than 48 hours'
      WHEN c.awb IS NOT NULL
        AND REPLACE(LOWER(c.Clickpost_Unified_Status), '-', ' ') IN (
              'pickuppending','pickup pending')
        AND DATETIME_DIFF(
              CURRENT_DATETIME('Asia/Kolkata'),
              DATETIME(TIMESTAMP(c.Order_Date, 'Asia/Kolkata')), HOUR) > 24
        THEN 'Pickup pending for more than 24 hours'
      WHEN c.awb IS NOT NULL
        AND REPLACE(LOWER(c.Clickpost_Unified_Status), '-', ' ') IN (
              'intransit','in transit','shipmentdelayed','shipment delayed')
        AND DATE_DIFF(
              CURRENT_DATE('Asia/Kolkata'),
              c.Order_Date, DAY) > 7
        THEN 'In transit for more than 7 days'
      WHEN c.awb IS NOT NULL
        AND REPLACE(LOWER(c.Clickpost_Unified_Status), '-', ' ') IN (
              'faileddelivery','failed delivery')
        THEN 'Delivery attempt failed'
      WHEN c.awb IS NOT NULL
        AND REPLACE(LOWER(c.Clickpost_Unified_Status), '-', ' ') IN (
              'shipmentdelayed','shipment delayed')
        THEN 'Shipment delayed'
      ELSE 'OK'
    END AS Reason,

    e.Payment_Mode,
    e.awb,
    e.Warehouse

  FROM Shopify_oi s
  LEFT JOIN Easyecom_tr e
    ON s.order_name = e.Order_Number
    AND CAST(s.order_item_id AS STRING) = REPLACE(e.Suborder_No, '`', '')
  -- ✅ join Returns on Shopify order_name + order_item_id directly
  LEFT JOIN Returned_orders_add r
    ON CAST(s.order_name AS STRING) = r.Order_Number
    AND CAST(s.order_item_id AS STRING) = r.Order_Item_ID
  LEFT JOIN Clickpost_om c
    ON e.tracking_number = c.awb
  LEFT JOIN Clickpost_tm tm
    ON e.tracking_number = tm.AWB
),

order_level_values AS (
  SELECT
    Shopify_order_name,
    ROUND(SUM(COALESCE(Shopify_sale_value, 0)), 0) AS Order_Shopify_sale_value,
    CASE
      WHEN COUNT(Easyecom_sale_value) = 0 THEN NULL
      ELSE ROUND(SUM(COALESCE(Easyecom_sale_value, 0)), 0)
    END AS Order_Easyecom_sale_value,
    CASE
      WHEN COUNT(Clickpost_sale_value) = 0 THEN NULL
      ELSE ROUND(MAX(Clickpost_sale_value), 0)
    END AS Order_Clickpost_sale_value
  FROM final
  GROUP BY Shopify_order_name
)

SELECT
  f.*,
  olv.Order_Shopify_sale_value,
  olv.Order_Easyecom_sale_value,
  olv.Order_Clickpost_sale_value,

  CASE
    WHEN ROUND(olv.Order_Shopify_sale_value - olv.Order_Easyecom_sale_value, 0) = 0 THEN 0
    WHEN olv.Order_Shopify_sale_value - olv.Order_Easyecom_sale_value > 0           THEN 1
    ELSE -1
  END AS Order_S_VS_E_Mismatch,

  CASE
    WHEN olv.Order_Clickpost_sale_value IS NULL                                       THEN NULL
    WHEN ROUND(olv.Order_Shopify_sale_value - olv.Order_Clickpost_sale_value, 0) = 0 THEN 0
    WHEN olv.Order_Shopify_sale_value - olv.Order_Clickpost_sale_value > 0           THEN 1
    ELSE -1
  END AS Order_S_VS_C_Mismatch,

  CASE
    WHEN olv.Order_Clickpost_sale_value IS NULL                                        THEN NULL
    WHEN ROUND(olv.Order_Easyecom_sale_value - olv.Order_Clickpost_sale_value, 0) = 0 THEN 0
    WHEN olv.Order_Easyecom_sale_value - olv.Order_Clickpost_sale_value > 0           THEN 1
    ELSE -1
  END AS Order_E_VS_C_Mismatch

FROM final f
LEFT JOIN order_level_values olv
  ON f.Shopify_order_name = olv.Shopify_order_name;
