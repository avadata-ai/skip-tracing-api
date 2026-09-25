"""Single-record skip trace with the Ava Data API (POST /standard-search).

Usage: AVADATA_API_KEY=sk_live_... python standard_search.py LAST_NAME [FIRST_NAME] [ADDRESS] [CITY] [STATE] [ZIP]
Charges 1 credit (2¢) per data type per match; a search with no match costs nothing.
Requires: pip install requests
"""
import os
import sys

import requests

API = "https://app.avadata.ai/api/v1"
key = os.environ.get("AVADATA_API_KEY")
args = sys.argv[1:]
if not key or not args:
    sys.exit(__doc__)

fields = ["lastName", "firstName", "address", "city", "state", "zip"]
body = {name: value for name, value in zip(fields, args) if value}
body["dataTypes"] = ["phone", "email"]

res = requests.post(f"{API}/standard-search", headers={"Authorization": f"Bearer {key}"}, json=body, timeout=60)
payload = res.json()
if not res.ok or not payload.get("success"):
    sys.exit(f"HTTP {res.status_code}: {payload.get('error', 'request failed')}")

data = payload["data"]
print(f"Match: {data['creditsCharged']} credit(s) charged" if data["matchFound"] else "No match: nothing charged")
for phone in data.get("phones", []):
    print("phone:", phone.get("number"), phone.get("type", ""))
for email in data.get("emails", []):
    print("email:", email.get("address"))
