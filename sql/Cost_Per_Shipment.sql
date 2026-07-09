CREATE OR REPLACE TABLE `shopify-pubsub-project.Cost_Validation.CPS` AS

WITH

easyecom AS (
  SELECT
    Order_Number,
    AWB_No,
    Packing_Material,
    SUM(Product_Weight * Suborder_Quantity) AS dead_weight_grams,
    MAX(Brand)                              AS brand,
    MAX(Payment_Mode)                       AS payment_mode,
    MAX(Order_Invoice_Amount)               AS order_invoice_value
  FROM `shopify-pubsub-project.Data_Warehouse_Easyecom_Staging.Mini_Sales_report_B2C`
  WHERE MP_Name = 'Shopify'
    AND LOWER(Brand) = 'pilgrim'
    AND AWB_No IS NOT NULL
    AND AWB_No != ''
  GROUP BY Order_Number, AWB_No, Packing_Material
),

with_tracking AS (
  SELECT
    e.Order_Number, e.AWB_No, e.Packing_Material,
    e.dead_weight_grams, e.brand, e.payment_mode, e.order_invoice_value,
    t.Drop_Pincode, t.Pickup_Pincode, t.Clickpost_Unified_Status, t.Courier_Partner
  FROM easyecom e
  INNER JOIN `shopify-pubsub-project.Data_Warehouse_ClickPost_Staging.Tracking_Master` t
    ON e.Order_Number = t.Order_ID AND e.AWB_No = t.AWB
  WHERE t.Courier_Partner IS NOT NULL
    AND t.Courier_Partner != ''
    AND t.Courier_Partner NOT IN (
      'ATS (Amazon Transportation Services)', 'PicoXpress', 'Proship B2C', 'Vamaship'
    )
),

with_partner AS (
  SELECT *,
    CASE Courier_Partner
      WHEN 'Delhivery'       THEN 'Delhivery'
      WHEN 'Shiprocket'      THEN 'Shiprocket'
      WHEN 'Elastic Run B2C' THEN 'Elastic Run'
      WHEN 'Pikndel HLD'     THEN 'Pinkdel'
      WHEN 'XpressBees'      THEN 'Xpressbee'
      ELSE NULL
    END AS rc_partner
  FROM with_tracking
),

with_zone AS (
  SELECT wp.*,
    CASE
      WHEN wp.rc_partner IN ('Pinkdel', 'Elastic Run') THEN 'A'
      ELSE z.Delivery_Zone
    END AS Delivery_Zone
  FROM with_partner wp
  LEFT JOIN `shopify-pubsub-project.Data_Warehouse_Easyecom_Staging.Partner_Zone_Mapping` z
    ON CONCAT(wp.Pickup_Pincode, '-', wp.Drop_Pincode) = z.SD_Pincode
    AND wp.rc_partner = z.partner
),

with_box AS (
  SELECT wz.*, b.Volume_Weight_gram, b.Length_cm_ AS length_cm, b.Width_cm, b.Height_cm,
    b.Dead_Weight AS box_weight
  FROM with_zone wz
  LEFT JOIN `shopify-pubsub-project.Data_Warehouse_Easyecom_Staging.Packaging_Boxs` b
    ON TRIM(wz.Packing_Material, '"') = b.Packaging_SKU
),

with_calc AS (
  SELECT wb.*,
    -- dead weight = product weights + box tare weight
    COALESCE(wb.dead_weight_grams, 0) + COALESCE(wb.box_weight, 0) AS total_dead_weight_grams,
    GREATEST(
      COALESCE(wb.Volume_Weight_gram, 0),
      COALESCE(wb.dead_weight_grams, 0) + COALESCE(wb.box_weight, 0)
    ) AS max_weight,
    CASE wb.Delivery_Zone
      WHEN 'A'  THEN 'zone_a'
      WHEN 'B'  THEN 'zone_b'
      WHEN 'C'  THEN 'zone_c'
      WHEN 'C1' THEN 'zone_c'
      WHEN 'C2' THEN 'zone_c'
      WHEN 'D'  THEN 'zone_d'
      WHEN 'D1' THEN 'zone_d'
      WHEN 'D2' THEN 'zone_d'
      WHEN 'E'  THEN 'zone_ef'
      WHEN 'F'  THEN 'zone_ef'
      ELSE NULL
    END AS zone_key,
    CASE
      WHEN wb.Clickpost_Unified_Status = 'Delivered'     THEN 'Forward'
      WHEN wb.Clickpost_Unified_Status = 'RTO-Delivered' THEN 'RTO'
      ELSE NULL
    END AS charge_type
  FROM with_box wb
),

