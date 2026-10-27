#!/usr/bin/env bash
# Build a property list with the Ava Data List Builder API: preview (free) -> create (with an
# Idempotency-Key) -> poll -> read the first records -> download the CSV.
# Usage: AVADATA_API_KEY=sk_live_... ./list-builder.sh STATE KIND VALUE [MAX_RECORDS] [list.csv]
# Example: ./list-builder.sh AZ county Maricopa 25 maricopa.csv
# KIND is city, county or zip (5 digits). MAX_RECORDS (default 25, at most 100,000) caps the pull.
# Credits: 1 credit (2¢) per record pulled. The cap is reserved when the list is created; you are charged
# for the records actually pulled and the rest is released. Edit FILTERS below to change the search;
# GET /lists/filters returns every allowed value. List Builder must be enabled for the account.
# Prints records when jq is installed, otherwise the raw JSON.
set -euo pipefail
: "${AVADATA_API_KEY:?Set AVADATA_API_KEY to your Ava Data API key}"
if [ $# -lt 3 ]; then
  echo "Usage: $0 STATE KIND VALUE [MAX_RECORDS] [list.csv]" >&2
  exit 1
fi
STATE_CODE=$1 KIND=$2 VALUE=$3 MAX="${4:-25}" OUT="${5:-list.csv}"
case "$MAX" in ''|*[!0-9]*) echo "MAX_RECORDS must be a whole number" >&2; exit 1 ;; esac
API="${AVADATA_BASE_URL:-https://app.avadata.ai/api/v1}"
AUTH="Authorization: Bearer $AVADATA_API_KEY"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# call METHOD PATH [curl args]: sets STATUS and writes the body to $TMP/body. On 429 (code RATE_LIMITED for
# the 60-per-minute key limit, or a List Builder code) it waits the Retry-After seconds, or 60 s if the
# header is missing, then retries. Responses also carry X-RateLimit-Limit, X-RateLimit-Remaining and
# X-RateLimit-Reset for the key limit; counts are kept per server instance, so wait on Retry-After.
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
  local msg code field
  msg=$(str_of error); code=$(str_of code); field=$(str_of field)
  echo "HTTP $STATUS${code:+ $code}: ${msg:-$(head -c 300 "$TMP/body" 2>/dev/null)}${field:+ (field: $field)}" >&2
  case "$STATUS" in
    000) echo "No response. Check the network and the base URL ($API)." >&2 ;;
    401) echo "Check the key and send it exactly as 'Authorization: Bearer sk_live_...'." >&2 ;;
    402) echo "Not enough available credits for the reservation. GET /credits shows availableCredits." >&2 ;;
    403) echo "LIST_BUILDER_DISABLED: List Builder isn't on for this account. SUBSCRIPTION_REQUIRED or" \
              "SUBSCRIPTION_PAUSED: start or resume your plan in the app." >&2 ;;
  esac
  exit 1
}
json_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

FILTERS="{\"location\":{\"state\":\"$(json_escape "$STATE_CODE")\",\"kind\":\"$(json_escape "$KIND")\",\"values\":[\"$(json_escape "$VALUE")\"]},\"quicklists\":[\"absentee-owner\",\"high-equity\"],\"quicklistMatch\":\"all\"}"

# 1. Preview: counts matches and shows the cost. Free (20 per minute, 250 per UTC day per account).
for attempt in 1 2 3; do
  call POST /lists/preview -H "Content-Type: application/json" --max-time 60 -d "{\"filters\":$FILTERS,\"maxRecords\":$MAX}"
  [ "$STATUS" = 503 ] || break
  echo "Match count unavailable right now (503), retrying in 10s" >&2
  sleep 10
done
[ "$STATUS" = 200 ] || fail
PULL=$(num_of recordsToPull)
echo "Preview: $(num_of matchCount) match(es); pulling $PULL record(s) costs about $(num_of estimatedCredits) credit(s)"
if [ "${PULL:-0}" -eq 0 ]; then
  echo "Nothing to pull: no list was created and nothing was charged."
  exit 0
fi

# 2. Create. maxRecords = the preview's recordsToPull, so only the credits needed are reserved.
# One Idempotency-Key per list, sent again on every retry: a retry after a timeout, 409 or 5xx
# returns the original list (header Idempotent-Replayed: true) instead of creating and charging twice.
IDEM_KEY="list-$(date +%Y%m%d%H%M%S)-$$-$RANDOM"
NAME="$STATE_CODE $KIND $VALUE absentee high equity"
BODY="{\"name\":\"$(json_escape "$NAME")\",\"maxRecords\":$PULL,\"filters\":$FILTERS}"
for attempt in 1 2 3 4 5; do
  call POST /lists -H "Content-Type: application/json" -H "Idempotency-Key: $IDEM_KEY" --max-time 120 -d "$BODY"
  case "$STATUS" in
    200) break ;;
    000|409|5??) echo "Create not confirmed (HTTP $STATUS), retrying with the same Idempotency-Key in 10s" >&2; sleep 10 ;;
    *) fail ;;
  esac
done
[ "$STATUS" = 200 ] || fail
LIST=$(str_of listId)
echo "List $LIST created, $(num_of creditsReserved) credit(s) reserved"
if grep -qi '^idempotent-replayed: *true' "$TMP/headers"; then echo "(replayed: this list already existed, nothing was charged twice)"; fi

# 3. Poll every 10 s until completed or failed. Any other value, including new ones, means still pulling.
while :; do
  call GET "/lists/$LIST" --max-time 60
  [ "$STATUS" = 200 ] || fail
  LIST_STATUS=$(str_of status)
  RECORDS=$(num_of recordCount)
  echo "status: $LIST_STATUS ($(num_of progress)%), $RECORDS record(s)"
  case "$LIST_STATUS" in completed|failed) break ;; esac
  sleep 10
done
CHARGED=$(num_of creditsCharged)
if [ "$LIST_STATUS" = failed ]; then
  echo "$(str_of errorMessage)" >&2
  [ "${RECORDS:-0}" -gt 0 ] || exit 1
fi

# 4. Read the first records as JSON (free). Default columns; add &columns=key1,key2 for others (up to 35).
call GET "/lists/$LIST/records?limit=5&offset=0" --max-time 60
[ "$STATUS" = 200 ] || fail
if command -v jq >/dev/null 2>&1; then
  jq -r '.data.records[] | "\(.propertyId)  \(.propStreet // ""), \(.propCity // ""), \(.propState // "") \(.propZip // "")  owner: \(.ownerName // "-")  [\((.quickListFlags // []) | join(", "))]"' "$TMP/body"
else
  head -c 1000 "$TMP/body"
  echo
fi

# 5. Download every record as CSV (free). Header row = column keys, propertyId first.
call GET "/lists/$LIST/download" --max-time 600
[ "$STATUS" = 200 ] || fail
mv "$TMP/body" "$OUT"
echo "Saved $OUT ($RECORDS record(s), $CHARGED credit(s) charged)"
