"""Run a .sql file against Databricks via databricks-sql-connector.
Usage: python exec_sql.py <repo_root> <sql_file> [--show]
Reads .env from repo root. Splits on ';'. Prints per-statement status.
"""
import os, sys, re
from dotenv import load_dotenv
from databricks import sql

repo = sys.argv[1]
sqlfile = sys.argv[2]
show = "--show" in sys.argv
load_dotenv(os.path.join(repo, ".env"))

conn = sql.connect(
    server_hostname=os.environ["DBRICKS_HOST"],
    http_path=os.environ["DBRICKS_HTTP_PATH"],
    access_token=os.environ["DBRICKS_TOKEN"],
)
cur = conn.cursor()

raw = open(os.path.join(repo, sqlfile), encoding="utf-8").read()
# strip full-line comments FIRST (they may contain ';'), then split on ';'
raw = "\n".join(l for l in raw.splitlines() if not l.strip().startswith("--"))
stmts = [c.strip() for c in raw.split(";") if c.strip()]

ok = err = 0
for st in stmts:
    label = re.sub(r"\s+", " ", st)[:70]
    try:
        cur.execute(st)
        if show:
            rows = cur.fetchall()
            print(f"OK  {label}")
            for r in rows[:20]:
                print("     ", r)
        else:
            ok += 1
    except Exception as e:
        err += 1
        print(f"ERR {label}\n    -> {str(e).splitlines()[0][:200]}")
print(f"\nDONE  ok={ok} err={err} total={len(stmts)}")
cur.close(); conn.close()
