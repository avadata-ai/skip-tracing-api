"""Single-record skip trace with the Ava Data API (POST /standard-search).

Usage: AVADATA_API_KEY=sk_live_... python standard_search.py LAST_NAME [FIRST_NAME] [ADDRESS] [CITY] [STATE] [ZIP]
Example: python standard_search.py Doe Jane "123 Main St" Austin TX 78701
The API validates only lastName up front, but a search needs a name plus street + ZIP, or city + state
(otherwise 400 INSUFFICIENT_INPUT). A match charges 1 credit (2¢) per requested data type, even a type
that comes back empty; a search with no match costs nothing. Run it on a server: the key must stay out
of browsers and apps.
Requires: pip install requests
"""
import os
import sys
import time

import requests

API = os.environ.get("AVADATA_BASE_URL", "https://app.avadata.ai/api/v1")
key = os.environ.get("AVADATA_API_KEY")
args = sys.argv[1:]
if not key or not args:
    sys.exit(__doc__)

HINTS = {
    401: "Check the key and send it exactly as 'Authorization: Bearer sk_live_...'.",
    402: "Not enough available credits. GET /credits shows availableCredits.",
    403: "SUBSCRIPTION_REQUIRED or SUBSCRIPTION_PAUSED: start or resume your plan in the app.",
    500: "Search service error. Any credits taken were refunded; it is safe to retry shortly.",
}


def call(path, body):
    """POST JSON and return `data`. On 429 (code RATE_LIMITED, 60 requests per minute per key), wait the
    Retry-After seconds, or 60 s if the header is missing, then retry. Responses also carry
    X-RateLimit-Limit, X-RateLimit-Remaining and X-RateLimit-Reset; counts are kept per server instance,
    so treat them as a guide and wait on Retry-After. Any other error exits with the API's message."""
    for attempt in range(1, 6):
        try:
            res = requests.post(f"{API}{path}", headers={"Authorization": f"Bearer {key}"}, json=body, timeout=60)
        except requests.Timeout:
            sys.exit("Timed out. Searches accept no idempotency key: this one may still have run and been "
                     "charged. Check your balance (GET /credits) before retrying.")
        except requests.RequestException as err:
            sys.exit(f"No response ({err}). Check the network and the base URL ({API}).")
        retry_after = res.headers.get("Retry-After", "60")
        wait = int(retry_after) if retry_after.isdigit() else 60
        if res.status_code == 429 and attempt < 5 and wait <= 300:
            print(f"Rate limited (HTTP 429), retrying in {wait}s", file=sys.stderr)
            time.sleep(wait)
            continue
        try:
            payload = res.json()
        except ValueError:
            payload = {"error": res.text[:300]}
        if res.ok and payload.get("success"):
            return payload["data"]
        code = f" {payload['code']}" if payload.get("code") else ""
        hint = f"\n{HINTS[res.status_code]}" if res.status_code in HINTS else ""
        sys.exit(f"HTTP {res.status_code}{code}: {payload.get('error', 'request failed')}{hint}")


fields = ["lastName", "firstName", "address", "city", "state", "zip"]
body = {name: value for name, value in zip(fields, args) if value}
body["dataTypes"] = ["phone", "email"]  # list each type once: a repeated type is charged again

data = call("/standard-search", body)
if not data["matchFound"]:
    print("No match: nothing charged")
    sys.exit(0)

# phones: [{number, lineType?}], emails: strings, name: {first, last}, addresses: [{address, city, state, zip, zip4?}]
name = data.get("name") or {}
print(f"Match: {data['creditsCharged']} credit(s) charged")
print(f"name: {' '.join(filter(None, [name.get('first'), name.get('last')]))} ({data.get('matchType', 'unknown')} match)")
for phone in data.get("phones", []):
    print("phone:", phone["number"], phone.get("lineType", ""))
for email in data.get("emails", []):
    print("email:", email)
for a in data.get("addresses", []):
    zip4 = f"-{a['zip4']}" if a.get("zip4") else ""
    print(f"address: {a.get('address')}, {a.get('city')}, {a.get('state')} {a.get('zip')}{zip4}")
if data.get("matchType") == "Household":
    print("Household match: a phone or email may belong to someone else at the address.")