with_slab AS (
  SELECT wc.*,
    CASE
      WHEN wc.max_weight <= 250 THEN 250
      WHEN wc.max_weight <= 500 THEN 500
      ELSE CAST(CEIL(wc.max_weight / 500.0) * 500 AS INT64)
    END AS weight_ceiling_grams,
    CASE
      WHEN wc.max_weight <= 250 THEN 250
      ELSE 500
    END AS first_weight_slab,
    CASE
      WHEN wc.rc_partner = 'Shiprocket' THEN 0
      WHEN wc.max_weight > 500 THEN CAST(CEIL(wc.max_weight / 500.0) - 1 AS INT64)
      ELSE 0
    END AS extra_slabs
  FROM with_calc wc
),

with_rates AS (
  SELECT
    ws.*,

    -- ── Forward rates (used for Delivered; also the base leg of RTO) ──
    CASE ws.zone_key
      WHEN 'zone_a'  THEN rf1.zone_a
      WHEN 'zone_b'  THEN rf1.zone_b
      WHEN 'zone_c'  THEN rf1.zone_c
      WHEN 'zone_d'  THEN rf1.zone_d
      WHEN 'zone_ef' THEN rf1.zone_ef
    END AS fwd_first_rate,
    CASE ws.zone_key
      WHEN 'zone_a'  THEN rfa.zone_a
      WHEN 'zone_b'  THEN rfa.zone_b
      WHEN 'zone_c'  THEN rfa.zone_c
      WHEN 'zone_d'  THEN rfa.zone_d
      WHEN 'zone_ef' THEN rfa.zone_ef
    END AS fwd_add_rate,

    -- ── RTO rates (return leg, added on top of forward for RTO-Delivered) ──
    CASE ws.zone_key
      WHEN 'zone_a'  THEN rr1.zone_a
      WHEN 'zone_b'  THEN rr1.zone_b
      WHEN 'zone_c'  THEN rr1.zone_c
      WHEN 'zone_d'  THEN rr1.zone_d
      WHEN 'zone_ef' THEN rr1.zone_ef
    END AS rto_first_rate,
    CASE ws.zone_key
      WHEN 'zone_a'  THEN rra.zone_a
      WHEN 'zone_b'  THEN rra.zone_b
      WHEN 'zone_c'  THEN rra.zone_c
      WHEN 'zone_d'  THEN rra.zone_d
      WHEN 'zone_ef' THEN rra.zone_ef
    END AS rto_add_rate,

    rf1.cod_flat,
    rf1.cod_pct

  FROM with_slab ws

  -- Forward: first slab
  LEFT JOIN `shopify-pubsub-project.Data_Warehouse_Easyecom_Staging.Rate_Card` rf1
    ON rf1.partner           = ws.rc_partner
    AND rf1.charge_type      = 'Forward'
    AND rf1.weight_slab_grams = ws.first_weight_slab

  -- Forward: additional slab
  LEFT JOIN `shopify-pubsub-project.Data_Warehouse_Easyecom_Staging.Rate_Card` rfa
    ON rfa.partner           = ws.rc_partner
    AND rfa.charge_type      = 'Forward'
    AND rfa.weight_slab_grams = 501

  -- RTO: first slab
  LEFT JOIN `shopify-pubsub-project.Data_Warehouse_Easyecom_Staging.Rate_Card` rr1
    ON rr1.partner           = ws.rc_partner
    AND rr1.charge_type      = 'RTO'
    AND rr1.weight_slab_grams = ws.first_weight_slab

  -- RTO: additional slab
  LEFT JOIN `shopify-pubsub-project.Data_Warehouse_Easyecom_Staging.Rate_Card` rra
    ON rra.partner           = ws.rc_partner
    AND rra.charge_type      = 'RTO'
    AND rra.weight_slab_grams = 501
)

