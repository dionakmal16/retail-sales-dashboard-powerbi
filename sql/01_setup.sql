/* =====================================================================
   RETAIL SALES 2022-2025  |  01 - SETUP (SQL Server, T-SQL)
   Memuat Sales_transactions_clean.csv (hasil clean_retail.py) ke RetailDB:
   staging (teks) -> tabel bertipe -> audit load -> view vw_valid_sales.

   Butuh SQL Server 2016 SP1+ (DROP IF EXISTS, CREATE OR ALTER).
   Jalankan per bagian secara berurutan di SSMS. Setiap bagian diakhiri
   query CHECK; hasilnya harus cocok sebelum lanjut ke 02_analysis.sql.
   ===================================================================== */


/* =====================================================================
   PART 0 - DATABASE
   (Skip the CREATE if you are not allowed to create databases; just USE
   a database you own.)
   ===================================================================== */
IF DB_ID('RetailDB') IS NULL CREATE DATABASE RetailDB;
GO
USE RetailDB;
GO


/* =====================================================================
   PART 1 - STAGING TABLE  (everything as text)
   WHY: loading straight into typed columns makes ONE bad value fail the
   whole load with a vague error. Staging as text always succeeds; we then
   convert in SQL, where we can see and count the failures.
   ===================================================================== */
DROP TABLE IF EXISTS dbo.stg_sales;
CREATE TABLE dbo.stg_sales (
    Transaction_ID           NVARCHAR(100) NULL,
    Order_ID                 NVARCHAR(100) NULL,
    Customer_ID              NVARCHAR(100) NULL,
    Customer_Name            NVARCHAR(100) NULL,
    Customer_Age             NVARCHAR(100) NULL,
    Customer_Gender          NVARCHAR(100) NULL,
    Customer_Segment         NVARCHAR(100) NULL,
    Order_Date               NVARCHAR(100) NULL,
    Order_Time               NVARCHAR(100) NULL,
    Sales_Channel            NVARCHAR(100) NULL,
    Store_ID                 NVARCHAR(100) NULL,
    Store_Name               NVARCHAR(100) NULL,
    Country                  NVARCHAR(100) NULL,
    Region                   NVARCHAR(100) NULL,
    City                     NVARCHAR(100) NULL,
    Product_ID               NVARCHAR(100) NULL,
    Product_Name             NVARCHAR(100) NULL,
    Product_Category         NVARCHAR(100) NULL,
    Product_Subcategory      NVARCHAR(100) NULL,
    Quantity                 NVARCHAR(100) NULL,
    Unit_Price               NVARCHAR(100) NULL,
    Discount_Percentage      NVARCHAR(100) NULL,
    Sales_Amount             NVARCHAR(100) NULL,
    Cost_Amount              NVARCHAR(100) NULL,
    Profit                   NVARCHAR(100) NULL,
    Payment_Method           NVARCHAR(100) NULL,
    Order_Status             NVARCHAR(100) NULL,
    Shipping_Method          NVARCHAR(100) NULL,
    Delivery_Days            NVARCHAR(100) NULL,
    Return_Flag              NVARCHAR(100) NULL,
    Return_Reason            NVARCHAR(100) NULL,
    Sales_Representative     NVARCHAR(100) NULL,
    Promotion_Code           NVARCHAR(100) NULL,
    Customer_Rating          NVARCHAR(100) NULL,
    Inventory_Level          NVARCHAR(100) NULL,
    Order_Year               NVARCHAR(100) NULL,
    Status_Return_Conflict   NVARCHAR(100) NULL
);
GO

