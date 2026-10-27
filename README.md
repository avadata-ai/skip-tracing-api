# Ava Data API: code examples (curl, Node.js, Python)

[In-app API docs](https://app.avadata.ai/api-docs) (sign in) · [OpenAPI file](https://app.avadata.ai/api/v1/openapi.json) · [Pricing](https://avadata.ai/pricing/) · [Terms](https://avadata.ai/terms/) · [Postman collection](postman-collection.json) · **[Create an account →](https://app.avadata.ai/register)**

Runnable examples for the Ava Data REST API from Ava Data, LLC:

- **Skip tracing.** Phones and emails for one person (`POST /standard-search`, `POST /deep-search`), or for a
  whole CSV as a background job (`POST /bulk/upload`).
- **List Builder.** Property lists built with the same filters as the app's List Builder page, read as JSON or
  downloaded as CSV (`/lists`).
- **Digital Matching.** Custom Audience files for ad platforms, built from a contact CSV (`/audience`).

The base URL is `https://app.avadata.ai/api/v1`, and every path in this README is relative to it:
`POST /standard-search` means `POST https://app.avadata.ai/api/v1/standard-search`.

## Quick start

1. **Create an account** at [app.avadata.ai/register](https://app.avadata.ai/register) and start the $9/month
   plan, which includes 100 credits. Until a plan is active, searches, uploads and List Builder previews and pulls
   return `403` with code `SUBSCRIPTION_REQUIRED`.
2. **Generate a key** in the app under **Settings → API Access → Generate New Key**. Copy it right away: it is
   shown only once.
3. **Keep the key on your server**, in an environment variable:

   ```bash
   export AVADATA_API_KEY=sk_live_your_api_key_here
   ```

4. **Check the key with a free call:**

   ```bash
   curl https://app.avadata.ai/api/v1/credits -H "Authorization: Bearer $AVADATA_API_KEY"
   ```

5. **Run a search** (1 credit per data type on a match, nothing on a miss):

   ```bash
   ./examples/standard-search.sh Doe Jane "123 Main St" Austin TX 78701
   ```

The full reference is the [in-app API docs](https://app.avadata.ai/api-docs) (sign in to the app first) and the
OpenAPI 3 file at <https://app.avadata.ai/api/v1/openapi.json>, which needs no key.

## Is there a sandbox or test mode?

No. There are no test keys and no sandbox: every key is a live `sk_live_` key, and every search runs on real data
and spends real credits when it matches. A request refused with a 4xx status is never charged. The cheapest ways
to test:

| To check | Call | Cost |
|---|---|---|
| The key, the header and your balance | `GET /credits`, `GET /usage` | Free |
| A List Builder search | `POST /lists/preview` | Free (250 per account per UTC day) |
| A single search end to end | `POST /standard-search` with `"dataTypes": ["phone"]` on a person you know | 1 credit (2¢) on a match, 0 on a miss |
| The bulk flow | `POST /bulk/upload` with a 2-3 row CSV and `["phone"]` | At most 1 credit per row |
| A list pull | `POST /lists` with `"maxRecords": 1` | At most 1 credit |

Deep Search needs 10 available credits to start, even when the result ends up free.

## Runnable examples

| Task | Bash (curl) | Node.js 18+ | Python 3 (`requests`) |
|---|---|---|---|
| Skip trace one record | [`standard-search.sh`](examples/standard-search.sh) | [`standard-search.mjs`](examples/standard-search.mjs) | [`standard_search.py`](examples/standard_search.py) |
| Bulk skip trace a CSV (upload → poll → download) | [`bulk-skip-trace.sh`](examples/bulk-skip-trace.sh) | [`bulk-skip-trace.mjs`](examples/bulk-skip-trace.mjs) | [`bulk_skip_trace.py`](examples/bulk_skip_trace.py) |
| Build a property list (preview → create → poll → records → CSV) | [`list-builder.sh`](examples/list-builder.sh) | [`list-builder.mjs`](examples/list-builder.mjs) | [`list_builder.py`](examples/list_builder.py) |

[`examples/sample-bulk.csv`](examples/sample-bulk.csv) is a valid bulk input file with one row for each accepted
column combination. Replace its rows with your own records before you upload it.

Every script:

- reads the key from `AVADATA_API_KEY`, and the base URL from `AVADATA_BASE_URL` (default
  `https://app.avadata.ai/api/v1`);
- takes its inputs as arguments and prints its usage when one is missing;
- checks the HTTP status and `success`, prints the API's `error` (with `code` and `field` when present) and a
  hint, and exits non-zero on failure;
- on `429`, waits for the `Retry-After` value when the response has one, otherwise 60 seconds, then retries;
- treats a no-match as a normal result, not an error;
- sends each data type once.

The bash scripts need curl, and print fields with [jq](https://jqlang.github.io/jq/) when it is installed (raw
JSON otherwise). The Node scripts are ES modules that use the built-in `fetch`. The Python scripts need
`pip install requests`.

## At a glance

| | |
|---|---|
| Base URL | `https://app.avadata.ai/api/v1` |
| Authentication | `Authorization: Bearer sk_live_…` on every request |
| Where to call it from | Your server. The API sends no CORS headers, so browsers block calls from web pages, and a key in browser or app code can be copied by anyone |
| Rate limit | 60 requests per minute per API key, on every endpoint |
| Request limits | JSON bodies up to 1 MB (`413 BODY_TOO_LARGE`). CSV uploads up to 100 MB, sent as `multipart/form-data` in a field named `file` (`413 FILE_TOO_LARGE`) |
| Row limits | Bulk: 250,000 rows per file. Digital Matching: 50,000 rows per file. List Builder: 100,000 records per list |
| Test mode | None (see above) |
| Pricing | 1 credit = 2¢. Standard Search 1 credit per requested data type per match, Deep Search 10 when contact data is found, bulk 1 per data type returned, List Builder 1 per record. Details under [Pricing](#pricing) |

## Authentication and key handling

Send the key as a bearer token on every request:

```
Authorization: Bearer sk_live_your_api_key_here
```

- The header must start with exactly `Bearer sk_live_`. A lowercase `bearer` or a missing prefix returns
  `401 Invalid or missing API key`; a mistyped or revoked key returns `401 Invalid or inactive API key`. The other
  `401` messages are `API access is not enabled for this account` and `Account is suspended`. None of them has a
  `code`.
- A key is shown once and can't be recovered. An account can hold more than one active key, so you can rotate
  without downtime: generate a new key, deploy it, then revoke the old one under **Settings → API Access**. A
  revoked key stops working on its next request.
- Keep keys on your server, in an environment variable or a secret store, and out of source control and client
  code. The [Terms](https://avadata.ai/terms/) (section 2) make you responsible for keeping API keys
  confidential and for telling support@avadata.ai promptly if you believe one has been compromised.

## Rate limits, retries and idempotency

- **60 requests per minute per API key, on every endpoint.** Every request made with a valid key counts,
  including status polls, downloads and requests that return an error. The window is a fixed 60 seconds that
  starts with the first request after the previous window ended.
- **This 429 has no `Retry-After` header, no rate-limit headers and no `code`.** The body is
  `{"success": false, "error": "Rate limit exceeded. Maximum 60 requests per minute."}`. Wait 60 seconds, then
  retry, and slow down if it happens again. Poll job status every 5-10 seconds, not faster.
- **List Builder adds its own limits**, each with a `code`: `PREVIEW_MINUTE_LIMIT` (20 previews a minute per
  account, `Retry-After: 60`), `PREVIEW_DAILY_LIMIT` (250 a UTC day, with `resetsAt` and `Retry-After`),
  `ACTIVE_PULL_LIMIT` (5 lists pulling at once), `DOWNLOAD_LIMIT` (2 downloads at once), `SKIP_TRACE_IN_PROGRESS`
  (one skip trace set-up at a time per account) and `SKIP_TRACE_BUSY` (`Retry-After: 10`). Only the codes shown
  with `Retry-After` send it. Honor it when it is sent; otherwise wait before you retry.
- **Only `POST /lists` and `POST /lists/{listId}/skip-trace` accept an `Idempotency-Key` header** (1-255 visible
  ASCII characters, no spaces, kept for 24 hours). Sending the same key and body again returns the original
  response with the header `Idempotent-Replayed: true`, with no second list or charge. The same key with a
  different body returns `400 IDEMPOTENCY_KEY_REUSED`; a retry while the first request is still running returns
  `409 IDEMPOTENCY_IN_PROGRESS`, so retry shortly with the same key.
- **Searches and CSV uploads accept no idempotency key.** Sending one again runs it again: a search is charged
  again, and an upload starts a second job with a second credit reservation. Give searches a generous client
  timeout (the examples use 60 seconds), and after a timeout check your balance with `GET /credits` before you
  retry.
- A search that fails with `500 Search service temporarily unavailable. Credits have been refunded.` was refunded
  and is safe to retry after a short wait.

## How do I skip trace a single record? (Standard Search)

`POST /standard-search` returns phones, emails or both for one person, chosen with `dataTypes`.

- **Input.** Only `lastName` and `dataTypes` are checked up front, but the search needs a name plus a complete
  address: street + ZIP, or city + state. Without one it returns `400` with code `INSUFFICIENT_INPUT`, and nothing
  is charged. Send `Content-Type: application/json`. Unknown fields such as `first_name` are ignored without an
  error, and a missing field returns `400` with the error `Required` and no field name.
- **dataTypes.** `["phone"]`, `["email"]` or `["phone", "email"]`. List each type once: duplicates are not
  removed, so `["phone", "phone"]` is charged 2 credits per match.
- **Billing.** 1 credit per requested type is taken before the search, so that many must be available
  (`402 Insufficient credits` otherwise). On a match every requested type is charged, even a type that comes back
  empty (`"emails": []`). A search with no match is refunded and reports `creditsCharged: 0`. Total your spend from
  `creditsCharged`.

### curl

```bash
curl -X POST https://app.avadata.ai/api/v1/standard-search \
  -H "Authorization: Bearer $AVADATA_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "firstName": "Jane",
    "lastName": "Doe",
    "address": "123 Main St",
    "city": "Austin",
    "state": "TX",
    "zip": "78701",
    "dataTypes": ["phone", "email"]
  }'
```

### Node.js (fetch, ES module)

```js
const res = await fetch("https://app.avadata.ai/api/v1/standard-search", {
  method: "POST",
  headers: {
    Authorization: `Bearer ${process.env.AVADATA_API_KEY}`,
    "Content-Type": "application/json",
  },
  body: JSON.stringify({
    firstName: "Jane",
    lastName: "Doe",
    address: "123 Main St",
    city: "Austin",
    state: "TX",
    zip: "78701",
    dataTypes: ["phone", "email"], // each type once
  }),
  signal: AbortSignal.timeout(60_000),
});

const body = await res.json();
if (!res.ok || !body.success) {
  throw new Error(`HTTP ${res.status}${body.code ? ` ${body.code}` : ""}: ${body.error}`);
}
const { matchFound, creditsCharged, phones = [], emails = [] } = body.data;
console.log(matchFound ? `Match: ${creditsCharged} credit(s)` : "No match: nothing charged");
for (const p of phones) console.log("phone:", p.number, p.lineType ?? "");
for (const e of emails) console.log("email:", e); // emails are plain strings
```

### Python (requests)

```python
import os, requests

res = requests.post(
    "https://app.avadata.ai/api/v1/standard-search",
    headers={"Authorization": f"Bearer {os.environ['AVADATA_API_KEY']}"},
    json={
        "firstName": "Jane",
        "lastName": "Doe",
        "address": "123 Main St",
        "city": "Austin",
        "state": "TX",
        "zip": "78701",
        "dataTypes": ["phone", "email"],  # each type once
    },
    timeout=60,
)
payload = res.json()
if not res.ok or not payload.get("success"):
    raise SystemExit(f"HTTP {res.status_code} {payload.get('code', '')}: {payload.get('error')}")

data = payload["data"]
print(f"Match: {data['creditsCharged']} credit(s)" if data["matchFound"] else "No match: nothing charged")
for phone in data.get("phones", []):
    print("phone:", phone["number"], phone.get("lineType", ""))
for email in data.get("emails", []):
    print("email:", email)  # emails are plain strings
```

### Response

```jsonc
// Match
{
  "success": true,
  "data": {
    "matchFound": true,
    "phones": [                                   // only when "phone" was requested
      { "number": "5125550101", "lineType": "Mobile" },
      { "number": "(512) 555-0102" }              // lineType is left out when unknown
    ],
    "emails": ["jane.doe@example.com"],           // only when "email" was requested; plain strings
    "name": { "first": "Jane", "last": "Doe" },
    "addresses": [
      { "address": "123 Main St", "city": "Austin", "state": "TX", "zip": "78701", "zip4": "1234" }
    ],
    "matchType": "Household",                     // "Individual" or "Household"
    "creditsCharged": 2
  }
}

// No match
{ "success": true, "data": { "matchFound": false, "creditsCharged": 0 } }
```

- `name`, `addresses` and `matchType` come with every match. Fields with no value are left out rather than sent as
  `null`.
- `phones` can hold several numbers: up to two mobiles first, then a landline, then the rest.
- `lineType` is free text (for example `Mobile` or `Landline`), so compare it case-insensitively. Numbers are
  returned as found and may be formatted, so normalize them before you store or dial them.
- `zip4` is a separate field, left out when unknown.
- `Household` means a phone or email may belong to someone else at the address, not the named person.

## Does the API return emails as well as phone numbers?

Yes. Set `dataTypes` to `["phone"]`, `["email"]` or `["phone", "email"]`. On a match, Standard Search charges
1 credit for each requested type, so phone plus email costs 2 credits (4¢) on a match and nothing on a miss. In
bulk, a row is charged only for the types it actually returns.

## How do I find relatives and associates of a hard-to-reach owner? (Deep Search)

`POST /deep-search` returns phones, emails and related people for one person. `lastName` is required;
`firstName`, `address`, `city`, `state` and `zip` narrow the search. Deep Search looks people up by name. A
company, LLC or trust name in `lastName` won't find the owner, so send a person's name. For an address with no
owner name, or a property owned by a company, LLC or trust, use a bulk upload with Street + City + State + ZIP
instead.

- **Billing.** 10 credits must be available to start (`402` otherwise). They are kept only when the result
  includes a phone, an email or a related person, and refunded otherwise, so `matchFound: true` with
  `creditsCharged: 0` is a normal result. Total your spend from `creditsCharged`, not from `matchFound`.
- A search that matches too many people returns `400` with code `INSUFFICIENT_INPUT`, and nothing is charged: add
  a first name, a ZIP, or a city and state.

```bash
curl -X POST https://app.avadata.ai/api/v1/deep-search \
  -H "Authorization: Bearer $AVADATA_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"firstName":"Jane","lastName":"Doe","city":"Austin","state":"TX"}'
```

```jsonc
{
  "success": true,
  "data": {
    "matchFound": true,
    "subject": {                                  // only when matchFound is true
      "firstName": "Jane",
      "lastName": "Doe",
      "aliases": ["Jane A Doe"],                  // aliases, age and dob are left out when unknown
      "age": 52,
      "deceased": false,
      "phones": [{ "number": "5125550101", "lineType": "Mobile", "disconnected": false }],
      "emails": ["jane.doe@example.com"],
      "addresses": [{ "address": "123 Main St", "city": "Austin", "state": "TX", "zip": "78701-1234" }],
      "bankruptcy": false
    },
    "relatedPeople": [
      {
        "firstName": "John",
        "lastName": "Doe",
        "age": 54,
        "deceased": false,
        "relationship": "Spouse",
        "phones": [{ "number": "5125550111", "lineType": "Landline", "disconnected": false }],
        "emails": [],                             // always empty for related people
        "addresses": [],                          // always empty for related people
        "bankruptcy": false
      }
    ],
    "creditsCharged": 10
  }
}
```

- Deep Search phone numbers have dashes, parentheses and spaces removed, emails are lowercased strings, and `zip`
  can be ZIP+4 (`78701-1234`).
- `disconnected` is `true` when the number is flagged as disconnected. `deceased` and `bankruptcy` are always
  booleans; `false` means no record was found, not that it was confirmed.
- `relationship` is one of Spouse, Parent, Child, Sibling, Other Relative, Roommate, Neighbor, Business Associate,
  Relative, Associate or Related.
- A no-match is `{"matchFound": false, "creditsCharged": 0}`.

## Can I upload a CSV of property owners and get phone numbers back? (Bulk)

Yes: `POST /bulk/upload` skip traces a CSV as a background job. Upload the file, poll the job, then download the
results with `layout=standard`.

### Input file rules

- A header row, then one record per line. UTF-8. No line breaks inside a cell (rows are split on line breaks).
  At most 100 MB and 250,000 rows (`400 Batch size exceeds limit` with `maxBatchSize`).
- Each row needs **one** of these combinations, or it is skipped:
  - First Name + Last Name + ZIP
  - First Name + Last Name + City + State
  - Street Address + City + State + ZIP
- **An address column alone is not enough**, and an address without city, state and ZIP does not count. A file
  whose columns can't meet any combination is refused with
  `400 The CSV columns can't produce any matches.`; a file where no row meets one returns `400` with
  `invalidCount`.
- Headers are matched by exact name, case-insensitive. The API does no column mapping (the mapping step is in the
  app's upload screen only), so rename your columns to one of these:

  | Field | Accepted headers |
  |---|---|
  | Street address | `address`, `street`, `street address` |
  | First name | `first name`, `firstname`, `first` |
  | Last name | `last name`, `lastname`, `last` |
  | Full name, used when the first or last name column is missing | `name`, `full name`, `fullname`, `owner name`, `owner` |
  | City | `city` |
  | State | `state`, `st` |
  | ZIP | `zip`, `zipcode`, `zip code`, `postal code` |

  Headers such as `first_name`, `zip_code` or `address1` are not recognized and are ignored without an error. A
  full-name column counts as First + Last Name, except for company names (LLC, Inc. and so on), which only count
  with the full street address, city, state and ZIP.
- Other columns, such as your own record ID, are kept and come back in the results. Include an ID column so you
  can join results back to your data.
- Rows that meet no combination are skipped and never charged. The upload response then adds `skippedCount` and
  `skippedReason`, and `recordCount` counts only the rows that will be searched.

### Sample CSV

[`examples/sample-bulk.csv`](examples/sample-bulk.csv) has one row per combination:

```csv
Record ID,First Name,Last Name,Address,City,State,Zip
1001,Jane,Doe,123 Main St,Austin,TX,78701
1002,John,Smith,,,,78701
1003,Maria,Lopez,,Phoenix,AZ,
1004,,,456 Oak Ave,Denver,CO,80202
```

### Credits

At upload, `recordCount` × the number of data types is reserved (`402` with `needed`, `available`, `reserved`
and `total` if that many aren't available). When the job finishes, each row is charged 1 credit for each
requested type it actually returned, and the rest of the reservation is released. `dataTypes` duplicates are not
removed at upload, so `["phone","phone"]` reserves twice as much; list each type once.

### Upload, poll, download (curl)

```bash
# 1. Upload. dataTypes is a JSON array string; list each type once.
curl -X POST https://app.avadata.ai/api/v1/bulk/upload \
  -H "Authorization: Bearer $AVADATA_API_KEY" \
  -F "file=@examples/sample-bulk.csv;type=text/csv" \
  -F 'dataTypes=["phone","email"]'
# -> {"success":true,"data":{"jobId":"abc123-def456","lookupId":"...","recordCount":4,
#     "dataTypes":["phone","email"],"creditsPerMatch":2,"status":"processing","message":"Processing 4 records. ..."}}
#    plus "skippedCount" and "skippedReason" when rows were skipped

# 2. Poll every 5-10 seconds until status is completed or failed.
curl https://app.avadata.ai/api/v1/bulk/abc123-def456/status \
  -H "Authorization: Bearer $AVADATA_API_KEY"
# -> {"success":true,"data":{"jobId":"abc123-def456","status":"processing","progress":60,
#     "estimatedSecondsRemaining":30,"numRecords":4,"numMatches":0,"errorMessage":null}}

# 3. Download the standard layout as CSV.
curl "https://app.avadata.ai/api/v1/bulk/abc123-def456/download?layout=standard&format=csv" \
  -H "Authorization: Bearer $AVADATA_API_KEY" -o results.csv
```

Uploads accept no idempotency key: sending the same upload again starts a second job.

### Job status

- `status` is `pending`, `uploading`, `queued`, `processing`, `completed` or `failed`. The upload response says
  `processing`, but the first polls can show `uploading` or `queued`. Treat any value other than `completed` or
  `failed` as still running.
- There are no webhooks; polling is the only way to know a job is done, and each poll counts toward the 60
  requests per minute.
- `failed`: the job stopped, its reserved credits were released and `errorMessage` says why. Rarely, a job marked
  failed turns out to have finished: its status then changes to `completed` and its matches are charged. Before
  you upload the same file again, check the status once more a few minutes later.
- Results stay available to download until you delete the upload from History in the app. Downloading a job that
  isn't completed returns `400 Job is not completed yet`.

### Results

Always pass `layout=standard`. The standard layout is your uploaded columns, then `Match Found` (`Yes` or `No`),
`Phone 1`-`Phone 6` with `Line Type 1`-`Line Type 6`, `Mobile 1`-`Mobile 3`, `Landline 1`-`Landline 3`, and
`Email 1`, `Email 2`… when emails were requested.

- `format=csv` returns that table as a CSV file. Cells that start with `=`, `+`, `@` (or `-` when the value isn't a
  number) get a leading `'` so spreadsheets don't run them as formulas.
- Without `format` you get JSON:
  `{"success": true, "data": {"jobId", "numRecords", "numMatches", "creditsCharged", "columns": [...], "results": [{...one object per row, keyed by column name...}]}}`.
  Read the rows from `data.results`.
- Skipped rows are not in the results, so join on your ID column, not on row position.
- Without `layout=standard` you get the older layout, kept unchanged for existing integrations: in JSON,
  `data.results` is usually the whole file as one CSV string. Don't build new code on it. Jobs started from a
  list skip trace always use the standard layout.

### Polling loop (Node.js)

```js
async function waitForJob(jobId, key) {
  for (;;) {
    const res = await fetch(`https://app.avadata.ai/api/v1/bulk/${jobId}/status`, {
      headers: { Authorization: `Bearer ${key}` },
    });
    if (res.status === 429) { // no Retry-After on this 429: wait out the 60-second window
      await new Promise((r) => setTimeout(r, 60_000));
      continue;
    }
    const body = await res.json();
    if (!res.ok || !body.success) throw new Error(`HTTP ${res.status}: ${body.error}`);
    if (body.data.status === "completed") return body.data;
    if (body.data.status === "failed") throw new Error(body.data.errorMessage ?? "bulk job failed");
    await new Promise((r) => setTimeout(r, 10_000));
  }
}
```

## How do I build a property list? (List Builder)

List Builder pulls property records with the same filters as the app's List Builder page. List Builder must be
turned on for the account (otherwise `403` with code `LIST_BUILDER_DISABLED`), and these endpoints take an API
key only; being signed in to the app is not enough.

1. `GET /lists/filters` (free) returns every value the `filters` object accepts, including quick lists, property
   types, range fields and record columns.
2. `POST /lists/preview` (free) counts matches and shows the cost.
3. `POST /lists` creates the list and starts the pull. Send an `Idempotency-Key`.
4. `GET /lists/{listId}` until `status` is `completed` or `failed`.
5. `GET /lists/{listId}/records` (JSON pages) or `GET /lists/{listId}/download` (CSV), both free.
6. Optional: `POST /lists/{listId}/skip-trace` runs a bulk skip trace on the list.

**Credits.** 1 credit (2¢) per record pulled. `maxRecords` (1-100,000) credits are reserved when the list is
created; when the pull ends you are charged for the records pulled and the rest is released. Set `maxRecords` to
the preview's `recordsToPull` to hold only what you need. A pull that stops early (`failed`) keeps, and charges
for, the records it already pulled.

```bash
# 1. Preview (free)
curl -X POST https://app.avadata.ai/api/v1/lists/preview \
  -H "Authorization: Bearer $AVADATA_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "filters": {
      "location": { "state": "AZ", "kind": "county", "values": ["Maricopa"] },
      "quicklists": ["absentee-owner", "high-equity"],
      "quicklistMatch": "all"
    },
    "maxRecords": 500
  }'
# -> {"success":true,"data":{"matchCount":1842,"creditsPerRecord":1,"maxRecordsLimit":100000,"maxRecords":500,
#     "recordsToPull":500,"estimatedCredits":500,"creditsToReserve":500}}

# 2. Create. Reuse the same Idempotency-Key when you retry this request.
curl -X POST https://app.avadata.ai/api/v1/lists \
  -H "Authorization: Bearer $AVADATA_API_KEY" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: maricopa-absentee-2026-10-27" \
  -d '{
    "name": "Maricopa absentee high equity",
    "maxRecords": 500,
    "filters": {
      "location": { "state": "AZ", "kind": "county", "values": ["Maricopa"] },
      "quicklists": ["absentee-owner", "high-equity"],
      "quicklistMatch": "all"
    }
  }'
