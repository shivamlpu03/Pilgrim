CREATE OR REPLACE TABLE `shopify-pubsub-project.Dashboard_category_pnl.D2C_PNL_DAILY_New` AS
-- =====================================================================
-- DAILY P&L  (data range: 2026-01-01 onwards)
-- =====================================================================

WITH

-- -------------------------------------------------------------------------
-- 0. Kit/combo GST rate (combo/physicalkit from D2C_SKU_mapping)
--    5% if kit title qualifies, else 18%
-- -------------------------------------------------------------------------
kit_gst_rate AS (
  SELECT DISTINCT
    Parent_SKU,
    CASE
      WHEN LOWER(Master_Title) LIKE '%hair oil%'
        OR LOWER(Master_Title) LIKE '%compact powder%'
        OR LOWER(Sub_Category)  LIKE '%shampoo%'
        THEN 0.05 / 1.05
      ELSE 0.18 / 1.18
    END AS gst_rate_factor
  FROM `shopify-pubsub-project.Product_SKU_Mapping.D2C_SKU_mapping`
  WHERE LOWER(Type_of_Product) IN ('combo', 'physicalkit')
    AND Parent_SKU IS NOT NULL
),

-- -------------------------------------------------------------------------
-- 1. All non-cancelled order lines
-- -------------------------------------------------------------------------
order_lines AS (
  SELECT
    DATE(oim.Order_created_at)               AS order_date,
    oim.Order_name,
    oim.Parent_SKU,
    oim.master_title,
    oim.item_quantity,
    oim.item_MRP_price,
    oim.item_MRP_price * oim.item_quantity    AS item_mrp_value,
    oim.item_gross_revenue                    AS item_selling_rev,
    CASE
      -- Kit/combo: use pre-computed rate (5% if all components 5%, else 18%)
      WHEN kg.gst_rate_factor IS NOT NULL
        THEN oim.item_gross_revenue * kg.gst_rate_factor
      -- Regular single product: existing logic
      WHEN LOWER(oim.master_title) LIKE '%hair oil%'
        OR LOWER(oim.master_title) LIKE '%compact powder%'
        OR LOWER(oim.Sub_Category) LIKE '%shampoo%'
        THEN oim.item_gross_revenue * 0.05 / 1.05
      ELSE
        oim.item_gross_revenue * 0.18 / 1.18
    END                                       AS item_gst
  FROM `shopify-pubsub-project.Data_Warehouse_Shopify_Staging.Order_items_master` oim
  LEFT JOIN kit_gst_rate kg ON kg.Parent_SKU = oim.Parent_SKU
  WHERE DATE(oim.Order_created_at) >= DATE '2026-01-01'
    AND COALESCE(oim.is_cancelled, 0) = 0
),

-- -------------------------------------------------------------------------
-- 2. Non-delivered order IDs
-- -------------------------------------------------------------------------
non_delivered_orders AS (
  SELECT DISTINCT Order_ID
  FROM `shopify-pubsub-project.Data_Warehouse_ClickPost_Staging.Tracking_Master`
  WHERE Order_date >= DATE_SUB(DATE '2026-01-01', INTERVAL 30 DAY)
    AND Clickpost_Unified_Status IN (
      'RTO-Delivered', 'RTO-Marked', 'RTO-InTransit',
      'RTO-OutForDelivery', 'RTO-Failed', 'RTO-Requested',
      'Lost', 'Damaged', 'FailedDelivery', 'PickupFailed'
    )
),

-- -------------------------------------------------------------------------
-- 3. Gross daily totals (ALL orders including RTOs)
-- -------------------------------------------------------------------------
daily_gross AS (
  SELECT
    order_date,
    COUNT(DISTINCT Order_name) AS gross_orders,
    SUM(item_selling_rev)      AS total_selling_rev,
    SUM(item_quantity)         AS gross_units,
    SUM(item_mrp_value)        AS gmv
  FROM order_lines
  GROUP BY order_date
),

-- -------------------------------------------------------------------------
-- 4. Return (RTO) daily totals — bucketed by Order_created_at
-- -------------------------------------------------------------------------
daily_rto AS (
  SELECT
    ol.order_date,
    COUNT(DISTINCT ol.Order_name) AS rto_orders,
    SUM(ol.item_quantity)         AS return_units,
    SUM(ol.item_mrp_value)        AS returns_mrp
  FROM order_lines ol
  INNER JOIN non_delivered_orders nd ON nd.Order_ID = ol.Order_name
  GROUP BY ol.order_date
),

