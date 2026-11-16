"""
Retail transactions - step-by-step data cleaning
=================================================
Run from the folder that contains the CSV:
    python clean_retail.py

Order of operations (each step makes the next one safer):
  1. Duplicates          -> so nothing is double counted in later checks
  2. Data types          -> so comparisons and math behave
  3. Text consistency    -> so "paypal" and "PayPal" are one category
  4. Impossible values   -> fix what the evidence lets us fix
  5. Missing values      -> recover what is recoverable, leave the rest honest
  6. Calculated columns  -> recompute Sales / Profit from trusted inputs
  7. Logic conflicts     -> flag (don't silently "fix") contradictions
  8. Validation          -> prove the result with assertions
"""
import pandas as pd
import numpy as np

RAW = "Sales_transactions_2022_2025.csv"
OUT = "Sales_transactions_clean.csv"


def step(title):
    print(f"\n{'=' * 72}\n{title}\n{'=' * 72}")


df = pd.read_csv(RAW)
print(f"Loaded {RAW}: {df.shape[0]:,} rows x {df.shape[1]} columns")

# ---------------------------------------------------------------------------
# STEP 1 - Duplicates
# WHY FIRST: duplicates inflate every count and sum, and they also bias the
# "most common value" logic we use for recovery in later steps.
# ---------------------------------------------------------------------------
step("STEP 1 - Remove duplicate rows")
before = len(df)
df = df.drop_duplicates().reset_index(drop=True)
print(f"Removed {before - len(df)} exact duplicate rows ({before:,} -> {len(df):,})")
assert df["Transaction_ID"].is_unique, "Transaction_ID should now be unique"

# ---------------------------------------------------------------------------
# STEP 2 - Data types
# WHY: dates stored as text can't be sorted/grouped by month; columns with
# missing values load as float (28.0) even when they are really whole numbers.
# 'Int64' (capital I) is pandas' nullable integer: keeps 28 AND allows <NA>.
# ---------------------------------------------------------------------------
step("STEP 2 - Fix data types")
df["Order_Date"] = pd.to_datetime(df["Order_Date"], errors="coerce")
assert df["Order_Date"].notna().all(), "unparseable dates found"
for col in ["Customer_Age", "Delivery_Days", "Inventory_Level"]:
    df[col] = df[col].astype("Int64")
print("Order_Date -> datetime; Customer_Age, Delivery_Days, Inventory_Level -> Int64")

# ---------------------------------------------------------------------------
# STEP 3 - Text consistency
# WHY: Python treats 'paypal', 'PayPal' and ' PayPal' as three categories, which
# silently splits your group-by results.
# TECHNIQUE: build a "key" (lowercase, no spaces/hyphens), group spellings that
# share a key, and keep the most frequent spelling as the canonical one.
# Abbreviations that produce a DIFFERENT key (NRW) need a manual mapping.
# ---------------------------------------------------------------------------
step("STEP 3 - Standardize text categories")
df["Region"] = df["Region"].replace({"NRW": "North Rhine-Westphalia"})


def standardize(series):
    s = series.str.strip().str.replace(r"\s+", " ", regex=True)
    key = s.str.lower().str.replace(r"[\s\-_]", "", regex=True)
    tmp = pd.DataFrame({"raw": s, "key": key}).dropna()
    canon = tmp.groupby("key")["raw"].agg(lambda x: x.value_counts().idxmax())
    return key.map(canon)


text_cols = ["Customer_Name", "Customer_Gender", "Customer_Segment", "Sales_Channel",
             "Store_ID", "Store_Name", "Country", "Region", "City", "Product_ID",
             "Product_Name", "Product_Category", "Product_Subcategory", "Payment_Method",
             "Order_Status", "Shipping_Method", "Return_Flag", "Return_Reason",
             "Promotion_Code", "Sales_Representative"]
for col in text_cols:
    n_before = df[col].nunique()
    df[col] = standardize(df[col])
    n_after = df[col].nunique()
    if n_before != n_after:
        print(f"{col:<22} {n_before:>3} distinct values -> {n_after:>3}")

# ---------------------------------------------------------------------------
# STEP 4 - Impossible values
# WHY: before deleting or imputing, ask "which column is lying?". Here the
# evidence (see investigation) showed Sales_Amount is trustworthy for the rows
# below, so the OTHER columns can be reconstructed from it.
# ---------------------------------------------------------------------------
step("STEP 4 - Fix impossible values")

