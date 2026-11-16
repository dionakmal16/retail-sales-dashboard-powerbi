/* =====================================================================
   RETAIL SALES 2022-2025  |  02 - ANALISIS EKSPLORATIF (T-SQL)
   Jalankan setelah 01_setup.sql, di database RetailDB.

   Sumber data per query:
   - dbo.vw_valid_sales     : penjualan valid (tanpa Cancelled & tanpa retur),
                              15.260 baris, total revenue 7.020.519,42
   - dbo.sales_transactions : semua transaksi (18.000 baris), dipakai
                              saat yang diukur justru retur/pembatalan

   Format setiap query:
     Pertanyaan -> Teknik -> Hasil (dijalankan di SQL Server 2025 Express)
     -> Insight
   ===================================================================== */
USE RetailDB;
GO


/* =====================================================================
   A. TREN WAKTU
   ===================================================================== */

/* ---- A1. Revenue, profit, dan margin per tahun ----------------------
   Pertanyaan : Bagaimana kinerja tiap tahun?
   Teknik     : GROUP BY; margin = SUM(Profit)/SUM(Sales), bukan rata-rata
                margin per baris (rata-rata per baris memberi bobot sama
                pada transaksi kecil dan besar).
   Hasil      : tahun | baris | revenue      | profit     | margin
                2022  | 3501  | 1.736.289,52 | 350.763,97 | 20,20%
                2023  | 3888  | 1.686.581,09 | 335.188,04 | 19,87%
                2024  | 3679  | 1.618.095,18 | 324.396,20 | 20,05%
                2025  | 4192  | 1.979.553,63 | 389.689,65 | 19,69%
   Insight    : Revenue turun 2 tahun berturut-turut lalu naik +22,3% di
                2025. Margin hampir tidak bergerak (19,7-20,2%), jadi
                kenaikan 2025 datang dari volume (+14% baris transaksi),
                bukan dari harga atau margin.                           */
SELECT Order_Year,
       COUNT(*)          AS line_items,
       SUM(Sales_Amount) AS revenue,
       SUM(Profit)       AS profit,
       ROUND(100.0 * SUM(Profit) / NULLIF(SUM(Sales_Amount), 0), 2) AS margin_pct
FROM dbo.vw_valid_sales
GROUP BY Order_Year
ORDER BY Order_Year;


/* ---- A2. Pertumbuhan YoY per bulan (2025 vs 2024) -------------------
   Pertanyaan : Apakah lonjakan 2025 merata sepanjang tahun?
   Teknik     : CTE + LAG(revenue, 12). Filter tahun diletakkan DI LUAR
                CTE kedua; kalau di WHERE yang sama dengan LAG, bulan 2024
                ikut terbuang dan hasil YoY menjadi NULL semua.
   Hasil      : Jan +23,8% | Feb +32,4% | Mar +44,8% | Apr +33,8%
                Mei +15,2% | Jun +12,5% | Jul  +3,4% | Agu +10,0%
                Sep +29,2% | Okt +37,0% | Nov  +6,4% | Des +27,0%
   Insight    : Ke-12 bulan 2025 tumbuh positif, jadi kenaikan bersifat
                menyeluruh, bukan karena satu bulan promo besar. Kenaikan
                paling kuat di Q1 (Mar +44,8%) dan Q4 (Okt +37%), paling
                lemah di Jul (+3,4%).                                   */
WITH monthly AS (
    SELECT DATEFROMPARTS(YEAR(Order_Date), MONTH(Order_Date), 1) AS month_start,
           SUM(Sales_Amount) AS revenue
    FROM dbo.vw_valid_sales
    GROUP BY DATEFROMPARTS(YEAR(Order_Date), MONTH(Order_Date), 1)
),
yoy AS (
    SELECT month_start,
           revenue,
           LAG(revenue, 12) OVER (ORDER BY month_start) AS revenue_last_year,
           ROUND(100.0 * (revenue - LAG(revenue, 12) OVER (ORDER BY month_start))
                 / NULLIF(LAG(revenue, 12) OVER (ORDER BY month_start), 0), 1) AS yoy_pct
    FROM monthly
)
SELECT *
FROM yoy
WHERE YEAR(month_start) = 2025
ORDER BY month_start;


