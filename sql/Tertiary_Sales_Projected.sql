CREATE OR REPLACE TABLE `shopify-pubsub-project.Product_SKU_Mapping.Tertiary_Master_Sales` AS
-- 
WITH all_raw AS (
  SELECT *
  FROM `shopify-pubsub-project.Product_SKU_Mapping.Tertiary_Master_Sales_Actual`
),

-- =========================================================
-- PILGRIM: Rolling-avg projection channels
-- =========================================================
pilgrim_actual_agg AS (
  SELECT 
    Brand, Com, source_channel, Channel, order_date,
    parent_sku, Product_Title, Master_Title,
    Main_Category, Sub_Category, Region,
    SUM(GMV)         AS GMV,
    SUM(Gross_Sales) AS Gross_Sales,
    SUM(Units_Sold)  AS Units_Sold
  FROM all_raw
  WHERE Brand = 'PILGRIM'
  GROUP BY ALL
),

pilgrim_per_channel_max AS (
  SELECT Channel, MAX(order_date) AS max_date
  FROM pilgrim_actual_agg
  GROUP BY Channel
),

pilgrim_monthly_channels_with_data AS (
  SELECT DISTINCT Channel, DATE_TRUNC(order_date, MONTH) AS month_with_data
  FROM pilgrim_actual_agg
  WHERE Channel IN ('Smytten', 'Purplle', 'First Cry', 'Export')
),

pilgrim_latest_data_month AS (
  SELECT Channel, MAX(DATE_TRUNC(order_date, MONTH)) AS latest_month
  FROM pilgrim_actual_agg
  WHERE Channel IN ('Smytten', 'Purplle', 'First Cry', 'Export')
  GROUP BY Channel
),

pilgrim_last7_avg AS (
  SELECT
    a.Brand, a.Com, a.source_channel, a.Channel,
    a.parent_sku, a.Product_Title, a.Master_Title,
    a.Main_Category, a.Sub_Category, a.Region,
    AVG(a.GMV)         AS GMV,
    AVG(a.Gross_Sales) AS Gross_Sales,
    AVG(a.Units_Sold)  AS Units_Sold
  FROM pilgrim_actual_agg a
  INNER JOIN pilgrim_per_channel_max m ON a.Channel = m.Channel
  WHERE a.order_date BETWEEN DATE_SUB(m.max_date, INTERVAL 6 DAY) AND m.max_date
    AND a.Channel NOT IN ('Smytten', 'Purplle', 'First Cry', 'Export')
  GROUP BY ALL
),

pilgrim_proj_dates AS (
  SELECT
    m.Channel,
    DATE_ADD(m.max_date, INTERVAL offset DAY) AS order_date,
    offset AS days_ahead
  FROM pilgrim_per_channel_max m,
  UNNEST(GENERATE_ARRAY(1, 60)) AS offset
  WHERE DATE_ADD(m.max_date, INTERVAL offset DAY) <= DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
    AND m.Channel NOT IN ('Smytten', 'Purplle', 'First Cry', 'Export')
),

pilgrim_initial_projections AS (
  SELECT
    l.Brand, l.Com, l.source_channel, l.Channel, d.order_date,
    l.parent_sku, l.Product_Title, l.Master_Title,
    l.Main_Category, l.Sub_Category, l.Region,
    l.GMV, l.Gross_Sales, l.Units_Sold,
    d.days_ahead, TRUE AS is_projected
  FROM pilgrim_last7_avg l
  INNER JOIN pilgrim_proj_dates d ON l.Channel = d.Channel
),

pilgrim_combined_data AS (
  SELECT
    Brand, Com, source_channel, Channel, order_date,
    parent_sku, Product_Title, Master_Title,
    Main_Category, Sub_Category, Region,
    GMV, Gross_Sales, Units_Sold,
    0 AS days_ahead, FALSE AS is_projected
  FROM pilgrim_actual_agg
  WHERE Channel NOT IN ('Smytten', 'Purplle', 'First Cry', 'Export')

  UNION ALL

  SELECT
    Brand, Com, source_channel, Channel, order_date,
    parent_sku, Product_Title, Master_Title,
    Main_Category, Sub_Category, Region,
    GMV, Gross_Sales, Units_Sold,
    days_ahead, is_projected
  FROM pilgrim_initial_projections
),