-- -------------------------------------------------------------------------
-- 5. Net order lines (delivered only)
-- -------------------------------------------------------------------------
net_order_lines AS (
  SELECT ol.*
  FROM order_lines ol
  LEFT JOIN non_delivered_orders nd ON nd.Order_ID = ol.Order_name
  WHERE nd.Order_ID IS NULL
),

-- -------------------------------------------------------------------------
-- 6. Gross_Sales and GST on delivered orders
-- -------------------------------------------------------------------------
daily_net_sales AS (
  SELECT
    order_date,
    SUM(item_selling_rev) AS gross_sales,
    SUM(item_gst)         AS gst
  FROM net_order_lines
  GROUP BY order_date
),

-- -------------------------------------------------------------------------
-- 7. COGS on delivered orders — split into regular vs freebie
-- Freebie SKUs: PGJB%, SAM%, %MINI%, %GIFT%, %PG-CL25%,
--               %PG-RB1%, %PG-RMB2%, %PG-GMP1%, or title contains bag/pouch
-- Fallback for freebies with no COGS: 15% of MRP from D2C_SKU_mapping
-- -------------------------------------------------------------------------
freebie_sku_mrp AS (
  SELECT
    Parent_SKU,
    MAX(MRP) AS catalog_mrp
  FROM `shopify-pubsub-project.Product_SKU_Mapping.D2C_SKU_mapping`
  WHERE Parent_SKU IS NOT NULL
  GROUP BY Parent_SKU
),

-- COGS lookup: latest rate per SKU as of order_date (from flat cogs_bq table)
daily_cogs_lookup AS (
  SELECT
    d.order_date,
    c.SKU_Name,
    c.COGS_ AS cogs_per_unit
  FROM (SELECT DISTINCT order_date FROM net_order_lines) d
  CROSS JOIN (
    SELECT SKU_Name, COGS_, Date
    FROM `shopify-pubsub-project.finance_cogs.cogs_bq`
    WHERE SKU_Name IS NOT NULL
  ) c
  WHERE c.Date = (
    SELECT MAX(c2.Date)
    FROM `shopify-pubsub-project.finance_cogs.cogs_bq` c2
    WHERE c2.SKU_Name = c.SKU_Name
      AND c2.Date    <= d.order_date
  )
),