# 4a. Ages: shoppers outside 16-100 are errors. Set to missing (fixed in step 5
# from the same customer's other transactions, where possible).
bad_age = ((df["Customer_Age"] < 16) | (df["Customer_Age"] > 100)).fillna(False).astype(bool)
print(f"Impossible ages set to missing: {bad_age.sum()}  (values: {df.loc[bad_age, 'Customer_Age'].tolist()})")
df.loc[bad_age, "Customer_Age"] = pd.NA

# 4b. Unit_Price with 3 decimals = decimal point slipped (price is 10x too small)
decimals = df["Unit_Price"].map(lambda x: len(str(x).split(".")[-1]))
bad_price = decimals > 2
print(f"Unit_Price with decimal-shift errors: {bad_price.sum()} -> multiplied by 10")
df.loc[bad_price, "Unit_Price"] = (df.loc[bad_price, "Unit_Price"] * 10).round(2)

# 4c. Discounts: the business only uses 0-30% in steps of 5. Anything else
# (45, 60, 110) is rebuilt from what the customer actually paid.
valid_discounts = [0, 5, 10, 15, 20, 25, 30]
bad_disc = ~df["Discount_Percentage"].isin(valid_discounts)
implied = (1 - df["Sales_Amount"] / (df["Quantity"] * df["Unit_Price"])) * 100
print(f"Invalid discounts: {bad_disc.sum()} {df.loc[bad_disc, 'Discount_Percentage'].tolist()}"
      f" -> implied from Sales: {((implied[bad_disc] / 5).round() * 5).tolist()}")
df.loc[bad_disc, "Discount_Percentage"] = (implied[bad_disc] / 5).round() * 5

# 4d. Quantity <= 0 is impossible for a sale. Rebuild from Sales / net price.
bad_qty = df["Quantity"] <= 0
implied_qty = df["Sales_Amount"] / (df["Unit_Price"] * (1 - df["Discount_Percentage"] / 100))
print(f"Quantity <= 0: {bad_qty.sum()} {df.loc[bad_qty, 'Quantity'].tolist()}"
      f" -> implied: {implied_qty[bad_qty].round(2).tolist()}")
df.loc[bad_qty, "Quantity"] = implied_qty[bad_qty].round().astype(int)

# ---------------------------------------------------------------------------
# STEP 5 - Missing values
# RULE OF THUMB: recover when a reliable rule exists, otherwise leave it
# missing. Inventing a value (e.g. filling age with the mean) fakes precision.
# ---------------------------------------------------------------------------
step("STEP 5 - Handle missing values")

# 5a. Product_Name: Product_ID <-> Product_Name is 1-to-1, so look it up
name_map = df.dropna(subset=["Product_Name"]).drop_duplicates("Product_ID").set_index("Product_ID")["Product_Name"]
n = df["Product_Name"].isna().sum()
df["Product_Name"] = df["Product_Name"].fillna(df["Product_ID"].map(name_map))
print(f"Product_Name       : recovered {n - df['Product_Name'].isna().sum()} of {n} via Product_ID")


# 5b. Customer attributes are stable per customer, so borrow from their other rows
def fill_from_customer(col):
    known = df.dropna(subset=[col]).groupby("Customer_ID")[col].agg(lambda s: s.mode().iloc[0])
    fill = df["Customer_ID"].map(known)
    if str(df[col].dtype) == "Int64":
        fill = fill.astype("Int64")
    n = df[col].isna().sum()
    df[col] = df[col].fillna(fill)
    print(f"{col:<19}: recovered {n - df[col].isna().sum()} of {n} via Customer_ID")


for col in ["Customer_Name", "Customer_Gender", "Customer_Age"]:
    fill_from_customer(col)

# 5c. Payment_Method has no recovery rule -> label honestly instead of guessing
n = df["Payment_Method"].isna().sum()
df["Payment_Method"] = df["Payment_Method"].fillna("Unknown")
print(f"Payment_Method     : {n} labelled 'Unknown'")

# 5d. Delivery_Days: Pickup orders have no delivery, so 0 is a known rule
m = df["Delivery_Days"].isna() & (df["Shipping_Method"] == "Pickup")
df.loc[m, "Delivery_Days"] = 0
print(f"Delivery_Days      : {m.sum()} Pickup orders set to 0")

print("\nIntentionally left missing (no safe rule):")
print("  Customer_Rating (customer simply didn't rate), Inventory_Level, remaining Delivery_Days,")
print("  and any Customer_Age/Name/Gender for single-purchase customers.")

