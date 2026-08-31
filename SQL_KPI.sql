CREATE DATABASE novacart_supply_chain;

USE novacart_supply_chain;

SHOW TABLES;

SELECT *
FROM inventory_snapshots
LIMIT 10;
SHOW TABLES;

SELECT * FROM inventory_snapshots LIMIT 10;
SELECT * FROM purchase_order LIMIT 10;
SELECT * FROM product_master LIMIT 10;
SELECT * FROM sales_demand LIMIT 10;
SELECT * FROM supplier_master LIMIT 10;
SELECT * FROM warehouse_master LIMIT 10;

SELECT COUNT(*) FROM inventory_snapshots;
SELECT COUNT(*) FROM product_master;
SELECT COUNT(*) FROM purchase_order;
SELECT COUNT(*) FROM sales_demand;
SELECT COUNT(*) FROM supplier_master;
SELECT COUNT(*) FROM warehouse_master;


-- KPI1
-- Total Inventory Value
SELECT 
	ROUND(
		SUM(Closing_stock * Unit_Cost_INR),
        2
	) AS inventory_Value
    FROM inventory_snapshots;

-- Inventory Value by Warehouse    
SELECT 
	Warehouse_ID,
    
    ROUND(
		SUM(Closing_Stock*Unit_Cost_INR),
        2
	) AS inventory_value
FROM inventory_snapshots
GROUP BY Warehouse_ID
ORDER BY Inventory_Value DESC;

-- Bckorders by warehouse
SELECT 
	warehouse_ID,
    SUM(Backorder_Qty) AS backorder_units
FROM inventory_snapshots
GROUP BY Warehouse_ID
ORDER BY backorder_units DESC;

-- Products with highest Backorders
SELECT 
	i.SKU_ID,
    p.Product_Name,
    p.Category,
    
    SUM(i.Backorder_Qty) AS backorder_units
FROM inventory_snapshots i
JOIN product_master p 
	ON i.SKU_ID=p.SKU_ID
GROUP BY
	i.SKU_ID,
    p.Product_Name,
    p.Category
ORDER BY backorder_units DESC
LIMIT 10;

-- Fill Rate by Warehouse
SELECT 
	Warehouse_ID,
    SUM(Sales_Qty) AS fulfilled_units,
    SUM(Demand_Qty) AS demand_units,
    ROUND(
		SUM(Sales_Qty)/
        NULLIF(SUM(Demand_Qty),0)
        *100,
        2
	) AS fill_rate_pct
    FROM inventory_snapshots
    GROUP BY Warehouse_ID
    ORDER BY fill_rate_pct DESC;
	
-- Lost Sales Opportunity
SELECT 
	SUM(Backorder_Qty) AS unfullfilled_units
FROM inventory_snapshots;

SELECT 
	ROUND(
		SUM(i.Backorder_Qty * p.selling_price_INR),
        2
	) AS estimated_lost_sales
    FROM inventory_snapshots i
    JOIN product_master p
		ON i.SKU_ID= p.SKU_ID;
-- Supplier Delivery Delay
SELECT
    Supplier_ID,
    Expected_Date,
    Actual_Delivery_Date,
    DATEDIFF(Actual_Delivery_Date, Expected_Date) AS delay_days
FROM purchase_order
WHERE Actual_Delivery_Date IS NOT NULL
ORDER BY Supplier_ID, delay_days DESC;
    
-- Supplier On-Time %
SELECT 
	Supplier_ID,
    COUNT(*) AS completed_orders,
    SUM(
		CASE 
			WHEN Actual_Delivery_Date<=Expected_Date
            THEN 1
            ELSE 0
		END
	) AS on_time_orders,
    ROUND(
		SUM(
			CASE 
				WHEN Actual_Delivery_Date<= Expected_Date
                THEN 1
                ELSE 0
			END 
		)/
        COUNT(*) *100,
        2
	) AS on_time_pct
FROM purchase_order
WHERE Actual_Delivery_Date IS NOT NULL
GROUP BY Supplier_ID
ORDER BY on_time_pct DESC;

-- Supplier Fill rate
SELECT
	Supplier_ID,
    SUM(Ordered_Qty) AS ordered,
    SUM(Received_Qty) AS Recieved,
    SUM(Ordered_Qty)-SUM(Received_Qty) AS Difference,
    ROUND(
		SUM(Received_Qty)/
        NULLIF (SUM(Ordered_Qty),0)
        *100,
        2
	) AS supplier_fill_rate_pct