pilgrim_rolling_avg AS (
  SELECT
    c1.Brand, c1.Com, c1.source_channel, c1.Channel, c1.order_date,
    c1.parent_sku, c1.Product_Title, c1.Master_Title,
    c1.Main_Category, c1.Sub_Category, c1.Region,
    CASE WHEN c1.is_projected THEN AVG(c2.GMV)         ELSE MAX(c1.GMV)         END AS GMV,
    CASE WHEN c1.is_projected THEN AVG(c2.Gross_Sales) ELSE MAX(c1.Gross_Sales) END AS Gross_Sales,
    CASE WHEN c1.is_projected THEN AVG(c2.Units_Sold)  ELSE MAX(c1.Units_Sold)  END AS Units_Sold,
    c1.is_projected
  FROM pilgrim_combined_data c1
  LEFT JOIN pilgrim_combined_data c2
    ON  c1.Channel      = c2.Channel
    AND c1.Product_Title = c2.Product_Title
    AND c1.Master_Title  = c2.Master_Title
    AND c1.Main_Category = c2.Main_Category
    AND c1.Sub_Category  = c2.Sub_Category
    AND c2.order_date BETWEEN DATE_SUB(c1.order_date, INTERVAL 7 DAY) AND DATE_SUB(c1.order_date, INTERVAL 1 DAY)
    AND (c2.days_ahead < c1.days_ahead OR c2.days_ahead = 0)
  GROUP BY
    c1.Brand, c1.Com, c1.source_channel, c1.Channel, c1.order_date,
    c1.parent_sku, c1.Product_Title, c1.Master_Title,
    c1.Main_Category, c1.Sub_Category, c1.Region, c1.is_projected
),

-- =========================================================
-- PILGRIM: Monthly-target channels (Smytten, Purplle, First Cry, Export)
-- =========================================================
month_targets AS (
  SELECT Month, 'Smytten'   AS Channel, Smytten    AS monthly_target
  FROM `shopify-pubsub-project.Marketplaces_Staging_Dataset.Target_Secondary`
  WHERE Smytten IS NOT NULL
  UNION ALL
  SELECT Month, 'Purplle'   AS Channel, Purplle    AS monthly_target
  FROM `shopify-pubsub-project.Marketplaces_Staging_Dataset.Target_Secondary`
  WHERE Purplle IS NOT NULL
  UNION ALL
  SELECT Month, 'First Cry' AS Channel, First_Cry  AS monthly_target
  FROM `shopify-pubsub-project.Marketplaces_Staging_Dataset.Target_Secondary`
  WHERE First_Cry IS NOT NULL
  UNION ALL
  SELECT Month, 'Export'    AS Channel, Export     AS monthly_target
  FROM `shopify-pubsub-project.Marketplaces_Staging_Dataset.Target_Secondary`
  WHERE Export IS NOT NULL
),

month_targets_expanded AS (
  SELECT
    Channel, Month, monthly_target,
    DATE_DIFF(DATE_ADD(Month, INTERVAL 1 MONTH), Month, DAY) AS days_in_month,
    SAFE_DIVIDE(
      monthly_target,
      DATE_DIFF(DATE_ADD(Month, INTERVAL 1 MONTH), Month, DAY)
    ) AS daily_target
  FROM month_targets
),

pilgrim_channel_monthly_totals AS (
  SELECT
    a.Channel,
    DATE_TRUNC(a.order_date, MONTH) AS Month,
    SUM(a.GMV)        AS total_monthly_gmv,
    SUM(a.Units_Sold) AS total_monthly_units
  FROM pilgrim_actual_agg a
  INNER JOIN pilgrim_latest_data_month ldm
    ON  a.Channel = ldm.Channel
    AND DATE_TRUNC(a.order_date, MONTH) = ldm.latest_month
  WHERE a.Channel IN ('Smytten', 'Purplle', 'First Cry', 'Export')
  GROUP BY a.Channel, DATE_TRUNC(a.order_date, MONTH)
),