/* ---------------------------------------------------------------------
   Load the CSV.
   NOTE 1: the path is on the SERVER's disk (not your laptop). If SQL Server
           runs in Docker/Linux, copy the file into the container first.
   NOTE 2: ROWTERMINATOR '0x0a' because this file uses Linux line endings.
           If you re-save the CSV in Excel it becomes Windows endings:
           change it to '0x0d0a'.
   NOTE 3: CODEPAGE 65001 = UTF-8 (needed for 'Ile-de-France' with accent).
   NO ACCESS to the server disk? Use SSMS: right-click the database >
   Tasks > Import Flat File, and import INTO dbo.stg_sales (keep all columns
   as text), then continue at PART 2.
   --------------------------------------------------------------------- */
TRUNCATE TABLE dbo.stg_sales;

BULK INSERT dbo.stg_sales
FROM 'C:\data\Sales_transactions_clean.csv'      -- <-- CHANGE THIS PATH
WITH (
    FIRSTROW        = 2,           -- skip the header row
    FIELDTERMINATOR = ',',
    ROWTERMINATOR   = '0x0d0a',
    CODEPAGE        = '65001',
    KEEPNULLS,                     -- empty field -> NULL
    TABLOCK
);
GO

-- CHECK: must return 18000
SELECT COUNT(*) AS staged_rows FROM dbo.stg_sales;
GO


/* =====================================================================
   PART 2 - TYPED TABLE (the one you will actually query)
   Constraints repeat the rules we validated in Python, so the database
   itself rejects bad data in future loads.
   TRY_CAST returns NULL instead of an error when a conversion fails; the
   NOT NULL columns then turn a silent bad value into a loud failure.
   GOTCHA: CAST('' AS INT) returns 0, not NULL! That is why every numeric
   conversion is wrapped as TRY_CAST(NULLIF(col, '') AS type).
   ===================================================================== */
DROP TABLE IF EXISTS dbo.sales_transactions;
CREATE TABLE dbo.sales_transactions (
    Transaction_ID           VARCHAR(20)    NOT NULL PRIMARY KEY,
    Order_ID                 VARCHAR(20)    NOT NULL,
    Customer_ID              VARCHAR(20)    NOT NULL,
    Customer_Name            NVARCHAR(100)  NULL,
    Customer_Age             TINYINT        NULL,
    Customer_Gender          VARCHAR(20)    NULL,
    Customer_Segment         VARCHAR(30)    NOT NULL,
    Order_Date               DATE           NOT NULL,
    Order_Time               TIME(0)        NOT NULL,
    Sales_Channel            VARCHAR(30)    NOT NULL,
    Store_ID                 VARCHAR(20)    NOT NULL,
    Store_Name               NVARCHAR(60)   NOT NULL,
    Country                  NVARCHAR(40)   NOT NULL,
    Region                   NVARCHAR(60)   NOT NULL,
    City                     NVARCHAR(40)   NOT NULL,
    Product_ID               VARCHAR(10)    NOT NULL,
    Product_Name             NVARCHAR(80)   NOT NULL,
    Product_Category         VARCHAR(40)    NOT NULL,
    Product_Subcategory      VARCHAR(40)    NOT NULL,
    Quantity                 INT            NOT NULL,
    Unit_Price               DECIMAL(10,2)  NOT NULL,
    Discount_Percentage      DECIMAL(5,2)   NOT NULL,
    Sales_Amount             DECIMAL(12,2)  NOT NULL,
    Cost_Amount              DECIMAL(12,2)  NOT NULL,
    Profit                   DECIMAL(12,2)  NOT NULL,
    Payment_Method           VARCHAR(30)    NOT NULL,
    Order_Status             VARCHAR(20)    NOT NULL,
    Shipping_Method          VARCHAR(20)    NOT NULL,
    Delivery_Days            TINYINT        NULL,
    Return_Flag              VARCHAR(3)     NOT NULL,
    Return_Reason            VARCHAR(30)    NULL,
    Sales_Representative     NVARCHAR(60)   NOT NULL,
    Promotion_Code           VARCHAR(30)    NULL,
    Customer_Rating          DECIMAL(2,1)   NULL,
    Inventory_Level          INT            NULL,
    Order_Year               SMALLINT       NOT NULL,
    Status_Return_Conflict   BIT            NOT NULL,
    CONSTRAINT CK_qty      CHECK (Quantity >= 1),
    CONSTRAINT CK_discount CHECK (Discount_Percentage BETWEEN 0 AND 30),
    CONSTRAINT CK_age      CHECK (Customer_Age BETWEEN 16 AND 100)
);
GO