FROM purchase_order
    WHERE Actual_Delivery_Date IS NOT NULL
    GROUP BY Supplier_ID
    ORDER BY supplier_fill_rate_pct;
    
SELECT *
FROM purchase_order;
-- OTIF Analysis
SELECT 
	Supplier_ID,
    COUNT(*) AS total_po,
    
    SUM(
		CASE 
			WHEN Actual_Delivery_Date<=Expected_Date
            AND Received_Qty>=Ordered_Qty
            THEN 1
            ELSE 0
		END
	) AS otif_orders,
    ROUND(
		SUM(
			CASE
				WHEN Actual_Delivery_Date<=Expected_Date
                AND Received_Qty>=Ordered_Qty
                THEN 1
                ELSE 0
			END
		)/
        COUNT(*)*100
	) AS otif_pct
    FROM purchase_order
    WHERE Actual_Delivery_Date IS NOT NULL 
    GROUP BY Supplier_ID
    ORDER BY otif_pct DESC;
    
-- Demand By Product
SELECT
	d.SKU_ID,
    p.product_Name,
    SUM(d.Demand_Qty) AS demand,
    SUM(d.Fulfilled_Qty) AS fullfilled
FROM sales_demand d
JOIN product_master p
	ON p.SKU_ID=d.SKU_ID
    
GROUP BY 
	d.SKU_ID,
    p.Product_Name
ORDER BY demand DESC;
SELECT *
FROM sales_demand;
    
-- Promotion vs non-Promotion Demand
SELECT 
	Promotion_Flag,
    ROUND(
		AVG(Demand_Qty),
        2
	) AS avg_demand,
	
    ROUND(
		SUM(Fulfilled_Qty)/
        NULLIF(SUM(Demand_Qty),0)
        *100,
        2
	) AS fill_rate_pct
FROM sales_demand
GROUP BY Promotion_Flag;

-- Monthly demand growth
-- Top SKU per category
-- Warehouse ranking
-- Supplier ranking
-- Stockout trends
-- Slow-moving SKUs
-- Warehouse-SKU problems

-- Monthly Demand Growth-LAG
WITH monthly_demand AS (
	SELECT
		DATE_FORMAT(Week_Start,'%Y-%m-01') AS month,
        SUM(Demand_Qty) AS total_demand
	FROM sales_demand
    GROUP BY DATE_FORMAT(Week_Start,'%Y-%m-01')
    ),
    demand_with_previous AS(
		SELECT 
			month,
            total_demand,
            LAG(total_demand) OVER (
				ORDER BY month
			) AS previous_month_demand
		FROM monthly_demand
	)
    SELECT 
		month,
		total_demand,
		previous_month_demand,
        
        ROUND(
        (total_demand-previous_month_demand)
        /
        NULLIF (previous_month_demand,0)
        *100,
        2
	) AS deamand_growth_pct
    FROM demand_with_previous
    ORDER BY month;
    
-- TOP SKU in Each Category-RANK
with sku_demand AS (
	SELECT
		p.Category,
        d.SKU_ID,
        p.Product_Name,
        SUM(d.Demand_Qty) AS total_demand
	FROM sales_demand d
    JOIN product_master p
		On d.SKU_ID=p.SKU_ID
        
	GROUP BY 
		p.Category,
        d.SKU_ID,
        p.Product_Name
	),
    ranked_products AS (
    SELECT 
		Category,
        SKU_ID,
        Product_Name,
        total_demand,
        
	RANK() OVER (
		PARTITION BY Category
        ORDER BY total_demand DESC
	) AS demand_rank
FROM sku_demand
)
SELECT * 
FROM ranked_products
WHERE demand_rank=1
ORDER BY Category;

-- Warehouse Ranking
with warehouse_performance AS (
	SELECT 
		warehouse_ID,
        SUM(Demand_Qty) AS total_demand,
        SUM(Sales_Qty)	AS total_sale,
        SUM(Backorder_Qty) AS beckorder,
        
        ROUND(
			SUM(Sales_Qty)/
            NULLIF(SUM(Demand_Qty),0)
            *100,
            2
		) AS fill_rate_pct
	FROM inventory_snapshots
    GROUP BY Warehouse_ID
)
SELECT *,
	RANK() OVER (
		ORDER BY fill_rate_pct DESC
		) AS warehouse_rank
	FROM warehouse_performance;
    