pilgrim_sku_monthly_contribution AS (
  SELECT
    a.Brand, a.Com, a.Channel, a.parent_sku,
    a.Product_Title, a.Master_Title, a.Main_Category, a.Sub_Category, a.Region,
    SUM(a.GMV)        AS sku_monthly_gmv,
    SUM(a.Units_Sold) AS sku_monthly_units,
    SAFE_DIVIDE(SUM(a.GMV),        t.total_monthly_gmv)   AS sku_contribution_pct,
    SAFE_DIVIDE(SUM(a.Units_Sold), t.total_monthly_units) AS sku_units_contribution_pct
  FROM pilgrim_actual_agg a
  INNER JOIN pilgrim_latest_data_month ldm
    ON  a.Channel = ldm.Channel
    AND DATE_TRUNC(a.order_date, MONTH) = ldm.latest_month
  INNER JOIN pilgrim_channel_monthly_totals t
    ON  a.Channel = t.Channel
    AND DATE_TRUNC(a.order_date, MONTH) = t.Month
  WHERE a.Channel IN ('Smytten', 'Purplle', 'First Cry', 'Export')
  GROUP BY
    a.Brand, a.Com, a.Channel, a.parent_sku,
    a.Product_Title, a.Master_Title, a.Main_Category, a.Sub_Category, a.Region,
    t.total_monthly_gmv, t.total_monthly_units
),

pilgrim_channel_asp AS (
  SELECT
    a.Brand, a.Com, a.Channel,
    SAFE_DIVIDE(SUM(a.GMV), NULLIF(SUM(a.Units_Sold), 0)) AS avg_selling_price
  FROM pilgrim_actual_agg a
  INNER JOIN pilgrim_latest_data_month ldm
    ON  a.Channel = ldm.Channel
    AND DATE_TRUNC(a.order_date, MONTH) = ldm.latest_month
  WHERE a.Channel IN ('Smytten', 'Purplle', 'First Cry', 'Export')
  GROUP BY a.Brand, a.Com, a.Channel
),

daily_target_units AS (
  SELECT
    mte.Channel, mte.Month, mte.daily_target, mte.days_in_month,
    SAFE_DIVIDE(mte.daily_target, NULLIF(asp.avg_selling_price, 0)) AS daily_units_target
  FROM month_targets_expanded mte
  LEFT JOIN pilgrim_channel_asp asp ON mte.Channel = asp.Channel
),