# -> {"success":true,"data":{"listId":"8f14e45f-...","status":"processing","progress":0,"recordCount":0,
#     "maxRecords":500,"creditsReserved":500,"creditsCharged":0,...}}

# 3. Poll every 5-10 seconds
curl https://app.avadata.ai/api/v1/lists/8f14e45f-ea8e-4a3b-9d2c-1b7e6f0a9c31 \
  -H "Authorization: Bearer $AVADATA_API_KEY"

# 4. Read records as JSON (limit up to 500; columns= takes up to 35 column keys from /lists/filters)
curl "https://app.avadata.ai/api/v1/lists/8f14e45f-ea8e-4a3b-9d2c-1b7e6f0a9c31/records?limit=100&offset=0" \
  -H "Authorization: Bearer $AVADATA_API_KEY"

# 5. Download every record as CSV
curl https://app.avadata.ai/api/v1/lists/8f14e45f-ea8e-4a3b-9d2c-1b7e6f0a9c31/download \
  -H "Authorization: Bearer $AVADATA_API_KEY" -o list.csv
```

- `filters.location` is required: one state, one `kind` (`city`, `county` or `zip`) and 1-50 values. ZIP codes
  must be 5 digits. Unknown keys are refused with `400` and a `field` naming the bad path.
- `status` is `processing`, `completed` or `failed`; treat any other value as still processing. It turns
  `completed` or `failed` only once credits are final, so `creditsCharged` is then the final charge.
- Records and downloads need a finished list (`400 LIST_NOT_READY`, or `LIST_FAILED` when a failed list has no
  records). Each record has a `propertyId` that stays the same across lists, so you can use it to remove
  duplicates. JSON values are typed (numbers, `true`/`false`, dates as `YYYY-MM-DD`, arrays, `null` when empty).
  The CSV header row uses column keys with `propertyId` first.
- `POST /lists/{listId}/skip-trace` takes `{"dataTypes": ["phone", "email"]}` (default `["phone"]`) and an
  optional `Idempotency-Key`. It returns a `jobId`; track and download it with the bulk endpoints above. Its
  results always use the standard layout and include the list's `Property ID` column for joining.

## How do I build ad audiences from a contact list? (Digital Matching)

`POST /audience/upload` turns a contact CSV into ready-to-upload Custom Audience files for ad platforms. Digital
Matching must be turned on for the account; otherwise the upload returns
`403 Digital Matching access is not enabled for this account` (no `code`). It prepares the files; it does not
launch campaigns.

```bash
curl -X POST https://app.avadata.ai/api/v1/audience/upload \
  -H "Authorization: Bearer $AVADATA_API_KEY" \
  -F "file=@contacts.csv;type=text/csv" \
  -F 'platforms=["facebook","google"]'