SELECT
  Order_Number,
  AWB_No,
  brand,
  payment_mode,
  Courier_Partner,
  rc_partner                    AS Delivery_Partner,
  Clickpost_Unified_Status,
  charge_type,
  Pickup_Pincode,
  Drop_Pincode,
  Delivery_Zone,
  Packing_Material,
  ROUND(dead_weight_grams, 1)         AS product_dead_weight_grams,
  ROUND(box_weight, 1)                AS box_weight_grams,
  ROUND(total_dead_weight_grams, 1)   AS dead_weight_grams,
  Volume_Weight_gram                  AS volume_weight_grams,
  ROUND(max_weight, 1)                AS max_weight_grams,
  weight_ceiling_grams,
  extra_slabs,
  fwd_first_rate                AS first_slab_rate,
  fwd_add_rate                  AS add_slab_rate,
  rto_first_rate,
  rto_add_rate,

  -- COD applies only when shipment is Delivered (Forward), never on RTO
  CASE
    WHEN UPPER(payment_mode) = 'COD' AND charge_type = 'Forward'
      THEN ROUND(GREATEST(COALESCE(cod_flat, 0), COALESCE(order_invoice_value, 0) * COALESCE(cod_pct, 0)), 2)
    ELSE 0
  END AS cod_charge,

  -- Forward freight leg
  CASE
    WHEN charge_type IS NULL THEN NULL
    ELSE COALESCE(fwd_first_rate, 0) + (extra_slabs * COALESCE(fwd_add_rate, 0))
  END AS forward_charge,

  -- RTO freight leg (non-zero only for RTO-Delivered)
  CASE
    WHEN charge_type = 'RTO'
      THEN COALESCE(rto_first_rate, 0) + (extra_slabs * COALESCE(rto_add_rate, 0))
    ELSE 0
  END AS rto_charge,

  -- CPS = freight only (no COD)
  --   Delivered  → forward freight
  --   RTO        → forward freight + RTO freight
  CASE
    WHEN charge_type IS NULL THEN NULL
    WHEN charge_type = 'Forward'
      THEN COALESCE(fwd_first_rate, 0) + (extra_slabs * COALESCE(fwd_add_rate, 0))
    WHEN charge_type = 'RTO'
      THEN COALESCE(fwd_first_rate, 0) + (extra_slabs * COALESCE(fwd_add_rate, 0))
         + COALESCE(rto_first_rate, 0) + (extra_slabs * COALESCE(rto_add_rate, 0))
  END AS CPS,

  -- final_charge = CPS + COD
  --   Delivered  → forward freight + COD (if COD order)
  --   RTO        → forward freight + RTO freight  (no COD on returns)
  CASE
    WHEN charge_type IS NULL THEN NULL
    WHEN charge_type = 'Forward'
      THEN COALESCE(fwd_first_rate, 0) + (extra_slabs * COALESCE(fwd_add_rate, 0))
         + CASE
             WHEN UPPER(payment_mode) = 'COD'
               THEN ROUND(GREATEST(COALESCE(cod_flat, 0), COALESCE(order_invoice_value, 0) * COALESCE(cod_pct, 0)), 2)
             ELSE 0
           END
    WHEN charge_type = 'RTO'
      THEN COALESCE(fwd_first_rate, 0) + (extra_slabs * COALESCE(fwd_add_rate, 0))
         + COALESCE(rto_first_rate, 0) + (extra_slabs * COALESCE(rto_add_rate, 0))
  END AS final_charge

FROM with_rates;
