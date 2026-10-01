"""Run dbt with .env loaded into a clean env dict (no MSYS path mangling).
Usage: python run_dbt.py <repo_root> <dbt args...>
"""
import os, sys, subprocess
from dotenv import dotenv_values

repo = sys.argv[1]
args = sys.argv[2:]
env = os.environ.copy()
env.update({k: v for k, v in dotenv_values(os.path.join(repo, ".env")).items() if v is not None})

DBT = r"C:\Users\offic\AppData\Local\Programs\Python\Python312\Scripts\dbt.exe"
cmd = [DBT] + args + [
    "--project-dir", os.path.join(repo, "dbt", "printtime_dw"),
    "--profiles-dir", os.path.join(repo, "dbt", "printtime_dw"),
    "--target", "databricks",
]
print("RUN:", " ".join(cmd), flush=True)
sys.exit(subprocess.run(cmd, env=env).returncode)