# ---------------------------------------------------------------------------
# STEP 6 - Calculated columns
# FINDING: when Sales_Amount disagreed with Qty x Price x (1 - Discount),
# Profit matched the *expected* sales in 66 of 70 cases, so Sales was the
# corrupted field. Profit is then recomputed as Sales - Cost.
# ---------------------------------------------------------------------------
step("STEP 6 - Recompute Sales_Amount and Profit")


def sales_expected_and_tolerance(d):
    """Expected sales plus the rounding error we should tolerate.

    Unit_Price is stored rounded to cents (+/-0.005). That error is multiplied
    by Quantity, so healthy rows with big quantities legitimately differ by a
    few cents. A flat 0.02 tolerance wrongly flags ~500 healthy rows, and
    "fixing" them would then break Profit. Tolerance must scale with quantity.
    """
    net = d["Quantity"] * d["Unit_Price"] * (1 - d["Discount_Percentage"] / 100)
    tol = 0.005 * d["Quantity"] * (1 - d["Discount_Percentage"] / 100) + 0.011
    return net, tol


net_expected, tol = sales_expected_and_tolerance(df)
bad_sales = (df["Sales_Amount"] - net_expected).abs() > tol
print(f"Sales_Amount genuinely inconsistent with its inputs: {bad_sales.sum()} rows -> recomputed")
df.loc[bad_sales, "Sales_Amount"] = net_expected[bad_sales].round(2)

PROFIT_TOL = 0.025  # three cent-rounded columns -> legit noise <= ~0.02


def profit_gap(d):
    """Absolute gap between recorded Profit and Sales - Cost.
    The SAME test is used to find problems here and to verify in Step 8."""
    return (d["Profit"] - (d["Sales_Amount"] - d["Cost_Amount"])).abs()


bad_profit = profit_gap(df) > PROFIT_TOL
print(f"Profit != Sales - Cost: {bad_profit.sum()} rows -> recomputed")
df.loc[bad_profit, "Profit"] = (df.loc[bad_profit, "Sales_Amount"] - df.loc[bad_profit, "Cost_Amount"]).round(2)

print(f"Negative-profit rows remaining: {(df['Profit'] < 0).sum()} "
      "(kept: heavy discounts can genuinely cause losses)")

# ---------------------------------------------------------------------------
# STEP 7 - Logic conflicts
# Some orders have Return_Flag = Yes but a status like 'Completed'. We can't
# know which column is right, so we FLAG instead of overwriting. Analysts can
# then decide per question (e.g. use Return_Flag for return-rate analysis).
# ---------------------------------------------------------------------------
step("STEP 7 - Flag contradictions")
df["Status_Return_Conflict"] = (df["Return_Flag"] == "Yes") & (df["Order_Status"] != "Returned")
print(f"Return_Flag = Yes but Order_Status != Returned: {df['Status_Return_Conflict'].sum()} rows flagged")

# ---------------------------------------------------------------------------
# STEP 8 - Validation: if any assertion fails, the cleaning isn't done.
# ---------------------------------------------------------------------------
step("STEP 8 - Validate")
net_expected, tol = sales_expected_and_tolerance(df)
checks = {
    "Transaction_ID unique": df["Transaction_ID"].is_unique,
    "Quantity >= 1": (df["Quantity"] >= 1).all(),
    "Discounts only 0-30% in 5s": df["Discount_Percentage"].isin(valid_discounts).all(),
    "Ages within 16-100 (or missing)": df["Customer_Age"].dropna().between(16, 100).all(),
    "Sales = Qty x Price x (1-Disc)": ((df["Sales_Amount"] - net_expected).abs() <= tol).all(),
    "Profit = Sales - Cost": (profit_gap(df) <= PROFIT_TOL).all(),
    "Product_Name has no nulls": df["Product_Name"].notna().all(),
}
for name, ok in checks.items():
    print(f"  [{'PASS' if ok else 'FAIL'}] {name}")
assert all(checks.values()), "Validation failed"

print("\nDistinct values after cleaning:")
for col in ["Customer_Gender", "Payment_Method", "Order_Status", "Product_Category", "Region", "City"]:
    print(f"  {col:<17} {df[col].nunique():>2}: {sorted(df[col].dropna().unique())}")

print("\nRemaining missing values:")
nulls = df.isna().sum()
print(nulls[nulls > 0].to_string())

df.to_csv(OUT, index=False)
print(f"\nSaved {len(df):,} clean rows to {OUT}")