INSERT INTO dbo.sales_transactions (Transaction_ID, Order_ID, Customer_ID, Customer_Name, Customer_Age, Customer_Gender, Customer_Segment, Order_Date, Order_Time, Sales_Channel, Store_ID, Store_Name, Country, Region, City, Product_ID, Product_Name, Product_Category, Product_Subcategory, Quantity, Unit_Price, Discount_Percentage, Sales_Amount, Cost_Amount, Profit, Payment_Method, Order_Status, Shipping_Method, Delivery_Days, Return_Flag, Return_Reason, Sales_Representative, Promotion_Code, Customer_Rating, Inventory_Level, Order_Year, Status_Return_Conflict)
SELECT
    NULLIF(LTRIM(RTRIM(Transaction_ID)), ''),
    NULLIF(LTRIM(RTRIM(Order_ID)), ''),
    NULLIF(LTRIM(RTRIM(Customer_ID)), ''),
    NULLIF(LTRIM(RTRIM(Customer_Name)), ''),
    TRY_CAST(NULLIF(Customer_Age, '') AS TINYINT),
    NULLIF(LTRIM(RTRIM(Customer_Gender)), ''),
    NULLIF(LTRIM(RTRIM(Customer_Segment)), ''),
    TRY_CAST(NULLIF(Order_Date, '') AS DATE),
    TRY_CAST(NULLIF(Order_Time, '') AS TIME(0)),
    NULLIF(LTRIM(RTRIM(Sales_Channel)), ''),
    NULLIF(LTRIM(RTRIM(Store_ID)), ''),
    NULLIF(LTRIM(RTRIM(Store_Name)), ''),
    NULLIF(LTRIM(RTRIM(Country)), ''),
    NULLIF(LTRIM(RTRIM(Region)), ''),
    NULLIF(LTRIM(RTRIM(City)), ''),
    NULLIF(LTRIM(RTRIM(Product_ID)), ''),
    NULLIF(LTRIM(RTRIM(Product_Name)), ''),
    NULLIF(LTRIM(RTRIM(Product_Category)), ''),
    NULLIF(LTRIM(RTRIM(Product_Subcategory)), ''),
    TRY_CAST(NULLIF(Quantity, '') AS INT),
    TRY_CAST(NULLIF(Unit_Price, '') AS DECIMAL(10,2)),
    TRY_CAST(NULLIF(Discount_Percentage, '') AS DECIMAL(5,2)),
    TRY_CAST(NULLIF(Sales_Amount, '') AS DECIMAL(12,2)),
    TRY_CAST(NULLIF(Cost_Amount, '') AS DECIMAL(12,2)),
    TRY_CAST(NULLIF(Profit, '') AS DECIMAL(12,2)),
    NULLIF(LTRIM(RTRIM(Payment_Method)), ''),
    NULLIF(LTRIM(RTRIM(Order_Status)), ''),
    NULLIF(LTRIM(RTRIM(Shipping_Method)), ''),
    TRY_CAST(NULLIF(Delivery_Days, '') AS TINYINT),
    NULLIF(LTRIM(RTRIM(Return_Flag)), ''),
    NULLIF(LTRIM(RTRIM(Return_Reason)), ''),
    NULLIF(LTRIM(RTRIM(Sales_Representative)), ''),
    NULLIF(LTRIM(RTRIM(Promotion_Code)), ''),
    TRY_CAST(NULLIF(Customer_Rating, '') AS DECIMAL(2,1)),
    TRY_CAST(NULLIF(Inventory_Level, '') AS INT),
    TRY_CAST(NULLIF(Order_Year, '') AS SMALLINT),
    CASE Status_Return_Conflict WHEN 'True' THEN 1 WHEN 'False' THEN 0 END
