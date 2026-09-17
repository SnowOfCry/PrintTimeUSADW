"""
Generate a small, referentially-consistent synthetic dataset for PrintTimeUSA
and load it directly into Databricks bronze (no local OLTP/DW needed).

- Amounts reconcile: invoice.subtotal = sum(line_total); tax = subtotal*rate;
  total = subtotal - discount + tax + fee; paid = sum(cleared payments);
  balance = total - paid. Statuses follow paid/partial/open/void.
- Valid FKs across customer/store/employee/product/invoice/line/payment/etc.

Usage: python gen_sample_data.py <repo_root>
"""
import os, sys, random, datetime as dt
from decimal import Decimal, ROUND_HALF_UP
from dotenv import load_dotenv
from databricks import sql

random.seed(42)
repo = sys.argv[1]
load_dotenv(os.path.join(repo, ".env"))

# ---------- SQL literal helpers ----------
class D(str): pass          # date
class T(str): pass          # timestamp

def q(s):
    return "'" + str(s).replace("'", "''") + "'"

def fmt(v):
    if v is None: return "NULL"
    if isinstance(v, bool): return "true" if v else "false"
    if isinstance(v, D): return "DATE" + q(v)
    if isinstance(v, T): return "TIMESTAMP" + q(v)
    if isinstance(v, (int, float, Decimal)): return str(v)
    return q(v)

def money(x):
    return Decimal(str(x)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)

NOW = T("2025-07-01 00:00:00")
META = ["bronze_record_id", "bronze_batch_id", "bronze_loaded_at_timestamp",
        "bronze_source_system", "bronze_source_table_name", "bronze_is_deleted_flag"]

conn = sql.connect(server_hostname=os.environ["DBRICKS_HOST"],
                   http_path=os.environ["DBRICKS_HTTP_PATH"],
                   access_token=os.environ["DBRICKS_TOKEN"])
cur = conn.cursor()

def load(table, cols, rows, system="oltp"):
    allcols = cols + META
    cur.execute(f"truncate table printtime_dw.bronze.{table}")
    vals = []
    for i, r in enumerate(rows, start=1):
        line = [fmt(v) for v in r] + [str(i), "1", fmt(NOW), q(system), q(table), "false"]
        vals.append("(" + ",".join(line) + ")")
    for j in range(0, len(vals), 300):
        cur.execute(f"insert into printtime_dw.bronze.{table} ({','.join(allcols)}) "
                    f"values " + ",".join(vals[j:j+300]))
    print(f"  {table}: {len(rows)} rows")

def d(y, m, day): return D(f"{y:04d}-{m:02d}-{day:02d}")
def ts(dd): return T(str(dd) + " 12:00:00")
CT = ["created_at_source_timestamp", "updated_at_source_timestamp"]
def cu(created): return [ts(created), ts(created)]   # created + updated timestamps

# ===================== REFERENCE DATA =====================
STATES = [("TX","Texas"),("CA","California"),("NY","New York"),("FL","Florida"),
          ("IL","Illinois"),("WA","Washington"),("GA","Georgia"),("AZ","Arizona")]
load("ref_state", ["state_code","state_name"]+CT,
     [[c, n]+cu(d(2020,1,1)) for c, n in STATES], system="reference")

TAX = [(1,"TX-STD","Texas standard",Decimal("0.0825")),
       (2,"CA-STD","California standard",Decimal("0.0725")),
       (3,"NY-STD","New York standard",Decimal("0.0400"))]
load("ref_tax_rate",
     ["tax_rate_id","tax_code","description","rate_pct","effective_from","effective_to","is_active_flag"]+CT,
     [[i,c,desc,r,d(2020,1,1),None,True]+cu(d(2020,1,1)) for i,c,desc,r in TAX], system="reference")

PM = [(1,"CASH","Cash","cash",False),(2,"VISA","Visa","card",True),
      (3,"MC","Mastercard","card",True),(4,"AMEX","Amex","card",True),
      (5,"CHECK","Check","check",False),(6,"ACH","ACH Transfer","ach",False)]
load("ref_payment_method",
     ["payment_method_id","method_code","method_name","method_type","is_card_flag","is_active_flag"]+CT,
     [[i,c,n,t,card,True]+cu(d(2020,1,1)) for i,c,n,t,card in PM], system="reference")