```

- The CSV needs an email or phone column, or a name with city + state, or a name with ZIP, or
  street + city + state + ZIP. Email headers: `email`, `e-mail`, `email address`, `emailaddress`. Phone headers:
  `phone`, `phone number`, `phonenumber`, `mobile`, `cell`, `cell phone`. Name and address headers are the same
  as for bulk. UTF-8, no line breaks inside cells, 100 MB and 50,000 rows per file.
- `platforms` accepts any of `facebook`, `google`, `linkedin`, `tiktok`, `generic`.
- Credits: every row is reserved at the response's `creditsPerMatch`, and only matched contacts are charged,
  all selected platforms included.
- Poll `GET /audience/{jobId}/status`, then `GET /audience/{jobId}/download` for a ZIP with one file per
  selected platform that has matches (`facebook_instagram_custom_audience.csv`, `google_ads_customer_match.csv`,
  `linkedin_contact_list.csv`, `tiktok_customer_file.csv`, `generic_hashed_audience.csv`),
  `master_audience_data.csv` and `README.txt`. Add `?platform=facebook` (one of the job's platforms) for that
  platform's CSV alone.
- The platform files contain hashed identifiers. `master_audience_data.csv` holds your uploaded rows as you sent
  them (not hashed), followed by the appended match columns (the same hashed identifiers). Keep it for reference;
  it isn't meant for upload.

By uploading you confirm you have the right to use the list for advertising and will follow each ad platform's
customer-list policies.

## All endpoints

| Method | Path | What it does | Credits |
|---|---|---|---|
| `POST` | `/standard-search` | Phones, emails or both for one person | 1 per requested type per match |
| `POST` | `/deep-search` | Phones, emails and related people for one person | 10 when contact data is found |
| `POST` | `/bulk/upload` | Upload a CSV for bulk skip tracing | 1 per requested type returned per row |
| `GET` | `/bulk/{jobId}/status` | Poll a bulk job | Free |
| `GET` | `/bulk/{jobId}/download` | Download a completed bulk job (`layout=standard`, `format=csv`) | Free |
| `POST` | `/audience/upload` | Upload a contact CSV for Digital Matching | `creditsPerMatch` per matched contact |
| `GET` | `/audience/{jobId}/status` | Poll a Digital Matching job | Free |
| `GET` | `/audience/{jobId}/download` | Download the audience files (ZIP, or one platform's CSV) | Free |
| `GET` | `/lists/filters` | Every allowed List Builder filter value and column | Free |
| `POST` | `/lists/preview` | Count matches and estimate the cost | Free |
| `POST` | `/lists` | Create a list and start the pull | 1 per record pulled |
| `GET` | `/lists` | Your lists, newest first | Free |
| `GET` | `/lists/{listId}` | One list's status, progress and credits | Free |
| `GET` | `/lists/{listId}/records` | A page of records as JSON | Free |
| `GET` | `/lists/{listId}/download` | Every record as CSV | Free |
| `POST` | `/lists/{listId}/skip-trace` | Skip trace a completed list as a bulk job | 1 per requested type returned per record |
| `GET` | `/credits` | Credit balance | Free |
| `GET` | `/usage` | Usage totals and recent API requests | Free |
| `GET` | `/openapi.json` | The OpenAPI 3 file (no key needed) | Free |

## Account: credits and usage

```bash
curl https://app.avadata.ai/api/v1/credits -H "Authorization: Bearer $AVADATA_API_KEY"
# -> subscriptionCredits, walletCredits, reservedCredits, totalCredits, availableCredits, subscriptionStatus