/* ---- A3. Running total dan moving average 3 bulan -------------------
   Pertanyaan : Bagaimana tren jika fluktuasi bulanan diredam?
   Teknik     : Window frame ROWS BETWEEN ... AND CURRENT ROW.
   Hasil      : MA-3 bulan Juni vs Desember:
                2022: 147 rb -> 191 rb | 2023: 134 rb -> 184 rb
                2024: 121 rb -> 174 rb | 2025: 146 rb -> 212 rb
                Running total akhir Des 2025 = 7.020.519,42 (= total view).
   Insight    : Pola musiman berulang setiap tahun: lembah di pertengahan
                tahun, puncak di akhir tahun. Running total akhir sama
                dengan total view, jadi tidak ada bulan yang hilang.    */
WITH monthly AS (
    SELECT DATEFROMPARTS(YEAR(Order_Date), MONTH(Order_Date), 1) AS month_start,
           SUM(Sales_Amount) AS revenue
    FROM dbo.vw_valid_sales
    GROUP BY DATEFROMPARTS(YEAR(Order_Date), MONTH(Order_Date), 1)
)
SELECT month_start,
       revenue,
       SUM(revenue) OVER (ORDER BY month_start
                          ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total,
       AVG(revenue) OVER (ORDER BY month_start
                          ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)         AS moving_avg_3m
FROM monthly
ORDER BY month_start;


/* ---- A4. Musiman: kontribusi tiap bulan (gabungan 4 tahun) ----------
   Pertanyaan : Bulan apa yang paling penting untuk penjualan?
   Teknik     : SUM(...) OVER () untuk persentase dari total.
   Hasil      : Nov 11,36% | Des 11,29% | Okt 9,79% | ... | Feb 6,33% | Jan 6,13%
   Insight    : Okt-Des menyumbang 32,4% revenue setahun, sekitar 2,6x
                Jan-Feb (12,5%). Stok dan kampanye sebaiknya disiapkan sejak
                September.                                              */
WITH monthly AS (
    SELECT MONTH(Order_Date) AS month_no, SUM(Sales_Amount) AS revenue
    FROM dbo.vw_valid_sales
    GROUP BY MONTH(Order_Date)
)
SELECT month_no,
       revenue,
       ROUND(100.0 * revenue / SUM(revenue) OVER (), 2) AS share_pct
FROM monthly
ORDER BY revenue DESC;


/* ---- A5. Bulan terbaik di setiap tahun ------------------------------
   Pertanyaan : Apakah puncak penjualan selalu jatuh di bulan yang sama?
   Teknik     : ROW_NUMBER() OVER (PARTITION BY tahun ORDER BY revenue DESC).
   Hasil      : 2022 Okt (11,6% dari tahun itu) | 2023 Des (12,7%)
                2024 Nov (12,3%)                 | 2025 Des (11,4%)
   Insight    : Puncak selalu di Q4, tetapi bulannya berpindah antara
                Okt-Des. Perencanaan cukup per kuartal, tidak perlu
                bertumpu pada satu bulan.                               */
WITH monthly AS (
    SELECT Order_Year, MONTH(Order_Date) AS month_no, SUM(Sales_Amount) AS revenue
    FROM dbo.vw_valid_sales
    GROUP BY Order_Year, MONTH(Order_Date)
),
ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY Order_Year ORDER BY revenue DESC) AS rn,
           ROUND(100.0 * revenue / SUM(revenue) OVER (PARTITION BY Order_Year), 1) AS share_of_year
    FROM monthly
)
SELECT Order_Year, month_no, revenue, share_of_year
FROM ranked
WHERE rn = 1
ORDER BY Order_Year;