PT = [(1,"SALE","Sale","Customer payment for a sale",True),
      (2,"REFUND","Refund","Money returned to customer",True),
      (3,"DEPOSIT","Deposit","Upfront deposit",True)]
load("ref_payment_type",
     ["payment_type_id","type_code","type_name","description","affects_balance_flag"]+CT,
     [[i,c,n,desc,ab]+cu(d(2020,1,1)) for i,c,n,desc,ab in PT], system="reference")

INV_ST = [("open","Open",False,1),("partial","Partial",False,2),
          ("paid","Paid",True,3),("void","Void",True,4)]
load("ref_invoice_status",
     ["status_code","status_name","is_terminal_flag","sort_order"]+CT,
     [[c,n,term,so]+cu(d(2020,1,1)) for c,n,term,so in INV_ST], system="reference")

PAY_ST = [("pending","Pending"),("cleared","Cleared"),("failed","Failed"),
          ("refunded","Refunded"),("void","Void")]
load("ref_payment_status", ["status_code","status_name"]+CT,
     [[c,n]+cu(d(2020,1,1)) for c,n in PAY_ST], system="reference")

# ===================== DIMENSIONS =====================
DEPTS = [(1,"APP","Apparel"),(2,"SGN","Signage"),(3,"PRO","Promo"),(4,"PRT","Print")]
load("oltp_department", ["department_id","department_code","department_name","description","is_active_flag"]+CT,
     [[i,c,n,f"{n} department",True]+cu(d(2021,1,1)) for i,c,n in DEPTS])

CATS = []
cid = 0
for dep_id, dc, dn in DEPTS:
    for k in range(2):
        cid += 1
        CATS.append((cid, dep_id, f"{dc}-{k+1}", f"{dn} Cat {k+1}"))
load("oltp_product_category",
     ["category_id","department_id","category_code","category_name","description","is_active_flag"]+CT,
     [[i,dep,c,n,f"{n}",True]+cu(d(2021,1,1)) for i,dep,c,n in CATS])

PRODUCTS = []
for pid in range(1, 26):
    cat = random.choice(CATS)
    cost = money(random.uniform(2, 60))
    markup = Decimal(str(round(random.uniform(1.3, 2.5), 4)))
    price = money(cost * markup)
    PRODUCTS.append(dict(product_id=pid, category=cat, cost=cost, markup=markup, price=price))
load("oltp_product",
     ["product_id","sku","product_name","description","department_id","category_id","brand",
      "unit_cost_amount","markup_pct","standard_price_amount","is_local_made_flag","is_active_flag"]+CT,
     [[p["product_id"], f"SKU-{p['product_id']:04d}", f"Product {p['product_id']}",
       "Custom printed item", p["category"][1], p["category"][0],
       random.choice(["PrintCo","LocalMade","Generic"]),
       p["cost"], p["markup"], p["price"], random.random()<0.4, True]+cu(d(2022,1,1))
      for p in PRODUCTS])

STORES = []
for sid in range(1, 5):
    st = random.choice(STATES)
    STORES.append(dict(store_id=sid, state=st[0]))
load("oltp_store",
     ["store_id","store_code","store_name","street_address","city","state_code","zip_code",
      "phone","region","store_type","open_date","is_active_flag"]+CT,
     [[s["store_id"], f"ST{s['store_id']:02d}", f"PrintTime Store {s['store_id']}",
       f"{100+s['store_id']} Main St", "Austin", s["state"], f"7{s['store_id']:04d}",
       f"512-555-0{s['store_id']:03d}", "South", "retail", d(2021,6,1), True]+cu(d(2021,6,1))
      for s in STORES])

EMPLOYEES = []
eid = 0
for s in STORES:
    for k in range(3):
        eid += 1
        EMPLOYEES.append(dict(employee_id=eid, store_id=s["store_id"]))
load("oltp_employee",
     ["employee_id","employee_code","first_name","last_name","full_name","email","phone",
      "role","store_id","hire_date","is_active_flag"]+CT,
     [[e["employee_id"], f"EMP{e['employee_id']:03d}", f"First{e['employee_id']}", f"Last{e['employee_id']}",
       f"First{e['employee_id']} Last{e['employee_id']}", f"emp{e['employee_id']}@printtime.com",
       f"512-555-1{e['employee_id']:03d}", random.choice(["cashier","manager","designer"]),
       e["store_id"], d(2022,1,10), True]+cu(d(2022,1,10)) for e in EMPLOYEES])

