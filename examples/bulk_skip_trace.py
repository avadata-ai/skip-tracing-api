"""Bulk skip trace a CSV with the Ava Data API: upload, poll, download the results in the standard layout.

Usage: AVADATA_API_KEY=sk_live_... python bulk_skip_trace.py input.csv [results.csv]
Start from sample-bulk.csv in this folder and replace its rows with your own records.
CSV rules: a header row, UTF-8, no line breaks inside cells, at most 100 MB and 250,000 rows. Each row
needs First Name + Last Name + ZIP, First Name + Last Name + City + State, or Street Address + City +
State + ZIP; an address column alone is not enough. Headers are matched by exact name, not mapped (the
accepted names are in the README). Rows without a combination are skipped and never charged; your other
columns, such as an ID, come back unchanged in the results.
Credits: rows x data types are reserved at upload; each row is charged 1 credit (2¢) per requested data
type it actually returned, and the rest is released.
Requires: pip install requests
"""
import json
import os
import sys
import time

import requests

API = os.environ.get("AVADATA_BASE_URL", "https://app.avadata.ai/api/v1")
key = os.environ.get("AVADATA_API_KEY")
if not key or len(sys.argv) < 2:
    sys.exit(__doc__)
src = sys.argv[1]
out = sys.argv[2] if len(sys.argv) > 2 else "results.csv"
auth = {"Authorization": f"Bearer {key}"}

HINTS = {
    401: "Check the key and send it exactly as 'Authorization: Bearer sk_live_...'.",
    402: "Not enough available credits (the upload reserves rows x data types). GET /credits shows availableCredits.",
    403: "SUBSCRIPTION_REQUIRED or SUBSCRIPTION_PAUSED: start or resume your plan in the app.",
    413: "The file is over 100 MB. Split it and upload the parts.",
}


def call(method, path, raw=False, timeout=60, **kwargs):
    """One request. On 429, wait and retry: Retry-After when the response has one, otherwise 60 s
    (the 60-per-minute 429 sends none). Returns `data` (or the response with raw=True); any other
    error exits with the API's message."""
    for attempt in range(1, 6):
        try:
            res = requests.request(method, f"{API}{path}", headers=auth, timeout=timeout, stream=raw, **kwargs)
        except requests.RequestException as err:
            sys.exit(f"No response ({err}). Check the network and the base URL ({API}).")
        retry_after = res.headers.get("Retry-After", "60")
        wait = int(retry_after) if retry_after.isdigit() else 60
        if res.status_code == 429 and attempt < 5 and wait <= 300:
            print(f"Rate limited (HTTP 429), retrying in {wait}s", file=sys.stderr)
            time.sleep(wait)
            continue
        if raw and res.ok:
            return res
        try:
            payload = res.json()
        except ValueError:
            payload = {"error": res.text[:300]}
        if res.ok and payload.get("success"):
            return payload["data"]
        code = f" {payload['code']}" if payload.get("code") else ""
        hint = f"\n{HINTS[res.status_code]}" if res.status_code in HINTS else ""
        sys.exit(f"HTTP {res.status_code}{code}: {payload.get('error', 'request failed')}{hint}")


# Upload. Uploads accept no idempotency key, so this script never retries one except after a 429.
try:
    with open(src, "rb") as f:
        content = f.read()
except OSError as err:
    sys.exit(f"Can't read {src}: {err.strerror}. Check the file name and path.")
job = call("POST", "/bulk/upload", timeout=300,
           files={"file": (os.path.basename(src), content, "text/csv")},
           data={"dataTypes": json.dumps(["phone", "email"])})  # list each type once
print(f"Job {job['jobId']} accepted: {job['recordCount']} row(s), {job['creditsPerMatch']} data type(s) per row")
if job.get("skippedCount"):
    print(f"Skipped {job['skippedCount']} row(s), not charged: {job.get('skippedReason')}")

# Poll every 10 s. Each poll counts toward the key's 60 requests per minute.
while True:
    status = call("GET", f"/bulk/{job['jobId']}/status")
    print(f"status: {status['status']} ({status.get('progress') or 0}%)")
    if status["status"] == "completed":
        print(f"Matched rows: {status.get('numMatches') or 0}")
        break
    if status["status"] == "failed":
        sys.exit(f"Job failed: {status.get('errorMessage') or 'no reason given'}\n"
                 "A failed job can still finish later. Check its status again before uploading the same file again.")
    time.sleep(10)  # uploading, queued, processing, or any new value: keep polling

# layout=standard: your columns, then Match Found, Phone 1-6 with Line Type 1-6, Mobile 1-3,
# Landline 1-3, Email 1... Without it you get the older layout, kept unchanged for existing integrations.
res = call("GET", f"/bulk/{job['jobId']}/download", raw=True, timeout=600,
           params={"layout": "standard", "format": "csv"})
with open(out, "wb") as f:
    for chunk in res.iter_content(chunk_size=1 << 16):
        f.write(chunk)
print(f"Saved {out}")