daily_cogs AS (
  SELECT
    ol.order_date,

    -- Regular COGS (non-freebie items only)
    SUM(
      CASE WHEN NOT (
        ol.Parent_SKU LIKE 'PGJB%'
        OR ol.Parent_SKU LIKE 'SAM%'
        OR ol.Parent_SKU LIKE '%MINI%'
        OR ol.Parent_SKU LIKE '%GIFT%'
        OR ol.Parent_SKU LIKE '%PG-CL25%'
        OR ol.Parent_SKU LIKE '%PG-RB1%'
        OR ol.Parent_SKU LIKE '%PG-RMB2%'
        OR ol.Parent_SKU LIKE '%PG-GMP1%'
        OR LOWER(ol.master_title) LIKE '%bag%'
        OR LOWER(ol.master_title) LIKE '%pouch%'
      ) THEN
        CASE
          WHEN cl.cogs_per_unit IS NOT NULL
            THEN cl.cogs_per_unit * ol.item_quantity
          ELSE
            ol.item_MRP_price * 0.15 * ol.item_quantity
        END
      ELSE 0 END
    )                                                           AS less_cogs,

    -- Freebie COGS (actual COGS from cogs_bq; else 15% of catalog MRP from D2C_SKU_mapping)
    SUM(
      CASE WHEN (
        ol.Parent_SKU LIKE 'PGJB%'
        OR ol.Parent_SKU LIKE 'SAM%'
        OR ol.Parent_SKU LIKE '%MINI%'
        OR ol.Parent_SKU LIKE '%GIFT%'
        OR ol.Parent_SKU LIKE '%PG-CL25%'
        OR ol.Parent_SKU LIKE '%PG-RB1%'
        OR ol.Parent_SKU LIKE '%PG-RMB2%'
        OR ol.Parent_SKU LIKE '%PG-GMP1%'
        OR LOWER(ol.master_title) LIKE '%bag%'
        OR LOWER(ol.master_title) LIKE '%pouch%'
      ) THEN
        CASE
          WHEN cl.cogs_per_unit IS NOT NULL
            THEN cl.cogs_per_unit * ol.item_quantity
          ELSE
            COALESCE(fm.catalog_mrp, 0) * 0.15 * ol.item_quantity
        END
      ELSE 0 END
    )                                                           AS freebie_cogs,

    SUM(
      CASE WHEN cl.cogs_per_unit IS NULL
            AND NOT (
              ol.Parent_SKU LIKE 'PGJB%'
              OR ol.Parent_SKU LIKE 'SAM%'
              OR ol.Parent_SKU LIKE '%MINI%'
              OR ol.Parent_SKU LIKE '%GIFT%'
              OR ol.Parent_SKU LIKE '%PG-CL25%'
              OR ol.Parent_SKU LIKE '%PG-RB1%'
              OR ol.Parent_SKU LIKE '%PG-RMB2%'
              OR ol.Parent_SKU LIKE '%PG-GMP1%'
              OR LOWER(ol.master_title) LIKE '%bag%'
              OR LOWER(ol.master_title) LIKE '%pouch%'
            )
           THEN ol.item_MRP_price * 0.15 * ol.item_quantity ELSE 0 END
    )                                                           AS cogs_from_fallback,
    SUM(
      CASE WHEN cl.cogs_per_unit IS NULL
            AND NOT (
              ol.Parent_SKU LIKE 'PGJB%'
              OR ol.Parent_SKU LIKE 'SAM%'
              OR ol.Parent_SKU LIKE '%MINI%'
              OR ol.Parent_SKU LIKE '%GIFT%'
              OR ol.Parent_SKU LIKE '%PG-CL25%'
              OR ol.Parent_SKU LIKE '%PG-RB1%'
              OR ol.Parent_SKU LIKE '%PG-RMB2%'
              OR ol.Parent_SKU LIKE '%PG-GMP1%'
              OR LOWER(ol.master_title) LIKE '%bag%'
              OR LOWER(ol.master_title) LIKE '%pouch%'
            )
           THEN 1 ELSE 0 END
    )                                                           AS fallback_lines
  FROM net_order_lines ol
  LEFT JOIN daily_cogs_lookup cl
    ON  cl.order_date = ol.order_date
    AND cl.SKU_Name   = ol.Parent_SKU
  LEFT JOIN freebie_sku_mrp fm
    ON  fm.Parent_SKU = ol.Parent_SKU
  GROUP BY ol.order_date
),

-- -------------------------------------------------------------------------
-- 8. Google spend
-- -------------------------------------------------------------------------
daily_google AS (
  SELECT
    segments_date    AS order_date,
    SUM(total_spend) AS google_spend
  FROM `shopify-pubsub-project.Data_Warehouse_GoogleAds_Staging.Campagin_Day_Level`
  WHERE segments_date >= DATE '2026-01-01'
  GROUP BY segments_date
),

-- -------------------------------------------------------------------------
-- 9. Meta spend
-- -------------------------------------------------------------------------
daily_meta AS (
  SELECT
    DATE(date_start)     AS order_date,
    ROUND(SUM(spend), 2) AS meta_spend
  FROM (
    SELECT
      date_start,
      CAST(spend AS FLOAT64) AS spend,
      ROW_NUMBER() OVER (
        PARTITION BY ad_id, date_start, hourly_stats_aggregated_by_advertiser_time_zone
        ORDER BY pg_extracted_at DESC
      ) AS rn
    FROM `shopify-pubsub-project.fb_airbyte_2.meta_hourly_spend`
    WHERE DATE(date_start) >= DATE_SUB(CURRENT_DATE('Asia/Kolkata'), INTERVAL 1 DAY)
  )
  WHERE rn = 1
  GROUP BY DATE(date_start)

  UNION ALL

  SELECT
    date_start       AS order_date,
    SUM(spend)       AS meta_spend
  FROM `shopify-pubsub-project.Data_Warehouse_Facebook_Ads_Staging.Meta_ads_insights_Master`
  WHERE date_start >= DATE '2026-01-01'
    AND date_start < DATE_SUB(CURRENT_DATE('Asia/Kolkata'), INTERVAL 1 DAY)
  GROUP BY date_start
),