/* =====================================================================
   B. PRODUK
   ===================================================================== */

/* ---- B1. Margin per kategori produk ---------------------------------
   Pertanyaan : Kategori mana yang paling menguntungkan?
   Teknik     : Rasio dari total + NULLIF untuk mencegah bagi nol.
   Hasil      : Appliances 22,06% | Furniture 21,11%
                Office Supplies 19,36% | Electronics 19,30%
   Insight    : Electronics menyumbang 59,6% revenue (4,18 jt) tetapi
                marginnya terendah. Appliances paling efisien namun hanya
                7% revenue. Ada ruang untuk mendorong Appliances.       */
SELECT Product_Category,
       SUM(Sales_Amount) AS revenue,
       SUM(Profit)       AS profit,
       ROUND(100.0 * SUM(Profit) / NULLIF(SUM(Sales_Amount), 0), 2) AS margin_pct
FROM dbo.vw_valid_sales
GROUP BY Product_Category
ORDER BY margin_pct DESC;


/* ---- B2. Top 3 produk di setiap kategori ----------------------------
   Pertanyaan : Produk apa yang menopang tiap kategori?
   Teknik     : RANK() OVER (PARTITION BY ...) di dalam CTE, lalu filter.
   Hasil      : Electronics  : ProBook 16 (1,18 jt; 28,1%), AeroBook 14 (1,16 jt; 27,7%)
                Furniture    : Standing Desk 29,3%, Meeting Table 27,4%
                Office Supp. : Printer Plus 34,8%, Laser Toner 27,1%
                Appliances   : Air Purifier 41,8%, Coffee Machine 28,5%
   Insight    : Di Electronics, dua laptop saja = 55,8% revenue kategori.
                Ketergantungan tertinggi ada di Appliances: Air Purifier
                41,8%. Gangguan stok pada produk ini paling berisiko.   */
WITH product_rev AS (
    SELECT Product_Category, Product_Name, SUM(Sales_Amount) AS revenue
    FROM dbo.vw_valid_sales
    GROUP BY Product_Category, Product_Name
),
ranked AS (
    SELECT *,
           RANK() OVER (PARTITION BY Product_Category ORDER BY revenue DESC) AS rnk,
           ROUND(100.0 * revenue / SUM(revenue) OVER (PARTITION BY Product_Category), 1) AS share_in_category
    FROM product_rev
)
SELECT Product_Category, rnk, Product_Name, revenue, share_in_category
FROM ranked
WHERE rnk <= 3
ORDER BY Product_Category, rnk;


/* =====================================================================
   C. PROMOSI
   ===================================================================== */

/* ---- C1. Efektivitas kode promo -------------------------------------
   Pertanyaan : Apakah kode promo menaikkan penjualan dengan mengorbankan margin?
   Teknik     : COALESCE untuk memberi label pada NULL.
   Hasil      : (no promo) 8.258 baris, diskon rata-rata 6,3%, margin 19,97%
                HOLIDAY20 6,2% / 19,62% | BLACKFRIDAY25 6,2% / 20,03%
                ... semua kode: diskon rata-rata 5,9-6,5%, margin 19,3-20,9%
   Insight    : Kode promo TIDAK berbeda dari transaksi tanpa promo:
                diskon rata-rata "HOLIDAY20" hanya 6,2%, bukan 20%. Jadi
                kolom Promotion_Code tidak mencerminkan diskon yang
                diberikan (lihat C2). Analisis diskon di dashboard memakai
                Discount_Percentage, bukan kode promo.                  */
SELECT COALESCE(Promotion_Code, '(no promo)') AS promo,
       COUNT(*)                               AS line_items,
       ROUND(AVG(Discount_Percentage), 1)     AS avg_discount_pct,
       SUM(Sales_Amount)                      AS revenue,
       ROUND(100.0 * SUM(Profit) / NULLIF(SUM(Sales_Amount), 0), 2) AS margin_pct
