#!/usr/bin/env bash
# Single-record skip trace with the Ava Data API (POST /standard-search).
# Usage: AVADATA_API_KEY=sk_live_... ./standard-search.sh LAST_NAME [FIRST_NAME] [ADDRESS] [CITY] [STATE] [ZIP]
# Example: ./standard-search.sh Doe Jane "123 Main St" Austin TX 78701
# The API validates only lastName up front, but a search needs a name plus street + ZIP, or city + state
# (otherwise 400 INSUFFICIENT_INPUT). A match charges 1 credit (2¢) per requested data type, even a type
# that comes back empty; a search with no match costs nothing.
# Run it on a server: the key must stay out of browsers and apps. Prints phones and emails when jq is
# installed, otherwise the raw JSON.
set -euo pipefail
: "${AVADATA_API_KEY:?Set AVADATA_API_KEY to your Ava Data API key}"
if [ $# -lt 1 ]; then
  echo "Usage: $0 LAST_NAME [FIRST_NAME] [ADDRESS] [CITY] [STATE] [ZIP]" >&2
  exit 1
fi
API="${AVADATA_BASE_URL:-https://app.avadata.ai/api/v1}"
AUTH="Authorization: Bearer $AVADATA_API_KEY"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# call METHOD PATH [curl args]: sets STATUS and writes the body to $TMP/body. On 429 (code RATE_LIMITED,
# 60 requests per minute per key) it waits the Retry-After seconds, or 60 s if the header is missing, then
# retries. Responses also carry X-RateLimit-Limit, X-RateLimit-Remaining and X-RateLimit-Reset; counts are
# kept per server instance, so treat them as a guide and wait on Retry-After.
call() {
  local method=$1 path=$2 attempt wait
  shift 2
  for attempt in 1 2 3 4 5; do
    : > "$TMP/body"; : > "$TMP/headers"
    STATUS=$(curl -sS -X "$method" "$API$path" -H "$AUTH" -D "$TMP/headers" -o "$TMP/body" -w '%{http_code}' "$@") || STATUS=000
    [ "$STATUS" = 429 ] && [ "$attempt" -lt 5 ] || return 0
    wait=$(sed -n 's/^[Rr]etry-[Aa]fter: *\([0-9][0-9]*\).*/\1/p' "$TMP/headers" | tail -n 1)
    wait=${wait:-60}
    [ "$wait" -le 300 ] || return 0
    echo "Rate limited (HTTP 429), retrying in ${wait}s" >&2
    sleep "$wait"
  done
}
str_of() { sed -nE "s/.*\"$1\" *: *\"(([^\"\\\\]|\\\\.)*)\".*/\1/p" "$TMP/body" | head -n 1 | sed 's/\\"/"/g'; }
num_of() { sed -n "s/.*\"$1\" *: *\([0-9][0-9]*\).*/\1/p" "$TMP/body" | head -n 1; }
fail() {
  local msg code
  msg=$(str_of error); code=$(str_of code)
  echo "HTTP $STATUS${code:+ $code}: ${msg:-$(head -c 300 "$TMP/body" 2>/dev/null)}" >&2
  case "$STATUS" in
    000) echo "No response. Check the network and the base URL ($API). After a timeout the search may" \
              "still have run and been charged: check your balance (GET /credits) before retrying." >&2 ;;
    401) echo "Check the key and send it exactly as 'Authorization: Bearer sk_live_...'." >&2 ;;
    402) echo "Not enough available credits. GET /credits shows availableCredits." >&2 ;;
    403) echo "SUBSCRIPTION_REQUIRED or SUBSCRIPTION_PAUSED: start or resume your plan in the app." >&2 ;;
    500) echo "Search service error. Any credits taken were refunded; it is safe to retry shortly." >&2 ;;
  esac
  exit 1
}

json_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
field() { if [ -n "$2" ]; then printf ',"%s":"%s"' "$1" "$(json_escape "$2")"; fi; }

# List each data type once: a repeated type is charged again.
BODY="{\"lastName\":\"$(json_escape "$1")\"$(field firstName "${2:-}")$(field address "${3:-}")$(field city "${4:-}")$(field state "${5:-}")$(field zip "${6:-}"),\"dataTypes\":[\"phone\",\"email\"]}"

call POST /standard-search -H "Content-Type: application/json" --max-time 60 -d "$BODY"
[ "$STATUS" = 200 ] || fail
if grep -q '"matchFound":false' "$TMP/body"; then
  echo "No match: nothing charged"
  exit 0
fi

echo "Match: $(num_of creditsCharged) credit(s) charged"
if command -v jq >/dev/null 2>&1; then
  jq -r '.data
    | "name: \(.name.first // "") \(.name.last // "") (\(.matchType // "unknown") match)",
      (.phones[]? | "phone: \(.number) \(.lineType // "")"),
      (.emails[]? | "email: \(.)"),
      (.addresses[]? | "address: \(.address), \(.city), \(.state) \(.zip)\(if .zip4 then "-" + .zip4 else "" end)")' "$TMP/body"
else
  cat "$TMP/body"
  echo
fi
if grep -q '"matchType":"Household"' "$TMP/body"; then
  echo "Household match: a phone or email may belong to someone else at the address."
fi
