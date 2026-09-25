#!/usr/bin/env bash
# Single-record skip trace with the Ava Data API (POST /standard-search).
# Usage: AVADATA_API_KEY=sk_live_... ./standard-search.sh LAST_NAME [FIRST_NAME] [ADDRESS] [CITY] [STATE] [ZIP]
# Charges 1 credit (2¢) per data type per match; a search with no match costs nothing.
set -euo pipefail
: "${AVADATA_API_KEY:?Set AVADATA_API_KEY to your Ava Data API key}"
if [ $# -lt 1 ]; then
  echo "Usage: $0 LAST_NAME [FIRST_NAME] [ADDRESS] [CITY] [STATE] [ZIP]" >&2
  exit 1
fi

json_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
field() { if [ -n "$2" ]; then printf ',"%s":"%s"' "$1" "$(json_escape "$2")"; fi; }

BODY="{\"lastName\":\"$(json_escape "$1")\"$(field firstName "${2:-}")$(field address "${3:-}")$(field city "${4:-}")$(field state "${5:-}")$(field zip "${6:-}"),\"dataTypes\":[\"phone\",\"email\"]}"

curl -sS -X POST "https://app.avadata.ai/api/v1/standard-search" \
  -H "Authorization: Bearer $AVADATA_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$BODY"
echo