-- Supplier Ranking
WITH supplier_metrics AS(
	SELECT 
		Supplier_ID,
        
        ROUND(
			AVG(
				CASE 
					WHEN Actual_Delivery_Date<=Expected_Date
                    THEN 1
                    ELSE 0
				END
                )*100,
                2
			) AS on_time_pct,
            ROUND(
				SUM(Received_Qty)/
            NULLIF(SUM(Ordered_Qty),0)
            *100,
            2
		) AS fill_rate_pct,
        ROUND(
			AVG( 
				CASE
					WHEN Actual_Delivery_Date<=Expected_Date
                    AND Received_Qty>=Ordered_Qty
                    THEN 1
                    ELSE 0
				END
			) *100,
            2
		) AS otif_pct
        FROM purchase_order
        WHERE Actual_Delivery_Date IS NOT NULL
        GROUP BY Supplier_ID
	)
    SELECT 
    *,
    RANK() OVER(
		ORDER BY otif_pct DESC
        ) AS supplier_rank
	FROM supplier_metrics
    ORDER BY supplier_rank;
    
-- STOCKOUT TREND
SELECT 
	DATE_FORMAT(Snapshot_Date,'%Y-%m-01') AS month,
    SUM(
		CASE
			WHEN Closing_Stock=0
            THEN 1 
            ELSE 0
		END
        
	) AS stockout_records,
    ROUND(
		SUM(
			CASE
				WHEN Closing_Stock=0
                THEN 1
                ELSE 0
			END
		)
    /
    COUNT(*) *100,
    2
    ) AS stockout_rate_pct
    FROM inventory_snapshots
    GROUP BY DATE_FORMAT(Snapshot_Date,'%Y-%m-01')
    ORDER BY month;
    
-- Slow Moving SKUs
SELECT 
	i.SKU_ID,
    p.Product_Name,
    p.Category,
    SUM(i.Sales_Qty) AS total_sales,
    
    ROUND(
		AVG(i.Closing_Stock)
        * AVG(i.Unit_Cost_INR),
        2
	) AS approx_avg_inventory_value
FROM inventory_snapshots i
JOIN product_master p
	ON i.SKU_ID= p.SKU_ID
GROUP BY 
	i.SKU_ID,
    p.Product_Name,
    p.Category
ORDER BY 
	total_sales ASC;
    
-- Warehouse-SKU Problem 
SELECT
	i.Warehouse_ID,
    i.SKU_ID,
    p.Product_Name,
    p.Category,
    SUM(i.Demand_Qty) AS demand,
    SUM(i.Sales_Qty) AS sales,
    SUM(i.Backorder_Qty) As backorders,
    
    ROUND(
		SUM(i.Sales_Qty)
        /
        NULLIF(SUM(i.Demand_Qty),0)
        *100,
        2
	) AS fill_rate_pct
FROM inventory_snapshots i
JOIN product_master p
	ON i.SKU_ID= p.SKU_ID
GROUP BY 
	i.Warehouse_ID,
    i.SKU_ID,
    p.Product_Name,
    p.Category
HAVING 
	SUM(i.Backorder_Qty)>0
    
    ORDER BY 
		backorders DESC,
        fill_rate_pct ASC
LIMIT 20;


-- ROW NUMBER

WITH warehouse_sku AS (
	SELECT 
		i.Warehouse_ID,
        i.SKU_ID,
        p.Product_Name,
        SUM(i.Backorder_Qty) AS backorder
	FROM inventory_snapshots i
    JOIN product_master p
		ON i.SKU_ID=p.SKU_ID
	GROUP BY 
		i.Warehouse_ID,
        i.SKU_ID,
        p.Product_Name
	),
    ranked AS (
		SELECT 
        *,
         ROW_NUMBER() OVER(
			PARTITION BY Warehouse_ID
				ORDER BY backorder DESC
			) AS row_num
		FROM warehouse_sku
	)
	SELECT 
		Warehouse_ID,
        SKU_ID,
        Product_Name,
        backorder
	FROM ranked
    WHERE row_num=1
    ORDER BY Warehouse_ID;
-- Supplier Names

SELECT 
	po.Supplier_ID,
    s.Supplier_Name,
	
    ROUND(
		AVG(
			DATEDIFF(
				po.Actual_Delivery_Date,
                po.Expected_Date
			)
		),
        2
	) AS avg_delay_days
    FROM purchase_order po
    JOIN supplier_master s
		ON po.Supplier_ID=s.Supplier_ID
	WHERE po.Actual_Delivery_Date IS NOT NULL
    GROUP BY 
		po.Supplier_ID,
        s.Supplier_Name
	ORDER BY avg_delay_days DESC;
    
    
          
    
    
	
        
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    