pilgrim_monthly_daily_rows AS (
  -- SKU-level contribution rows
  SELECT
    smc.Brand,
    smc.Com,
    CASE WHEN dtu.Channel IN ('Smytten', 'Purplle', 'First Cry') THEN 'Marketplace' ELSE 'Offline' END AS source_channel,
    dtu.Channel,
    DATE_ADD(dtu.Month, INTERVAL day_offset DAY) AS order_date,
    smc.parent_sku, smc.Product_Title, smc.Master_Title,
    smc.Main_Category, smc.Sub_Category, smc.Region,
    dtu.daily_target * COALESCE(smc.sku_contribution_pct,       0) AS GMV,
    dtu.daily_target * COALESCE(smc.sku_contribution_pct,       0) AS Gross_Sales,
    dtu.daily_units_target * COALESCE(smc.sku_units_contribution_pct, 0) AS Units_Sold,
    TRUE AS is_projected
  FROM daily_target_units dtu
  CROSS JOIN UNNEST(GENERATE_ARRAY(0, days_in_month - 1)) AS day_offset
  INNER JOIN pilgrim_sku_monthly_contribution smc ON dtu.Channel = smc.Channel
  LEFT JOIN pilgrim_monthly_channels_with_data mcd
    ON  dtu.Channel = mcd.Channel
    AND dtu.Month   = mcd.month_with_data
  WHERE DATE_ADD(dtu.Month, INTERVAL day_offset DAY) <= DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
    AND mcd.month_with_data IS NULL

  UNION ALL

  -- Fallback: channel has no SKU data yet
  SELECT
    'PILGRIM'            AS Brand,
    CAST(NULL AS STRING) AS Com,
    CASE WHEN dtu.Channel IN ('Smytten', 'Purplle', 'First Cry') THEN 'Marketplace' ELSE 'Offline' END AS source_channel,
    dtu.Channel,
    DATE_ADD(dtu.Month, INTERVAL day_offset DAY) AS order_date,
    CAST(NULL AS STRING) AS parent_sku,
    CAST(NULL AS STRING) AS Product_Title,
    CAST(NULL AS STRING) AS Master_Title,
    CAST(NULL AS STRING) AS Main_Category,
    CAST(NULL AS STRING) AS Sub_Category,
    'null'               AS Region,
    dtu.daily_target       AS GMV,
    dtu.daily_target       AS Gross_Sales,
    dtu.daily_units_target AS Units_Sold,
    TRUE AS is_projected
  FROM daily_target_units dtu
  CROSS JOIN UNNEST(GENERATE_ARRAY(0, days_in_month - 1)) AS day_offset
  LEFT JOIN pilgrim_monthly_channels_with_data mcd
    ON  dtu.Channel = mcd.Channel
    AND dtu.Month   = mcd.month_with_data
  LEFT JOIN pilgrim_sku_monthly_contribution smc ON dtu.Channel = smc.Channel
  WHERE DATE_ADD(dtu.Month, INTERVAL day_offset DAY) <= DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
    AND mcd.month_with_data IS NULL
    AND smc.Channel IS NULL
),

pilgrim_monthly_actuals AS (
  SELECT
    Brand, Com, source_channel, Channel, order_date,
    parent_sku, Product_Title, Master_Title,
    Main_Category, Sub_Category, Region,
    GMV, Gross_Sales, Units_Sold,
    FALSE AS is_projected
  FROM pilgrim_actual_agg
  WHERE Channel IN ('Smytten', 'Purplle', 'First Cry', 'Export')
),

-- =========================================================
-- PHD: Rolling-avg projection (all channels)
-- =========================================================
phd_actual_agg AS (
  SELECT
    Brand, Com, source_channel, Channel, order_date,
    parent_sku, Product_Title, Master_Title,
    Main_Category, Sub_Category, Region,
    SUM(GMV)         AS GMV,
    SUM(Gross_Sales) AS Gross_Sales,
    SUM(Units_Sold)  AS Units_Sold
  FROM all_raw
  WHERE Brand = 'PHD'
  GROUP BY ALL
),

phd_per_channel_max AS (
  SELECT Channel, MAX(order_date) AS max_date
  FROM phd_actual_agg
  GROUP BY Channel
),

phd_last7_avg AS (
  SELECT
    a.Brand, a.Com, a.source_channel, a.Channel,
    a.parent_sku, a.Product_Title, a.Master_Title,
    a.Main_Category, a.Sub_Category, a.Region,
    AVG(a.GMV)         AS GMV,
    AVG(a.Gross_Sales) AS Gross_Sales,
    AVG(a.Units_Sold)  AS Units_Sold
  FROM phd_actual_agg a
  INNER JOIN phd_per_channel_max m ON a.Channel = m.Channel
  WHERE a.order_date BETWEEN DATE_SUB(m.max_date, INTERVAL 6 DAY) AND m.max_date
  GROUP BY ALL
),

phd_proj_dates AS (
  SELECT
    m.Channel,
    DATE_ADD(m.max_date, INTERVAL offset DAY) AS order_date,
    offset AS days_ahead
  FROM phd_per_channel_max m,
  UNNEST(GENERATE_ARRAY(1, 60)) AS offset
  WHERE DATE_ADD(m.max_date, INTERVAL offset DAY) <= DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
),