-- -------------------------------------------------------------------------
-- 10. Brand marketing spends (AppLovin, CRM, GPay, PhonePe, PayTM)
-- -------------------------------------------------------------------------
daily_brand_marketing AS (
  SELECT
    Date                                          AS order_date,
    COALESCE(AppLovin_Actual, 0)                  AS applovin_spend,
    COALESCE(CRM_Actual, 0)                       AS crm_spend,
    COALESCE(GPay_Actual, 0)                      AS gpay_spend,
    COALESCE(PhonePe_Actual, 0)                   AS phonepay_spend,
    COALESCE(SAFE_CAST(PayTM_Actual AS FLOAT64), 0) AS paytm_spend
  FROM `shopify-pubsub-project.Dashboard_category_pnl.CRM_APPLOVIN_OTHERS_SPEND_New`
  WHERE Date >= DATE '2026-01-01'
),

-- -------------------------------------------------------------------------
-- 11. Actual shipping cost from CPS (AWB → Order → Daily)
-- -------------------------------------------------------------------------
cps_deduped AS (
  -- Remove exact duplicate rows per (AWB, charge_type) — mainly affects Shiprocket
  SELECT AWB_No, Order_Number, final_charge
  FROM `shopify-pubsub-project.Cost_Validation.CPS`
  WHERE charge_type IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY AWB_No, charge_type ORDER BY AWB_No) = 1
),

cps_per_order AS (
  -- Sum forward + RTO charges per order
  SELECT Order_Number, SUM(final_charge) AS order_shipping_cost
  FROM cps_deduped
  GROUP BY Order_Number
),

daily_shipping AS (
  -- Join distinct orders to CPS; fallback ₹40 if no CPS data
  SELECT
    ol.order_date,
    SUM(COALESCE(cs.order_shipping_cost, 40)) AS actual_shipping,
    COUNTIF(cs.order_shipping_cost IS NULL)    AS fallback_orders
  FROM (
    SELECT DISTINCT order_date, Order_name
    FROM order_lines
  ) ol
  LEFT JOIN cps_per_order cs ON cs.Order_Number = ol.Order_name
  GROUP BY ol.order_date
)