FROM dbo.vw_valid_sales
GROUP BY COALESCE(Promotion_Code, '(no promo)')
ORDER BY revenue DESC;


/* ---- C2. Cek kualitas data: transaksi promo tanpa diskon ------------
   Pertanyaan : Seberapa sering kode promo dipakai tanpa diskon sama sekali?
   Teknik     : Conditional aggregation.
   Hasil      : 7.002 baris berkode promo, 2.949 di antaranya diskon 0% (42,1%).
   Insight    : Hampir separuh transaksi "promo" tidak mendapat potongan.
                Ini temuan kualitas data yang perlu ditanyakan ke tim
                terkait (pencatatan kampanye vs harga di kasir), bukan
                bukti bahwa promo berhasil atau gagal.                  */
SELECT COUNT(*) AS promo_lines,
       SUM(CASE WHEN Discount_Percentage = 0 THEN 1 ELSE 0 END) AS promo_zero_discount,
       ROUND(100.0 * SUM(CASE WHEN Discount_Percentage = 0 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_zero_discount
FROM dbo.vw_valid_sales
WHERE Promotion_Code IS NOT NULL;


/* =====================================================================
   D. CHANNEL, TOKO, DAN PELANGGAN
   ===================================================================== */

/* ---- D1. Revenue per channel ----------------------------------------
   Pertanyaan : Channel mana yang terbesar?
   Teknik     : Persentase dari total dengan SUM(SUM(...)) OVER ().
   Hasil      : Online 2,63 jt (37,4%) | Retail Store 2,08 jt (29,6%)
                B2B Portal 1,84 jt (26,2%) | Phone Order 0,48 jt (6,8%)
   Insight    : Online adalah channel terbesar. B2B Portal berada di
                urutan 3 dari sisi revenue, tetapi nilai per order-nya
                sekitar 2,5x channel lain (lihat dashboard halaman 4).  */
SELECT Sales_Channel,
       SUM(Sales_Amount) AS revenue,
       ROUND(100.0 * SUM(Sales_Amount) / SUM(SUM(Sales_Amount)) OVER (), 1) AS share_pct
FROM dbo.vw_valid_sales
GROUP BY Sales_Channel
ORDER BY revenue DESC;


/* ---- D2. Revenue channel per tahun (pivot) --------------------------
   Pertanyaan : Channel mana yang mendorong kenaikan 2025?
   Teknik     : Pivot dengan conditional aggregation.
   Hasil      : 2024 -> 2025: Online +17,2% | Retail Store +24,3%
                B2B Portal +29,7% | Phone Order +16,3%
   Insight    : Semua channel naik di 2025. B2B Portal tumbuh paling cepat
                setelah 2 tahun turun (483 rb -> 414 rb -> 410 rb -> 532 rb). */
SELECT Sales_Channel,
       SUM(CASE WHEN Order_Year = 2022 THEN Sales_Amount ELSE 0 END) AS y2022,
       SUM(CASE WHEN Order_Year = 2023 THEN Sales_Amount ELSE 0 END) AS y2023,
       SUM(CASE WHEN Order_Year = 2024 THEN Sales_Amount ELSE 0 END) AS y2024,
       SUM(CASE WHEN Order_Year = 2025 THEN Sales_Amount ELSE 0 END) AS y2025,
       SUM(Sales_Amount)                                             AS total
FROM dbo.vw_valid_sales
GROUP BY Sales_Channel
ORDER BY total DESC;


/* ---- D3. Toko terbaik di setiap negara ------------------------------
   Pertanyaan : Toko mana yang paling kuat di setiap negara?
   Teknik     : RANK() OVER (PARTITION BY Country) + jumlah toko per negara.
   Hasil      : US Los Angeles Downtown 855 rb (28,8% dari 4 toko)
                UK London City 733 rb (64,9% dari 2 toko)
                Kanada Toronto Central 57,2% | Jerman Munich Zentrum 61,2%
                Prancis & Australia hanya punya 1 toko (100%).
   Insight    : Di negara dengan 2 toko, satu toko menguasai ~60% revenue.
                Prancis dan Australia bergantung penuh pada satu toko.  */
WITH store_rev AS (
    SELECT Country, Store_Name, SUM(Sales_Amount) AS revenue
    FROM dbo.vw_valid_sales
    GROUP BY Country, Store_Name
),
ranked AS (
    SELECT *,
           RANK()  OVER (PARTITION BY Country ORDER BY revenue DESC) AS rnk,
           COUNT(*) OVER (PARTITION BY Country)                      AS stores_in_country,
           ROUND(100.0 * revenue / SUM(revenue) OVER (PARTITION BY Country), 1) AS share_in_country
    FROM store_rev
)
SELECT Country, Store_Name, revenue, stores_in_country, share_in_country
FROM ranked
WHERE rnk = 1
ORDER BY revenue DESC;


/* ---- D4. Pelanggan one-time vs repeat -------------------------------
   Pertanyaan : Seberapa penting pelanggan yang kembali?
   Teknik     : COUNT(DISTINCT Order_ID), karena satu order bisa berisi
                beberapa baris; lalu mengelompokkan hasil yang sudah
                dikelompokkan.
   Hasil      : Repeat   3.342 pelanggan | 6,47 jt (92,1%) | rata-rata 1.934,52
                One-time 1.332 pelanggan | 0,56 jt  (7,9%) | rata-rata   416,93
   Insight    : 71% pelanggan adalah repeat dan mereka menghasilkan 92%
                revenue, dengan belanja per pelanggan 4,6x lipat.
                Retensi jauh lebih bernilai daripada akuisisi.          */
WITH customer AS (
    SELECT Customer_ID,
           COUNT(DISTINCT Order_ID) AS orders,
           SUM(Sales_Amount)        AS spend
    FROM dbo.vw_valid_sales
    GROUP BY Customer_ID
)
SELECT CASE WHEN orders = 1 THEN 'One-time' ELSE 'Repeat' END AS customer_type,
       COUNT(*)             AS customers,
       SUM(spend)           AS total_spend,
       ROUND(AVG(spend), 2) AS avg_spend_per_customer,
       ROUND(100.0 * SUM(spend) / SUM(SUM(spend)) OVER (), 1) AS spend_share_pct
FROM customer
GROUP BY CASE WHEN orders = 1 THEN 'One-time' ELSE 'Repeat' END;


/* ---- D5. Margin per kombinasi segmen x channel ----------------------
   Pertanyaan : Kombinasi mana yang marginnya paling rendah, dan apakah
                sampelnya cukup besar untuk dipercaya?
   Teknik     : GROUP BY dua dimensi + COUNT(*) sebagai ukuran sampel.
   Hasil      : Terendah: Corporate x B2B Portal 17,84% (217 baris)
                          Corporate x Phone Order 17,90% (154 baris)
                Tertinggi: Premium x B2B Portal 21,70% (hanya 75 baris)
                Per segmen: Corporate diskon rata-rata 7,68%, margin 18,32%
                            Premium   diskon rata-rata 5,67%, margin 21,05%
   Insight    : Semua kombinasi Corporate berada di posisi terbawah,
                sejalan dengan diskon rata-rata Corporate yang tertinggi.
                Jadi masalahnya ada di segmen, bukan channel. Angka
                tertinggi (Premium x B2B, n=75) terlalu kecil untuk
                dijadikan kesimpulan.                                   */
SELECT Customer_Segment,
       Sales_Channel,
       COUNT(*)          AS line_items,
       SUM(Sales_Amount) AS revenue,
       ROUND(100.0 * SUM(Profit) / NULLIF(SUM(Sales_Amount), 0), 2) AS margin_pct
FROM dbo.vw_valid_sales
GROUP BY Customer_Segment, Sales_Channel
ORDER BY margin_pct ASC;

-- Pendukung D5: diskon rata-rata dan margin per segmen
SELECT Customer_Segment,
       COUNT(*)                           AS line_items,
       ROUND(AVG(Discount_Percentage), 2) AS avg_discount_pct,
       ROUND(100.0 * SUM(Profit) / NULLIF(SUM(Sales_Amount), 0), 2) AS margin_pct
FROM dbo.vw_valid_sales
GROUP BY Customer_Segment
ORDER BY margin_pct;


/* =====================================================================
   E. RETUR, OPERASIONAL, DAN KUALITAS DATA
   ===================================================================== */

/* ---- E1. Return rate per kategori -----------------------------------
   Pertanyaan : Kategori mana yang paling sering diretur?
   Teknik     : Conditional aggregation (CASE di dalam SUM). Memakai SEMUA
                transaksi, karena retur justru yang sedang diukur.
   Hasil      : Appliances 11,99% (238/1.985) | Electronics 10,37%
                Furniture 10,20% | Office Supplies 9,92%
   Insight    : Appliances memiliki return rate tertinggi sekaligus margin
                tertinggi (B1). Menekan retur Appliances adalah peluang
                profit yang paling jelas.                               */
SELECT Product_Category,
       COUNT(*) AS line_items,
       SUM(CASE WHEN Return_Flag = 'Yes' THEN 1 ELSE 0 END) AS returned,
       ROUND(100.0 * SUM(CASE WHEN Return_Flag = 'Yes' THEN 1 ELSE 0 END) / COUNT(*), 2) AS return_rate_pct
FROM dbo.sales_transactions
GROUP BY Product_Category
ORDER BY return_rate_pct DESC;


/* ---- E2. Apakah pengiriman lambat menurunkan rating? ----------------
   Pertanyaan : Apakah lama pengiriman memengaruhi kepuasan pelanggan?
   Teknik     : AVG mengabaikan NULL; selalu tampilkan ukuran sampel (n).
   Hasil      : 0 hari 4,00 (n=5.658) | 4 hari 4,02 | 6 hari 3,93
                8 hari 3,89 (n=114)    | 10 hari 5,00 (n=1)
   Insight    : Rating datar di kisaran 3,9-4,0 untuk semua durasi.
                Nilai 5,0 pada 10 hari hanya berasal dari 1 rating, jadi
                itu noise, bukan temuan. Kecepatan kirim tidak terbukti
                memengaruhi rating di data ini.                         */
SELECT Delivery_Days,
       COUNT(Customer_Rating)                        AS n_ratings,
       ROUND(AVG(CAST(Customer_Rating AS FLOAT)), 2) AS avg_rating
FROM dbo.sales_transactions
WHERE Delivery_Days IS NOT NULL
GROUP BY Delivery_Days
ORDER BY Delivery_Days;


/* ---- E3. Konflik status vs retur ------------------------------------
   Pertanyaan : Seberapa besar inkonsistensi antara Order_Status dan
                Return_Flag (ditandai oleh clean_retail.py)?
   Teknik     : GROUP BY ROLLUP untuk subtotal.
   Hasil      : Total 276 = Completed 182 | Shipped 39 | Processing 29 | Cancelled 26
   Insight    : 182 order berstatus Completed padahal diretur. Inilah
                alasan retur diukur dari Return_Flag, bukan Order_Status.
                Jika memakai Order_Status, retur akan terhitung kurang.  */
SELECT COALESCE(Order_Status, '(total)') AS order_status,
       COUNT(*)                          AS conflict_rows
FROM dbo.sales_transactions
WHERE Status_Return_Conflict = 1
GROUP BY ROLLUP (Order_Status)
ORDER BY conflict_rows DESC;