CUSTOMERS = []
for cid2 in range(1, 41):
    is_biz = random.random() < 0.5
    status = "active" if random.random() < 0.8 else "inactive"
    CUSTOMERS.append(dict(customer_id=cid2, is_biz=is_biz, status=status,
                          store=random.choice(STORES)["store_id"],
                          tax=random.choice(TAX)[0]))
load("oltp_customer",
     ["customer_id","customer_account_no","business_name","first_name","last_name","full_name",
      "email","phone","customer_status","default_tax_rate_id","home_store_id","first_order_date"]+CT,
     [[c["customer_id"], f"ACC-{c['customer_id']:04d}",
       f"Biz {c['customer_id']} LLC" if c["is_biz"] else None,
       None if c["is_biz"] else f"John{c['customer_id']}",
       None if c["is_biz"] else f"Doe{c['customer_id']}",
       None if c["is_biz"] else f"John{c['customer_id']} Doe{c['customer_id']}",
       f"cust{c['customer_id']}@example.com", f"(555) 100-{c['customer_id']:04d}",
       c["status"], c["tax"], c["store"], d(2023,1,15)]+cu(d(2023,1,15)) for c in CUSTOMERS])

ADDRESSES = []
aid = 0
for c in CUSTOMERS:
    for k in range(random.randint(1, 2)):
        aid += 1
        ADDRESSES.append(dict(address_id=aid, customer_id=c["customer_id"],
                              state=random.choice(STATES)[0], primary=(k == 0)))
load("oltp_customer_address",
     ["address_id","customer_id","address_type","street_address","street_address2","city",
      "state_code","zip_code","is_primary_flag"]+CT,
     [[a["address_id"], a["customer_id"], "billing" if a["primary"] else "shipping",
       f"{a['address_id']} Oak Ave", None, "Austin", a["state"], "78701", a["primary"]]+cu(d(2023,1,15))
      for a in ADDRESSES])

# ===================== TRANSACTIONS =====================
invoices, lines, payments = [], [], []
inv_status_hist, refunds, adjustments = [], [], []
line_id = pay_id = ish_id = ref_id = adj_id = 0

for inv_id in range(1, 151):
    cust = random.choice(CUSTOMERS)
    store_id = cust["store"]
    emp = random.choice([e for e in EMPLOYEES if e["store_id"] == store_id])
    taxid = cust["tax"]
    rate = dict((t[0], t[3]) for t in TAX)[taxid]
    cust_addrs = [a for a in ADDRESSES if a["customer_id"] == cust["customer_id"]]
    bill = cust_addrs[0]["address_id"]
    ship = cust_addrs[-1]["address_id"]
    idate = d(2024, random.randint(1, 12), random.randint(1, 28))

    # lines
    n_lines = random.randint(1, 4)
    subtotal = Decimal("0.00")
    for ln in range(1, n_lines + 1):
        line_id += 1
        p = random.choice(PRODUCTS)
        qty = random.randint(1, 40)
        unit_price = money(p["price"] * Decimal(str(round(random.uniform(0.95, 1.1), 3))))
        disc = money(unit_price * qty * Decimal(str(round(random.choice([0, 0, 0.05, 0.1]), 3))))
        line_total = money(unit_price * qty - disc)
        subtotal += line_total
        lines.append([line_id, inv_id, ln, p["product_id"], None, f"Line {ln}",
                      random.choice(["Red","Blue","Black","White",None]), qty, unit_price,
                      p["cost"], disc, line_total] + cu(idate))

    inv_disc = money(subtotal * Decimal(str(round(random.choice([0, 0, 0.03]), 3))))
    tax_amt = money((subtotal - inv_disc) * rate)
    fee = Decimal("0.00")
    total = money(subtotal - inv_disc + tax_amt + fee)

    roll = random.random()
    if roll < 0.6:   status, paid = "paid", total
    elif roll < 0.8: status, paid = "partial", money(total * Decimal("0.5"))
    elif roll < 0.95: status, paid = "open", Decimal("0.00")
    else:            status, paid = "void", Decimal("0.00")
    balance = money(total - paid)
    due = d(2024, min(12, idate[5:7] and int(idate[5:7])), 28) if False else idate

    invoices.append([inv_id, f"INV-{inv_id:05d}", cust["customer_id"], store_id, emp["employee_id"],
                     bill, ship, f"PO-{inv_id}", idate, idate, status, taxid,
                     subtotal, inv_disc, tax_amt, fee, total, paid, balance,
                     "auto-generated"] + cu(idate))

    # payments to match paid amount
    if paid > 0:
        n_pay = 1 if status == "partial" else random.randint(1, 2)
        remaining = paid
        for s_ in range(1, n_pay + 1):
            pay_id += 1
            amt = money(remaining if s_ == n_pay else remaining / 2)
            remaining = money(remaining - amt)
            payments.append([pay_id, inv_id, cust["customer_id"], random.choice(PM)[0], 1,
                             emp["employee_id"], store_id, None, s_, "cleared", idate,
                             amt, money(amt * rate / (1 + rate)), Decimal("0.00"), amt,
                             f"REF{pay_id:06d}"] + cu(idate))

    # status history
    ish_id += 1
    inv_status_hist.append([ish_id, inv_id, None, "open", ts(idate), emp["employee_id"], "created"])
    if status in ("paid", "partial", "void"):
        ish_id += 1
        inv_status_hist.append([ish_id, inv_id, "open", status, ts(idate), emp["employee_id"], "updated"])

    # occasional refund + adjustment
    if status == "paid" and random.random() < 0.1:
        ref_id += 1
        refunds.append([ref_id, pay_id, inv_id, money(total * Decimal("0.2")), idate,
                        "customer return", emp["employee_id"]] + cu(idate))
    if random.random() < 0.15:
        adj_id += 1
        adjustments.append([adj_id, inv_id, "discount", money(Decimal("5.00")),
                            random.choice(["price match","goodwill","damage"]), emp["employee_id"], idate] + cu(idate))

