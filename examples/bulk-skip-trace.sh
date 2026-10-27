#!/usr/bin/env bash
# Bulk skip trace a CSV with the Ava Data API: upload, poll, download the results in the standard layout.
# Usage: AVADATA_API_KEY=sk_live_... ./bulk-skip-trace.sh input.csv [results.csv]
# Start from sample-bulk.csv in this folder and replace its rows with your own records.
# CSV rules: a header row, UTF-8, no line breaks inside cells, at most 100 MB and 250,000 rows. Each row
# needs First Name + Last Name + ZIP, First Name + Last Name + City + State, or Street Address + City +
# State + ZIP; an address column alone is not enough. Headers are matched by exact name, not mapped (the
# accepted names are in the README). Rows without a combination are skipped and never charged; your other
# columns, such as an ID, come back unchanged in the results.
# Credits: rows x data types are reserved at upload; each row is charged 1 credit (2¢) per requested data
# type it actually returned, and the rest is released.
set -euo pipefail
: "${AVADATA_API_KEY:?Set AVADATA_API_KEY to your Ava Data API key}"
IN="${1:?Usage: $0 input.csv [results.csv]}"
OUT="${2:-results.csv}"
[ -f "$IN" ] && [ -r "$IN" ] || { echo "Can't read $IN: check the file name and path." >&2; exit 1; }
API="${AVADATA_BASE_URL:-https://app.avadata.ai/api/v1}"
AUTH="Authorization: Bearer $AVADATA_API_KEY"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# call METHOD PATH [curl args]: sets STATUS and writes the body to $TMP/body. On 429 it waits and
# retries: Retry-After when the response has one, otherwise 60 s (the 60-per-minute 429 sends none).
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
    000) echo "No response. Check the network and the base URL ($API)." >&2 ;;
    401) echo "Check the key and send it exactly as 'Authorization: Bearer sk_live_...'." >&2 ;;
    402) echo "Not enough available credits (the upload reserves rows x data types). GET /credits shows availableCredits." >&2 ;;
    403) echo "SUBSCRIPTION_REQUIRED or SUBSCRIPTION_PAUSED: start or resume your plan in the app." >&2 ;;
    413) echo "The file is over 100 MB. Split it and upload the parts." >&2 ;;
  esac
  exit 1
}

# Upload. Uploads accept no idempotency key, so this script never retries one except after a 429.
# dataTypes: list each type once (["phone"], ["email"] or ["phone","email"]).
call POST /bulk/upload --max-time 300 -F "file=@$IN;type=text/csv" -F 'dataTypes=["phone","email"]'
[ "$STATUS" = 200 ] || fail
JOB=$(str_of jobId)
echo "Job $JOB accepted: $(num_of recordCount) row(s), $(num_of creditsPerMatch) data type(s) per row"
SKIPPED=$(num_of skippedCount)
if [ -n "$SKIPPED" ]; then echo "Skipped $SKIPPED row(s), not charged: $(str_of skippedReason)"; fi

# Poll every 10 s. Each poll counts toward the key's 60 requests per minute.
while :; do
  call GET "/bulk/$JOB/status" --max-time 60
  [ "$STATUS" = 200 ] || fail
  STATE=$(str_of status)
  PROGRESS=$(num_of progress)
  echo "status: ${STATE:-unknown}${PROGRESS:+ ($PROGRESS%)}"
  case "$STATE" in
    completed) echo "Matched rows: $(num_of numMatches)"; break ;;
    failed)
      echo "Job failed: $(str_of errorMessage)" >&2
      echo "A failed job can still finish later. Check its status again before uploading the same file again." >&2
      exit 1 ;;
  esac  # uploading, queued, processing, or any new value: keep polling
  sleep 10
done

# layout=standard: your columns, then Match Found, Phone 1-6 with Line Type 1-6, Mobile 1-3,
# Landline 1-3, Email 1... Without it you get the older layout, kept unchanged for existing integrations.
call GET "/bulk/$JOB/download?layout=standard&format=csv" --max-time 600
[ "$STATUS" = 200 ] || fail
mv "$TMP/body" "$OUT"
echo "Saved $OUT"