curl "https://app.avadata.ai/api/v1/usage?limit=50&offset=0" \
  -H "Authorization: Bearer $AVADATA_API_KEY"
# -> stats {totalRequests, totalCreditsUsed, requestsToday, requestsThisMonth},
#    recentActivity [{id, endpoint, method, statusCode, creditsUsed, timestamp}], pagination {limit, offset, hasMore}
```

- `availableCredits` is what a new search, upload or list can use: total credits minus those reserved by running
  jobs.
- `/usage` lists requests made with your API keys. `limit` is 1-100 (default 50; larger values are reduced to 100)
  and `offset` defaults to 0. `creditsUsed` is 0 on bulk, Digital Matching and list-create requests, because those
  are charged when the job finishes. `hasMore` is true whenever the page is full, even on the last page.

## Errors

Every error body is `{"success": false, "error": "..."}`, sometimes with `code`, `field` and extra fields.
Branch on the HTTP status first: many errors carry no `code`. Ignore fields and codes you don't recognize; new
ones can be added to v1.

| Status | Meaning | Codes and extra fields | Retry? |
|---|---|---|---|
| `400` | Invalid request | `INSUFFICIENT_INPUT` (search input too thin or too broad), `INVALID_JSON`, `INVALID_UPLOAD`, `LIST_NOT_READY`, `LIST_FAILED`, `LIST_EMPTY`, `INVALID_IDEMPOTENCY_KEY`, `IDEMPOTENCY_KEY_REUSED`, `UNSUPPORTED_CONTENT_TYPE`. List Builder, `/usage` and the bulk `layout` check add `field`; bulk uploads add `invalidCount` or `maxBatchSize`. Search validation errors have no code | No, fix the request |
| `401` | Missing, invalid or revoked key, API access turned off, or account suspended | No code | No |
| `402` | Not enough available credits | Bulk, Digital Matching and List Builder add `needed`, `available`, `reserved`, `total`; searches send only `Insufficient credits` | After adding credits |
| `403` | No active plan, a paused plan, a feature not enabled, or another account's job or list | `SUBSCRIPTION_REQUIRED`, `SUBSCRIPTION_PAUSED` (with `resumeAt`), `LIST_BUILDER_DISABLED`; the Digital Matching gate has no code | No |
| `404` | Job or list not found, or an unknown path or method (a JSON body, never `405`) | | No |
| `409` | A request with this `Idempotency-Key` is still running | `IDEMPOTENCY_IN_PROGRESS` | Yes, shortly, with the same key |
| `413` | Too large | `BODY_TOO_LARGE` (JSON over 1 MB), `FILE_TOO_LARGE` (upload over 100 MB) | No |
| `429` | Rate limited | No code on the 60-per-minute limit; List Builder codes listed above | Yes: after `Retry-After`, or 60 seconds when there is none |
| `500` | Server error | A search 500 says credits were refunded | Searches: yes, after a short wait |
| `503` | List preview count unavailable | `PREVIEW_UNAVAILABLE` | Yes |

## Pricing

1 credit = 2¢.

- **Standard Search:** 1 credit per requested data type whenever a match is found, even for a type that comes
  back empty. No match costs nothing.
- **Deep Search:** 10 credits when the result includes a phone, an email or a related person; otherwise nothing.
- **Bulk and list skip traces:** 1 credit for each requested data type a row actually returns. Rows × data types
  are reserved up front and the rest is released when the job finishes.
- **List Builder:** 1 credit per record pulled. Previews, records and downloads are free.
- **Digital Matching:** `creditsPerMatch` (shown in the upload response) per matched contact, all selected
  platforms included.

Every account, API use included, is on the $9/month plan, which includes 100 credits. Full rate card:
<https://avadata.ai/pricing/>.

## Permitted use

The [Terms of Service](https://avadata.ai/terms/) govern the API. The points that matter most when you build on
it (section 3):

- Ava Data is not a consumer reporting agency, and its data is not a consumer report under the Fair Credit
  Reporting Act. Don't use it to establish eligibility for credit or insurance, employment, housing or tenancy, a
  government license or benefit, or any other purpose the FCRA regulates.
- Don't use it to stalk, harass, threaten or intimidate anyone, to locate a person in violation of a protective or
  restraining order, to discriminate unlawfully, or in any way that violates the Driver's Privacy Protection Act,
  the Gramm-Leach-Bliley Act or applicable state privacy law.
- Ava Data does not make calls or send messages for you, and it does not screen numbers against do-not-call
  registries. API responses carry no do-not-call or consent field. You are solely responsible for complying with
  the TCPA, federal and state do-not-call rules, wireless-consent requirements, calling windows, texting rules and
  every other law on contacting people, including getting any consent those laws require.

## Postman

[`postman-collection.json`](postman-collection.json) is a Postman v2.1 collection with every endpoint above.
Import it and set the `apiKey` collection variable; `baseUrl` is already `https://app.avadata.ai/api/v1`, and
the key is sent as a bearer token. The upload and create requests save `jobId`, `audienceJobId` and `listId` for
the requests that follow, and the List Builder requests create an `Idempotency-Key` that is reused until a
request succeeds, so resending after a failure is a safe retry.