phd_initial_projections AS (
  SELECT
    l.Brand, l.Com, l.source_channel, l.Channel, d.order_date,
    l.parent_sku, l.Product_Title, l.Master_Title,
    l.Main_Category, l.Sub_Category, l.Region,
    l.GMV, l.Gross_Sales, l.Units_Sold,
    d.days_ahead, TRUE AS is_projected
  FROM phd_last7_avg l
  INNER JOIN phd_proj_dates d ON l.Channel = d.Channel
),

phd_combined_data AS (
  SELECT
    Brand, Com, source_channel, Channel, order_date,
    parent_sku, Product_Title, Master_Title,
    Main_Category, Sub_Category, Region,
    GMV, Gross_Sales, Units_Sold,
    0 AS days_ahead, FALSE AS is_projected
  FROM phd_actual_agg

  UNION ALL

  SELECT
    Brand, Com, source_channel, Channel, order_date,
    parent_sku, Product_Title, Master_Title,
    Main_Category, Sub_Category, Region,
    GMV, Gross_Sales, Units_Sold,
    days_ahead, is_projected
  FROM phd_initial_projections
),

phd_rolling_avg AS (
  SELECT
    c1.Brand, c1.Com, c1.source_channel, c1.Channel, c1.order_date,
    c1.parent_sku, c1.Product_Title, c1.Master_Title,
    c1.Main_Category, c1.Sub_Category, c1.Region,
    CASE WHEN c1.is_projected THEN AVG(c2.GMV)         ELSE MAX(c1.GMV)         END AS GMV,
    CASE WHEN c1.is_projected THEN AVG(c2.Gross_Sales) ELSE MAX(c1.Gross_Sales) END AS Gross_Sales,
    CASE WHEN c1.is_projected THEN AVG(c2.Units_Sold)  ELSE MAX(c1.Units_Sold)  END AS Units_Sold,
    c1.is_projected
  FROM phd_combined_data c1
  LEFT JOIN phd_combined_data c2
    ON  c1.Channel      = c2.Channel
    AND c1.Product_Title = c2.Product_Title
    AND c1.Master_Title  = c2.Master_Title
    AND c1.Main_Category = c2.Main_Category
    AND c1.Sub_Category  = c2.Sub_Category
    AND c2.order_date BETWEEN DATE_SUB(c1.order_date, INTERVAL 7 DAY) AND DATE_SUB(c1.order_date, INTERVAL 1 DAY)
    AND (c2.days_ahead < c1.days_ahead OR c2.days_ahead = 0)
  GROUP BY
    c1.Brand, c1.Com, c1.source_channel, c1.Channel, c1.order_date,
    c1.parent_sku, c1.Product_Title, c1.Master_Title,
    c1.Main_Category, c1.Sub_Category, c1.Region, c1.is_projected
),

-- =========================================================
-- Final Union: PILGRIM + PHD
-- =========================================================
final_union AS (
  -- Pilgrim: rolling-avg channels (actuals + projections)
  SELECT Brand, Com, source_channel, Channel, order_date, parent_sku,
    Product_Title, Master_Title, Main_Category, Sub_Category, Region,
    GMV, Gross_Sales, Units_Sold, is_projected
  FROM pilgrim_rolling_avg

  UNION ALL

  -- Pilgrim: monthly-target channel actuals
  SELECT Brand, Com, source_channel, Channel, order_date, parent_sku,
    Product_Title, Master_Title, Main_Category, Sub_Category, Region,
    GMV, Gross_Sales, Units_Sold, is_projected
  FROM pilgrim_monthly_actuals

  UNION ALL

  -- Pilgrim: monthly-target channel projections
  SELECT Brand, Com, source_channel, Channel, order_date, parent_sku,
    Product_Title, Master_Title, Main_Category, Sub_Category, Region,
    GMV, Gross_Sales, Units_Sold, is_projected
  FROM pilgrim_monthly_daily_rows

  UNION ALL

  -- PHD: rolling-avg channels (actuals + projections)
  SELECT Brand, Com, source_channel, Channel, order_date, parent_sku,
    Product_Title, Master_Title, Main_Category, Sub_Category, Region,
    GMV, Gross_Sales, Units_Sold, is_projected
  FROM phd_rolling_avg
),

