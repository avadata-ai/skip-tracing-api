"""Build a property list with the Ava Data List Builder API: preview (free) -> create (with an
Idempotency-Key) -> poll -> read the first records -> download the CSV.

Usage: AVADATA_API_KEY=sk_live_... python list_builder.py STATE KIND VALUE [MAX_RECORDS] [list.csv]
Example: python list_builder.py AZ county Maricopa 25 maricopa.csv
KIND is city, county or zip (5 digits). MAX_RECORDS (default 25, at most 100,000) caps the pull.
Credits: 1 credit (2¢) per record pulled. The cap is reserved when the list is created; you are charged
for the records actually pulled and the rest is released. Edit `filters` below to change the search;
GET /lists/filters returns every allowed value. List Builder must be enabled for the account.
Requires: pip install requests
"""
import os
import sys
import time
import uuid

import requests

API = os.environ.get("AVADATA_BASE_URL", "https://app.avadata.ai/api/v1")
key = os.environ.get("AVADATA_API_KEY")
args = sys.argv[1:]
if not key or len(args) < 3 or (len(args) > 3 and not args[3].isdigit()):
    sys.exit(__doc__)
state, kind, value = args[:3]
max_records = int(args[3]) if len(args) > 3 else 25
out = args[4] if len(args) > 4 else "list.csv"
auth = {"Authorization": f"Bearer {key}"}

HINTS = {
    401: "Check the key and send it exactly as 'Authorization: Bearer sk_live_...'.",
    402: "Not enough available credits for the reservation. GET /credits shows availableCredits.",
    403: "LIST_BUILDER_DISABLED: List Builder isn't on for this account. SUBSCRIPTION_REQUIRED or "
         "SUBSCRIPTION_PAUSED: start or resume your plan in the app.",
}


class ApiError(Exception):
    def __init__(self, status, payload):
        code = f" {payload['code']}" if payload.get("code") else ""
        field = f" (field: {payload['field']})" if payload.get("field") else ""
        hint = f"\n{HINTS[status]}" if status in HINTS else ""
        super().__init__(f"HTTP {status}{code}: {payload.get('error', 'request failed')}{field}{hint}")
        self.status = status


def call(method, path, raw=False, timeout=60, headers=None, **kwargs):
    """One request. On 429, wait and retry: Retry-After when the response has one, otherwise 60 s
    (the 60-per-minute 429 sends none). Returns (data, response), or the response with raw=True.
    Other errors raise ApiError; network errors raise requests.RequestException."""
    for attempt in range(1, 6):
        res = requests.request(method, f"{API}{path}", headers={**auth, **(headers or {})},
                               timeout=timeout, stream=raw, **kwargs)
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
            return payload["data"], res
        raise ApiError(res.status_code, payload)


filters = {
    "location": {"state": state, "kind": kind, "values": [value]},
    "quicklists": ["absentee-owner", "high-equity"],
    "quicklistMatch": "all",
}

try:
    # 1. Preview: counts matches and shows the cost. Free (20 per minute, 250 per UTC day per account).
    for attempt in range(1, 4):
        try:
            preview, _ = call("POST", "/lists/preview", json={"filters": filters, "maxRecords": max_records})
            break
        except ApiError as err:
            if err.status != 503 or attempt == 3:
                raise
            print("Match count unavailable right now (503), retrying in 10s", file=sys.stderr)
            time.sleep(10)
    print(f"Preview: {preview['matchCount']} match(es); pulling {preview['recordsToPull']} record(s) "
          f"costs about {preview['estimatedCredits']} credit(s)")
    if preview["recordsToPull"] == 0:
        print("Nothing to pull: no list was created and nothing was charged.")
        sys.exit(0)

    # 2. Create. maxRecords = the preview's recordsToPull, so only the credits needed are reserved.
    # One Idempotency-Key per list, sent again on every retry: a retry after a timeout, 409 or 5xx
    # returns the original list (header Idempotent-Replayed: true) instead of creating and charging twice.
    idempotency_key = str(uuid.uuid4())
    body = {"name": f"{state} {kind} {value} absentee high equity",
            "maxRecords": preview["recordsToPull"], "filters": filters}
    for attempt in range(1, 6):
        try:
            lst, res = call("POST", "/lists", json=body, timeout=120,
                            headers={"Idempotency-Key": idempotency_key})
            if res.headers.get("Idempotent-Replayed") == "true":
                print("(replayed: this list already existed, nothing was charged twice)")
            break
        except (ApiError, requests.RequestException) as err:
            status = getattr(err, "status", None)
            if (status is not None and status != 409 and status < 500) or attempt == 5:
                raise
            print(f"Create not confirmed ({f'HTTP {status}' if status else f'no response: {type(err).__name__}'}), "
                  "retrying with the same Idempotency-Key in 10s", file=sys.stderr)
            time.sleep(10)
    print(f"List {lst['listId']} created, {lst['creditsReserved']} credit(s) reserved")

    # 3. Poll every 10 s until completed or failed. Any other value, including new ones, means still pulling.
    while lst["status"] not in ("completed", "failed"):
        time.sleep(10)
        lst, _ = call("GET", f"/lists/{lst['listId']}")
        print(f"status: {lst['status']} ({lst['progress']}%), {lst['recordCount']} record(s)")
    if lst["status"] == "failed":
        print(lst["errorMessage"], file=sys.stderr)
        if lst["recordCount"] == 0:
            sys.exit(1)

    # 4. Read the first records as JSON (free). Default columns; add columns=key1,key2 for others (up to 35).
    page, _ = call("GET", f"/lists/{lst['listId']}/records", params={"limit": 5, "offset": 0})
    for r in page["records"]:
        flags = ", ".join(r.get("quickListFlags") or [])
        print(f"{r['propertyId']}  {r.get('propStreet') or ''}, {r.get('propCity') or ''}, "
              f"{r.get('propState') or ''} {r.get('propZip') or ''}  owner: {r.get('ownerName') or '-'}  [{flags}]")

    # 5. Download every record as CSV (free). Header row = column keys, propertyId first.
    res = call("GET", f"/lists/{lst['listId']}/download", raw=True, timeout=600)
    with open(out, "wb") as f:
        for chunk in res.iter_content(chunk_size=1 << 16):
            f.write(chunk)
    print(f"Saved {out} ({lst['recordCount']} record(s), {lst['creditsCharged']} credit(s) charged)")
except ApiError as err:
    sys.exit(str(err))
except requests.RequestException as err:
    sys.exit(f"No response ({err}). Check the network and the base URL ({API}).")