## FAQ

**Can I call the API from a browser or a mobile app?**
No. The API sends no CORS headers, so browsers block calls from web pages, and a key shipped in front-end or app
code can be copied by anyone. Call it from your server.

**Can I look up a property owner's phone number from an address alone?**
In bulk, yes, when each row has the full street address, city, state and ZIP. An address column by itself is
refused. The single-record endpoints look people up by name, so for one-off lookups send the owner's personal
name. For a property owned by a company, LLC or trust, use a bulk upload with Street + City + State + ZIP (a
company name in a full-name column counts only with the full address), or skip trace a List Builder list with
`POST /lists/{listId}/skip-trace`.

**What are the API rate limits?**
60 requests per minute per API key, on every endpoint. The 429 for this limit has no `Retry-After` header: wait 60
seconds, then retry more slowly.

**Can I use the API with n8n or Zapier?**
Yes, through each tool's generic HTTP request step: call the REST endpoints above with your bearer key. Ava Data
does not publish a native Zapier or n8n app.

**Will the API change under me?**
New response fields, error codes and status values can be added to v1. Ignore fields and codes you don't
recognize, and treat a status value you don't recognize as still processing.

## About Ava Data

Ava Data, LLC builds property-owner lists, skip tracing, list stacking and Follow Up Boss enrichment for real
estate investors, agents and developers: <https://avadata.ai/>.

## License

Sample code in this repository is provided under the MIT License. The Ava Data API itself is governed by
<https://avadata.ai/terms/>.