-- -------------------------------------------------------------------------
-- FINAL
-- -------------------------------------------------------------------------
SELECT
  g.order_date                                                          AS date,

  -- 1. GMV
  ROUND(g.gmv, 2)                                                       AS gmv,

  -- 2. Gross_Without_Cancellation
  ROUND(g.total_selling_rev, 2)                                         AS Gross_Without_Cancellation,

  -- 3. Returns = RTO units × MRP
  ROUND(COALESCE(r.returns_mrp, 0), 2)                                  AS returns,

  -- 4. MRP_Value = GMV − Returns
  ROUND(g.gmv - COALESCE(r.returns_mrp, 0), 2)                         AS mrp_value,

  -- 5. Discounts = MRP_Value − Gross_Sales
  ROUND(
    (g.gmv - COALESCE(r.returns_mrp, 0))
    - COALESCE(ns.gross_sales, 0),
    2
  )                                                                     AS discounts,

  -- 6. Gross_Sales
  ROUND(COALESCE(ns.gross_sales, 0), 2)                                 AS gross_sales,

  -- 7. GST
  ROUND(COALESCE(ns.gst, 0), 2)                                         AS gst,

  -- 8. Net_Sales = Gross_Sales − GST
  ROUND(COALESCE(ns.gross_sales, 0) - COALESCE(ns.gst, 0), 2)          AS net_sales,

  -- 9. COGS — split into regular and freebie
  ROUND(COALESCE(c.less_cogs, 0), 2)                                    AS less_cogs,
  ROUND(COALESCE(c.freebie_cogs, 0), 2)                                 AS freebie_cogs,
  ROUND(COALESCE(c.cogs_from_fallback, 0), 2)                           AS cogs_from_fallback,
  COALESCE(c.fallback_lines, 0)                                          AS fallback_lines,

  -- 10. Inward_Logistics = 0.7% of MRP_Value
  ROUND((g.gmv - COALESCE(r.returns_mrp, 0)) * 0.007, 2)               AS inward_logistics,

  -- 11. Gross_Profit = Net_Sales − (Less_COGS + Freebie_COGS) − Inward_Logistics
  ROUND(
    (COALESCE(ns.gross_sales, 0) - COALESCE(ns.gst, 0))
    - COALESCE(c.less_cogs, 0)
    - COALESCE(c.freebie_cogs, 0)
    - (g.gmv - COALESCE(r.returns_mrp, 0)) * 0.007,
    2
  )                                                                     AS gross_profit,

  -- 12. Txn_Fees = 0.65% of Net_Sales
  ROUND((COALESCE(ns.gross_sales, 0) - COALESCE(ns.gst, 0)) * 0.0065, 2) AS txn_fees,

  -- 13. Order_Process = 1.5% of MRP_Value
  ROUND((g.gmv - COALESCE(r.returns_mrp, 0)) * 0.015, 2)               AS order_proc,

  -- 14. Engagement_Fees = Txn_Fees + Order_Process
  ROUND(
    (COALESCE(ns.gross_sales, 0) - COALESCE(ns.gst, 0)) * 0.0065
    + (g.gmv - COALESCE(r.returns_mrp, 0)) * 0.015,
    2
  )                                                                     AS engagement_fees,

  -- 15. Shipping = actual CPS cost (fallback ₹40/order where CPS missing)
  ROUND(COALESCE(sh.actual_shipping, g.gross_orders * 40), 2)           AS shipping,
  COALESCE(sh.fallback_orders, 0)                                        AS shipping_fallback_orders,

  -- 16. CM1 = Gross_Profit − Engagement_Fees − Shipping
  ROUND(
    (COALESCE(ns.gross_sales, 0) - COALESCE(ns.gst, 0))
    - COALESCE(c.less_cogs, 0)
    - COALESCE(c.freebie_cogs, 0)
    - (g.gmv - COALESCE(r.returns_mrp, 0)) * 0.007
    - ((COALESCE(ns.gross_sales, 0) - COALESCE(ns.gst, 0)) * 0.0065
       + (g.gmv - COALESCE(r.returns_mrp, 0)) * 0.015)
    - COALESCE(sh.actual_shipping, g.gross_orders * 40),
    2
  )                                                                     AS cm1,

  -- 17. Google Ads
  ROUND(COALESCE(gs.google_spend, 0), 2)                                AS google,

  -- 18. Meta Ads
  ROUND(COALESCE(m.meta_spend, 0), 2)                                   AS meta,

  -- 19. Brand Marketing (AppLovin + CRM + GPay + PhonePe + PayTM)
  ROUND(COALESCE(bm.applovin_spend, 0), 2)                              AS applovin,
  ROUND(COALESCE(bm.crm_spend, 0), 2)                                   AS crm,
  ROUND(COALESCE(bm.gpay_spend, 0), 2)                                  AS gpay,
  ROUND(COALESCE(bm.phonepay_spend, 0), 2)                              AS phonepay,
  ROUND(COALESCE(bm.paytm_spend, 0), 2)                                 AS paytm,
  ROUND(
    COALESCE(bm.applovin_spend, 0)
    + COALESCE(bm.crm_spend, 0)
    + COALESCE(bm.gpay_spend, 0)
    + COALESCE(bm.phonepay_spend, 0)
    + COALESCE(bm.paytm_spend, 0),
    2
  )                                                                     AS brand_marketing,

  -- 20. CM2 = CM1 − Google − Meta − Brand Marketing
  ROUND(
    (COALESCE(ns.gross_sales, 0) - COALESCE(ns.gst, 0))
    - COALESCE(c.less_cogs, 0)
    - COALESCE(c.freebie_cogs, 0)
    - (g.gmv - COALESCE(r.returns_mrp, 0)) * 0.007
    - ((COALESCE(ns.gross_sales, 0) - COALESCE(ns.gst, 0)) * 0.0065
       + (g.gmv - COALESCE(r.returns_mrp, 0)) * 0.015)
    - COALESCE(sh.actual_shipping, g.gross_orders * 40)
    - COALESCE(gs.google_spend, 0)
    - COALESCE(m.meta_spend, 0)
    - COALESCE(bm.applovin_spend, 0)
    - COALESCE(bm.crm_spend, 0)
    - COALESCE(bm.gpay_spend, 0)
    - COALESCE(bm.phonepay_spend, 0)
    - COALESCE(bm.paytm_spend, 0),
    2
  )                                                                     AS cm2

FROM            daily_gross           g
LEFT JOIN       daily_rto             r   USING (order_date)
LEFT JOIN       daily_net_sales       ns  USING (order_date)
LEFT JOIN       daily_cogs            c   USING (order_date)
LEFT JOIN       daily_google          gs  USING (order_date)
LEFT JOIN       daily_meta            m   USING (order_date)
LEFT JOIN       daily_brand_marketing bm  USING (order_date)
LEFT JOIN       daily_shipping        sh  USING (order_date)
ORDER BY date DESC;
