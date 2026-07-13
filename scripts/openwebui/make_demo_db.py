"""Build the demo sales SQLite DB for the Open WebUI SQL tool.

Usage: python make_demo_db.py <path/to/demo.db>
Idempotent: exits without touching an existing database.

Fictional B2B company, 2024-01 through 2026-06. Hidden story for the
"agentic analyst" demo: EMEA revenue collapses in Q3 2025 because the two
anchor EMEA customers churn after a spike of critical support tickets
(a botched v3 firmware rollout), compounded by a 20% price cut on the
flagship product that trims margins everywhere else.
"""

import datetime as dt
import os
import random
import sqlite3
import sys

random.seed(1337)
if len(sys.argv) != 2:
    sys.exit("Usage: python make_demo_db.py <path/to/demo.db>")
DB = sys.argv[1]
if os.path.exists(DB):
    print(f"demo.db already exists at {DB} — skipping.")
    sys.exit(0)
os.makedirs(os.path.dirname(os.path.abspath(DB)), exist_ok=True)

REGIONS = ["AMER", "EMEA", "APAC"]
SEGMENTS = ["enterprise", "midmarket", "startup"]
FIRST = ["Acme", "Globex", "Initech", "Umbra", "Vertex", "Helios", "Nimbus", "Quanta",
         "Zephyr", "Orchid", "Falcon", "Aurora", "Cobalt", "Delta", "Ember", "Flux",
         "Granite", "Harbor", "Ion", "Juniper", "Krypton", "Lumen", "Mistral", "Nova",
         "Onyx", "Pylon", "Quartz", "Ridge", "Summit", "Tundra"]
SECOND = ["Systems", "Labs", "Industries", "Dynamics", "Networks", "Analytics",
          "Robotics", "Software", "Logistics", "Energy"]

PRODUCTS = [
    (1, "TernaryEdge Accelerator", "hardware", 4200.0),
    (2, "BonsaiServe License", "software", 950.0),
    (3, "Quantization Toolkit", "software", 480.0),
    (4, "Premium Support", "services", 1200.0),
    (5, "Deployment Consulting", "services", 2600.0),
    (6, "EdgeBox Mini", "hardware", 780.0),
]

conn = sqlite3.connect(DB)
c = conn.cursor()
c.executescript("""
CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT, region TEXT,
    segment TEXT, signup_date TEXT, churned_date TEXT);
CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, category TEXT,
    unit_price REAL);
CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER,
    order_date TEXT, status TEXT);
CREATE TABLE order_items (order_id INTEGER, product_id INTEGER,
    quantity INTEGER, unit_price REAL);
CREATE TABLE support_tickets (id INTEGER PRIMARY KEY, customer_id INTEGER,
    created_date TEXT, severity TEXT, topic TEXT);
""")
c.executemany("INSERT INTO products VALUES (?,?,?,?)", PRODUCTS)

# ── customers ────────────────────────────────────────────────────────────────
customers = []
cid = 0
names = [f"{a} {b}" for a in FIRST for b in SECOND]
random.shuffle(names)
for region in REGIONS:
    for _ in range(28):
        cid += 1
        seg = random.choices(SEGMENTS, weights=[2, 4, 4])[0]
        signup = dt.date(2023, 1, 1) + dt.timedelta(days=random.randint(0, 700))
        customers.append([cid, names.pop(), region, seg, signup.isoformat(), None])

# Two anchor EMEA enterprise customers that churn end of Q2 2025
anchors = []
for nm in ("Meridian Grid AG", "NordFab Automation"):
    cid += 1
    customers.append([cid, nm, "EMEA", "enterprise", "2023-02-15", "2025-07-05"])
    anchors.append(cid)

c.executemany("INSERT INTO customers VALUES (?,?,?,?,?,?)", customers)

# ── orders ───────────────────────────────────────────────────────────────────
def price(pid, day):
    base = PRODUCTS[pid - 1][3]
    # flagship price cut of 20% from 2025-08-01 onward
    if pid == 1 and day >= dt.date(2025, 8, 1):
        return round(base * 0.8, 2)
    return base

oid = 0
start, end = dt.date(2024, 1, 1), dt.date(2026, 6, 30)
for cust in customers:
    cust_id, _, region, seg, signup, churned = cust
    churn_day = dt.date.fromisoformat(churned) if churned else None
    freq = {"enterprise": 22, "midmarket": 38, "startup": 60}[seg]
    if cust_id in anchors:
        freq = 8  # anchors order a lot
    day = max(start, dt.date.fromisoformat(signup))
    while day <= end:
        day += dt.timedelta(days=max(3, int(random.gauss(freq, freq / 3))))
        if day > end or (churn_day and day >= churn_day):
            break
        oid += 1
        c.execute("INSERT INTO orders VALUES (?,?,?,?)",
                  (oid, cust_id, day.isoformat(), "completed"))
        for _ in range(random.randint(1, 3)):
            pid = random.choices([1, 2, 3, 4, 5, 6],
                                 weights=[3 if seg == "enterprise" else 1, 4, 3, 2, 1, 3])[0]
            qty = random.randint(1, 6 if pid != 1 else 3)
            if cust_id in anchors and pid == 1:
                qty = random.randint(4, 9)
            c.execute("INSERT INTO order_items VALUES (?,?,?,?)",
                      (oid, pid, qty, price(pid, day)))

# ── support tickets (spike for anchors in May-June 2025: v3 firmware) ────────
tid = 0
for cust in customers:
    cust_id = cust[0]
    n = random.randint(2, 10)
    for _ in range(n):
        tid += 1
        day = start + dt.timedelta(days=random.randint(0, (end - start).days))
        c.execute("INSERT INTO support_tickets VALUES (?,?,?,?,?)",
                  (tid, cust_id, day.isoformat(),
                   random.choice(["low", "medium", "high"]),
                   random.choice(["billing", "onboarding", "performance",
                                  "integration", "bug"])))
for cust_id in anchors:
    for _ in range(14):
        tid += 1
        day = dt.date(2025, 5, 5) + dt.timedelta(days=random.randint(0, 50))
        c.execute("INSERT INTO support_tickets VALUES (?,?,?,?,?)",
                  (tid, cust_id, day.isoformat(), "critical",
                   "v3 firmware regression"))

conn.commit()
n_orders = c.execute("SELECT COUNT(*) FROM orders").fetchone()[0]
print(f"demo.db built: {len(customers)} customers, {n_orders} orders")
conn.close()