MASTER_CTE AS (
  SELECT
    Brand,
    Com,
    source_channel,
    Channel,
    DATE_TRUNC(order_date, MONTH) AS Order_date,
    MAX(order_date)               AS Maxx_date,
    parent_sku,
    Product_Title,
    Master_Title,
    Main_Category,
    Sub_Category,
    Region,
    SUM(GMV)         AS GMV,
    SUM(Gross_Sales) AS Gross_Sales,
    SUM(Units_Sold)  AS Units_Sold
  FROM final_union
  GROUP BY ALL
),

LMTD_CTE AS (
  SELECT
    Brand,
    Com,
    source_channel,
    Channel,
    DATE_TRUNC(order_date, MONTH) AS order_date,
    parent_sku,
    Product_Title,
    Master_Title,
    Main_Category,
    Sub_Category,
    Region,
    SUM(Gross_Sales) AS lmtd_gross
  FROM final_union
  WHERE
    DATE_TRUNC(order_date, MONTH) = DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH)
    AND EXTRACT(DAY FROM order_date) <= EXTRACT(DAY FROM DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
  GROUP BY ALL
),

DOM_CTE AS (
  SELECT
    a.*,
    CASE
      WHEN ROW_NUMBER() OVER (
        PARTITION BY a.order_date, a.channel, a.main_category, a.product_title
        ORDER BY a.parent_sku, a.Master_Title, a.Sub_Category
      ) = 1
      THEN b.Final_Product_Target
    END AS Final_Product_Target,
    CASE
      WHEN ROW_NUMBER() OVER (
        PARTITION BY a.order_date, a.channel, a.main_category, a.product_title
        ORDER BY a.parent_sku, a.Master_Title, a.Sub_Category
      ) = 1
      THEN SAFE_DIVIDE(
             b.Final_Product_Target,
             EXTRACT(DAY FROM LAST_DAY(a.order_date))
           )
    END AS product_target,
    c.lmtd_gross AS LMTD_Gros_Sales
  FROM MASTER_CTE AS a
  -- Target lookup: Pilgrim-only table.
  -- FIX: added "AND a.Brand = 'PILGRIM'" below. Without this, the join key
  -- (month, channel, main_category, product_title) has no brand condition,
  -- so any PHD row that happens to share the same channel + category +
  -- product_title + month as a Pilgrim target row silently inherits that
  -- Pilgrim target. This was the bug causing PHD to show non-null targets
  -- (e.g. ~1.96 Cr / ~6.3L units leaking into PHD's D2C numbers) even
  -- though there is no real target source for PHD.
  LEFT JOIN (
    SELECT
      month,
      channel,
      NULLIF(main_category, '#N/A') AS main_category,
      NULLIF(product_title,  '#N/A') AS product_title,
      SUM(Final_Product_Target) AS Final_Product_Target
    FROM `shopify-pubsub-project.Tertiary_Sales.Targer_onwards`
    GROUP BY 1, 2, 3, 4
  ) b
    ON  a.order_date   = b.month
    AND a.channel      = b.channel
    AND a.main_category = b.main_category
    AND a.product_title = b.product_title
    AND a.Brand = 'PILGRIM'   -- ** FIX: prevent cross-brand target leakage into PHD **
  LEFT JOIN LMTD_CTE c
    ON  DATE_ADD(a.order_date, INTERVAL -1 MONTH) = c.order_date
    AND a.Brand        = c.Brand          -- prevent cross-brand LMTD match
    AND a.channel      = c.channel
    AND a.parent_sku   = c.parent_sku
    AND a.Product_Title = c.Product_Title
    AND a.Master_Title  = c.Master_Title
    AND a.Main_Category = c.Main_Category
    AND a.Sub_Category  = c.Sub_Category
  WHERE a.order_date < CURRENT_DATE()
)

SELECT * FROM DOM_CTE;
