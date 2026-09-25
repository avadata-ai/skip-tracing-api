"""Bulk skip trace a CSV with the Ava Data API: upload, poll, download.

Usage: AVADATA_API_KEY=sk_live_... python bulk_skip_trace.py input.csv [results.csv]
The CSV needs a header row and at minimum an "address" column; firstName, lastName, city,
state and zip columns narrow each search. 1 credit (2¢) per data type per match.
Requires: pip install requests
"""
import json
import os
import sys
import time

import requests

API = "https://app.avadata.ai/api/v1"
key = os.environ.get("AVADATA_API_KEY")
if not key or len(sys.argv) < 2:
    sys.exit(__doc__)
src = sys.argv[1]
out = sys.argv[2] if len(sys.argv) > 2 else "results.csv"
auth = {"Authorization": f"Bearer {key}"}


def call(method, path, **kwargs):
    res = requests.request(method, f"{API}{path}", headers=auth, timeout=120, **kwargs)
    payload = res.json()
    if not res.ok or not payload.get("success"):
        sys.exit(f"HTTP {res.status_code}: {payload.get('error', 'request failed')}")
    return payload["data"]


with open(src, "rb") as f:
    job = call("POST", "/bulk/upload",
               files={"file": (os.path.basename(src), f, "text/csv")},
               data={"dataTypes": json.dumps(["phone", "email"])})
print(f"Job {job['jobId']} accepted ({job.get('recordCount')} records)")

while True:
    status = call("GET", f"/bulk/{job['jobId']}/status")
    print(f"status: {status['status']} ({status.get('progress', 0)}%)")
    if status["status"] == "completed":
        break
    if status["status"] == "failed":
        sys.exit(status.get("errorMessage") or "bulk job failed")
    time.sleep(5)

res = requests.get(f"{API}/bulk/{job['jobId']}/download", params={"format": "csv"}, headers=auth, timeout=300)
res.raise_for_status()
with open(out, "wb") as f:
    f.write(res.content)
print(f"Saved {out}")
