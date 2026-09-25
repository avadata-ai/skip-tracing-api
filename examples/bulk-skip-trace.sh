#!/usr/bin/env bash
# Bulk skip trace a CSV with the Ava Data API: upload, poll, download.
# Usage: AVADATA_API_KEY=sk_live_... ./bulk-skip-trace.sh input.csv [results.csv]
# The CSV needs a header row and at minimum an "address" column; firstName, lastName, city,
# state and zip columns narrow each search. 1 credit (2¢) per data type per match.
set -euo pipefail
: "${AVADATA_API_KEY:?Set AVADATA_API_KEY to your Ava Data API key}"
IN="${1:?Usage: $0 input.csv [results.csv]}"
OUT="${2:-results.csv}"
API="https://app.avadata.ai/api/v1"
AUTH="Authorization: Bearer $AVADATA_API_KEY"

UPLOAD=$(curl -sS -X POST "$API/bulk/upload" -H "$AUTH" -F "file=@$IN" -F 'dataTypes=["phone","email"]')
JOB=$(printf '%s' "$UPLOAD" | sed -n 's/.*"jobId" *: *"\([^"]*\)".*/\1/p')
if [ -z "$JOB" ]; then echo "Upload failed: $UPLOAD" >&2; exit 1; fi
echo "Job $JOB accepted"

while :; do
  STATUS_JSON=$(curl -sS "$API/bulk/$JOB/status" -H "$AUTH")
  STATUS=$(printf '%s' "$STATUS_JSON" | sed -n 's/.*"status" *: *"\([^"]*\)".*/\1/p')
  PROGRESS=$(printf '%s' "$STATUS_JSON" | sed -n 's/.*"progress" *: *\([0-9]*\).*/\1/p')
  echo "status: ${STATUS:-unknown}${PROGRESS:+ ($PROGRESS%)}"
  case "$STATUS" in
    completed) break ;;
    failed) echo "Job failed: $STATUS_JSON" >&2; exit 1 ;;
    "") echo "Unexpected response: $STATUS_JSON" >&2; exit 1 ;;
  esac
  sleep 5
done

curl -sS -f "$API/bulk/$JOB/download?format=csv" -H "$AUTH" -o "$OUT"
echo "Saved $OUT"