load("oltp_invoice",
     ["invoice_id","invoice_number","customer_id","store_id","employee_id","billing_address_id",
      "shipping_address_id","po_number","invoice_date","invoice_due_date","invoice_status","tax_rate_id",
      "subtotal_amount","discount_amount","tax_amount","fee_amount","total_amount","paid_amount",
      "balance_due_amount","notes"]+CT, invoices)
load("oltp_invoice_line",
     ["invoice_line_id","invoice_id","line_number","product_id","variant_id","line_description",
      "color","order_qty","unit_price_amount","unit_cost_amount","discount_amount","line_total_amount"]+CT, lines)
load("oltp_payment",
     ["payment_id","invoice_id","customer_id","payment_method_id","payment_type_id","employee_id",
      "store_id","parent_payment_id","payment_sequence_num","payment_status","payment_date",
      "gross_amount","tax_amount","fee_amount","net_amount","reference_no"]+CT, payments)
load("oltp_invoice_status_history",
     ["status_history_id","invoice_id","old_status","new_status","changed_at_source_timestamp","changed_by","note"],
     inv_status_hist)
load("oltp_refund",
     ["refund_id","payment_id","invoice_id","refund_amount","refund_date","reason","refunded_by"]+CT, refunds)
load("oltp_invoice_adjustment",
     ["adjustment_id","invoice_id","adjustment_type","amount","reason","adjusted_by","adjustment_date"]+CT, adjustments)

# customer status history (a few)
csh = []
for k, c in enumerate([c for c in CUSTOMERS if c["status"] == "inactive"][:8], start=1):
    csh.append([k, c["customer_id"], "active", "inactive", ts(d(2024,6,1)), 1, "churn"])
load("oltp_customer_status_history",
     ["status_history_id","customer_id","old_status","new_status","changed_at_source_timestamp","changed_by","reason"], csh)

# econ indicators (FRED-style): 2 series x 12 months
econ = []
for si, series in enumerate(["CPIAUCSL", "UNRATE"]):
    for m in range(1, 13):
        econ.append([series, d(2024, m, 1),
                     money(300 + m * 0.5) if si == 0 else money(3.5 + m * 0.02),
                     "Index" if si == 0 else "Percent"] + cu(d(2024, m, 1)))
load("econ_indicator", ["series_id","observation_date","indicator_value","units"]+CT, econ, system="fred")

print("\nDONE — sample data loaded.")
cur.close(); conn.close()