FROM dbo.stg_sales;
GO

-- Indexes for the queries below (date ranges, per-customer lookups)
CREATE INDEX IX_sales_order_date  ON dbo.sales_transactions (Order_Date) INCLUDE (Sales_Amount, Profit);
CREATE INDEX IX_sales_customer    ON dbo.sales_transactions (Customer_ID);
GO


/* =====================================================================
   PART 3 - LOAD AUDIT: prove nothing was lost or mangled
   ===================================================================== */
-- CHECK 3a: 18000 rows, SUM(Sales_Amount) = 8235120.21, SUM(Profit) = 1644731.70
SELECT COUNT(*) AS row_count, SUM(Sales_Amount) AS total_sales, SUM(Profit) AS total_profit
FROM dbo.sales_transactions;

-- CHECK 3b: NULL counts must be: Age 17 | Delivery_Days 95 | Inventory 198
--           Rating 3430 | Promotion_Code 9712 | Return_Reason 16127
SELECT
    SUM(CASE WHEN Customer_Age     IS NULL THEN 1 ELSE 0 END) AS null_age,
    SUM(CASE WHEN Delivery_Days    IS NULL THEN 1 ELSE 0 END) AS null_delivery,
    SUM(CASE WHEN Inventory_Level  IS NULL THEN 1 ELSE 0 END) AS null_inventory,
    SUM(CASE WHEN Customer_Rating  IS NULL THEN 1 ELSE 0 END) AS null_rating,
    SUM(CASE WHEN Promotion_Code   IS NULL THEN 1 ELSE 0 END) AS null_promo,
    SUM(CASE WHEN Return_Reason    IS NULL THEN 1 ELSE 0 END) AS null_return_reason
FROM dbo.sales_transactions;

-- CHECK 3c: values that were in the file but failed conversion (all must be 0)
SELECT 'Customer_Age' AS col, COUNT(*) AS failed
FROM dbo.stg_sales s JOIN dbo.sales_transactions t ON t.Transaction_ID = s.Transaction_ID
WHERE NULLIF(s.Customer_Age, '') IS NOT NULL AND t.Customer_Age IS NULL
UNION ALL
SELECT 'Customer_Rating', COUNT(*)
FROM dbo.stg_sales s JOIN dbo.sales_transactions t ON t.Transaction_ID = s.Transaction_ID
WHERE NULLIF(s.Customer_Rating, '') IS NOT NULL AND t.Customer_Rating IS NULL
UNION ALL
SELECT 'Delivery_Days', COUNT(*)
FROM dbo.stg_sales s JOIN dbo.sales_transactions t ON t.Transaction_ID = s.Transaction_ID
WHERE NULLIF(s.Delivery_Days, '') IS NOT NULL AND t.Delivery_Days IS NULL;
GO

-- Staging is no longer needed (uncomment to free the space)
-- DROP TABLE dbo.stg_sales;


/* =====================================================================
   PART 4 - ONE SHARED DEFINITION OF "VALID SALES"
   Cancelled orders never produced revenue, and returned orders were
   refunded. Defining this ONCE in a view keeps every report consistent.
   We use Return_Flag (not Order_Status) for returns because 276 rows
   have Return_Flag = 'Yes' but a status like 'Completed'.
   ===================================================================== */
CREATE OR ALTER VIEW dbo.vw_valid_sales AS
SELECT *
FROM dbo.sales_transactions
WHERE Order_Status <> 'Cancelled'
  AND Return_Flag  = 'No';
GO

-- CHECK: 15260 rows, SUM(Sales_Amount) = 7020519.42
SELECT COUNT(*) AS valid_rows, SUM(Sales_Amount) AS valid_sales FROM dbo.vw_valid_sales;
GO

