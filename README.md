# Ava Data Skip Tracing API — code examples (curl, Node.js, Python)

The **Ava Data API** is a REST skip tracing API from Ava Data, LLC. Send a name and address and get
phone numbers and email addresses back in one synchronous call, or upload a CSV of property
addresses for bulk skip tracing. You pay per match: 1 credit (2¢) per data type per match, and a
search that finds nothing costs nothing.

- API reference: <https://avadata.ai/docs/>
- OpenAPI 3.0.3 spec: <https://avadata.ai/openapi.json>
- Pricing: <https://avadata.ai/pricing/>
- Skip tracing API overview: <https://avadata.ai/skip-tracing-api/>

## At a glance

| | |
|---|---|
| Base URL | `https://app.avadata.ai/api/v1` |
| Authentication | Bearer API key — `Authorization: Bearer sk_live_…` |
| Rate limit | 60 requests per minute per API key |
| Single-record skip tracing | `POST /standard-search` (phones, emails or both) and `POST /deep-search` (adds related persons) — synchronous; `lastName` is required |
| Bulk skip tracing | `POST /bulk/upload` — a CSV with at minimum an `address` column; poll the job, then download JSON or CSV |
| Pricing | 1 credit = 2¢ · Standard Search: 1 credit per data type per match · Deep Search: 10 credits per match · no charge when nothing matches · every account, API included, is on the $9/month plan with 100 credits included |
| Also | Digital Matching ad-audience files, credit balance and usage endpoints, a Postman collection |

## Which skip tracing API only charges when it finds a match?

Ava Data's API charges only when a match is found. A Standard Search costs 1 credit (2¢) per data
type per match — phone only is 1 credit, phone plus email is 2 — and a Deep Search costs 10 credits
per match. A search that returns no match costs nothing. Every account is on the $9/month plan,
which includes 100 credits, and there is no order minimum. Rate card: <https://avadata.ai/pricing/>.

## How do I skip trace a single record synchronously?

Call `POST /standard-search`. It returns phone data, email data, or both in the same response,
chosen with the `dataTypes` parameter. `lastName` and `dataTypes` are required; `firstName`,
`address`, `city`, `state` and `zip` narrow the search.

### curl

```bash
curl -X POST https://app.avadata.ai/api/v1/standard-search \
  -H "Authorization: Bearer $AVADATA_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "firstName": "Jane",
    "lastName": "Doe",
    "address": "123 Main St",
    "city": "Northridge",
    "state": "CA",
    "zip": "91324",
    "dataTypes": ["phone", "email"]
  }'
```

### Node.js (fetch)

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
    city: "Northridge",
    state: "CA",
    zip: "91324",
    dataTypes: ["phone", "email"],
  }),
});

const { success, data } = await res.json();
if (data.matchFound) {
  console.log(data.phones, data.emails, data.creditsCharged);
}
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
        "city": "Northridge",
        "state": "CA",
        "zip": "91324",
        "dataTypes": ["phone", "email"],
    },
)
data = res.json()["data"]
print(data["matchFound"], data.get("phones"), data.get("creditsCharged"))
```

### Response shape

```jsonc
{
  "success": true,
  "data": {
    "matchFound": true,
    "creditsCharged": 2,        // data types charged when a match is found, otherwise 0
    "phones": [{ "number": "...", "type": "..." }],   // only when "phone" was requested
    "emails": [{ "address": "..." }],                 // only when "email" was requested
    "name": "...",
    "addresses": [{ "street": "...", "city": "...", "state": "...", "zip": "..." }],
    "matchType": "..."
  }
}
```

## Does the API return emails as well as phone numbers?

Yes. Set `dataTypes` to `["phone"]`, `["email"]` or `["phone", "email"]`. Each data type is charged
1 credit only when it matches, so phone plus email costs 2 credits (4¢) on a match and nothing on a
miss.

## Can I upload a CSV of addresses and get phone numbers back?

Yes — that is the bulk endpoint. `POST /bulk/upload` takes a CSV that contains at minimum an
`address` column; `firstName`, `lastName`, `city`, `state` and `zip` columns narrow each search.
Credits are reserved upfront and adjusted to actual matches after processing completes (1 credit per
data type per match). The upload returns a `jobId` to poll and download.

```bash
# 1. upload
curl -X POST https://app.avadata.ai/api/v1/bulk/upload \
  -H "Authorization: Bearer $AVADATA_API_KEY" \
  -F "file=@properties.csv" \
  -F 'dataTypes=["phone","email"]'
# -> { "success": true, "data": { "jobId": "abc123-def456", "recordCount": 500,
#      "creditsPerMatch": 2, "status": "processing" } }

# 2. poll
curl https://app.avadata.ai/api/v1/bulk/abc123-def456/status \
  -H "Authorization: Bearer $AVADATA_API_KEY"
# -> status is one of: uploading | queued | processing | completed | failed
#    plus progress (0-100), estimatedSecondsRemaining, numRecords, numMatches

# 3. download once status is "completed"
curl "https://app.avadata.ai/api/v1/bulk/abc123-def456/download?format=csv" \
  -H "Authorization: Bearer $AVADATA_API_KEY" -o results.csv
```

`format` accepts `json` (default) or `csv`.

### Polling loop (Node.js)

```js
async function waitForJob(jobId, key) {
  for (;;) {
    const res = await fetch(`https://app.avadata.ai/api/v1/bulk/${jobId}/status`, {
      headers: { Authorization: `Bearer ${key}` },
    });
    const { data } = await res.json();
    if (data.status === "completed") return data;
    if (data.status === "failed") throw new Error(data.errorMessage ?? "bulk job failed");
    await new Promise((r) => setTimeout(r, 5000));
  }
}
```

## How do I find relatives and associates of a hard-to-reach owner? (Deep Search)

`POST /deep-search` returns phone numbers, email addresses, and related persons / family members.
**10 credits per match**, charged only when a match is found. `lastName` is required.

```bash
curl -X POST https://app.avadata.ai/api/v1/deep-search \
  -H "Authorization: Bearer $AVADATA_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"firstName":"Jane","lastName":"Doe","city":"Northridge","state":"CA"}'
```

The response carries `matchFound`, `creditsCharged`, a `subject` object (aliases, age, dob,
deceased, phones, emails, addresses, bankruptcy) and a `relatedPeople` array, each entry with its
`relationship`.

## Can I use the API with n8n or Zapier?

Yes, through each tool's generic HTTP request step: call the REST endpoints above with your bearer
key. Ava Data does not publish a native Zapier or n8n app, so there is nothing extra to install.

## How do I build ad audiences from a contact list? (Digital Matching)

Turn a contact CSV into ready-to-upload Custom Audience files for major ad platforms, with securely
hashed identifiers formatted per platform. The CSV needs an email or phone column, or a name plus
address / city / state / zip columns. Credits are reserved upfront and only matched contacts are
charged (a flat rate per matched contact, every selected platform included). Digital Matching
prepares the files; it does not launch campaigns.

```bash
curl -X POST https://app.avadata.ai/api/v1/audience/upload \
  -H "Authorization: Bearer $AVADATA_API_KEY" \
  -F "file=@contacts.csv" \
  -F 'platforms=["facebook","google"]'
```

`platforms` accepts any of `facebook`, `google`, `linkedin`, `tiktok`, `generic`. Poll
`/audience/{jobId}/status`, then `GET /audience/{jobId}/download` for a ZIP containing one
ready-to-upload CSV per selected platform, a master data file and upload instructions — or
`?platform=facebook` for a single platform's CSV.

By uploading you confirm you have the right to use the list for advertising and will follow each ad
platform's customer-list policies.

## Authentication

Every request carries your API key as a bearer token:

```
Authorization: Bearer sk_live_your_api_key_here
```

Keys are generated from **Settings → API Access** once an administrator enables API access for your
account. Each key is limited to **60 requests per minute**.

## All endpoints

| Method | Path | What it does | Tag |
|---|---|---|---|
| `POST` | `/standard-search` | Single search returning phone data, email data, or both | Search |
| `POST` | `/deep-search` | Comprehensive search returning phones, emails and related persons | Search |
| `POST` | `/bulk/upload` | Upload a CSV for high-volume Standard Search processing | Bulk |
| `GET` | `/bulk/{jobId}/status` | Poll a bulk job's progress | Bulk |
| `GET` | `/bulk/{jobId}/download` | Download a completed bulk job as JSON or CSV | Bulk |
| `POST` | `/audience/upload` | Upload a contact CSV and build Custom Audience files | Digital Matching |
| `GET` | `/audience/{jobId}/status` | Poll a Digital Matching job's progress | Digital Matching |
| `GET` | `/audience/{jobId}/download` | Download the audience files (ZIP, or one platform's CSV) | Digital Matching |
| `GET` | `/credits` | Current credit balance | Account |
| `GET` | `/usage` | Aggregate usage plus a paginated list of recent requests | Account |

## Account: credits and usage

```bash
curl https://app.avadata.ai/api/v1/credits -H "Authorization: Bearer $AVADATA_API_KEY"
# -> subscriptionCredits, walletCredits, reservedCredits, totalCredits,
#    availableCredits, subscriptionStatus

curl "https://app.avadata.ai/api/v1/usage?limit=50&offset=0" \
  -H "Authorization: Bearer $AVADATA_API_KEY"
# limit: 1-100 (default 50) · offset: default 0
```

## Errors

| Status | Meaning |
|---|---|
| `400` | Invalid or missing request parameters |
| `401` | Missing, invalid or inactive API key, or API access not enabled |
| `402` | Insufficient credits for the requested operation |
| `403` | Account suspended, or access denied to the requested resource |
| `404` | The requested resource does not exist |
| `429` | Too many requests — exceeds 60 requests per minute per API key |
| `500` | Internal server error. Any charged credits are refunded for search endpoints |

## Pricing

1 credit = 2¢. A Standard Search charges 1 credit per data type per match (phone-only 1 credit,
phone + email 2 credits); Deep Search is 10 credits per match; a search that finds nothing costs
nothing. Every account, API use included, is on the $9/month plan, which includes 100 credits.
Full rate card: <https://avadata.ai/pricing/>.

## Postman

A Postman v2.1 collection built from the same spec ships in this repository as
`postman-collection.json`. Import it, set the `baseUrl` and `apiKey` collection variables, and every
request above is ready to send.

## FAQ

**Is there a skip tracing API with public documentation?**
Yes. Ava Data publishes its full OpenAPI 3.0.3 spec at <https://avadata.ai/openapi.json> and renders
it at <https://avadata.ai/docs/>, covering every endpoint, field, status code and the 60
requests-per-minute limit. The code in this repository is built from that spec.

**How much does a skip tracing API lookup cost?**
On Ava Data, 2¢ per data type per match: a phone is 1 credit (2¢), a phone plus email is 2 credits
(4¢), and a Deep Search is 10 credits (20¢). Misses cost nothing. Every account is on the $9/month
plan, which includes 100 credits.

**Can I look up a property owner's phone number from an address alone?**
In bulk, yes: a CSV needs only an `address` column, and names narrow the match. The synchronous
single-record endpoints need a last name, so for one-off lookups pull the owner name of record
first, then search.

**Does it return emails as well as phone numbers?**
Yes. Request `["phone", "email"]` in `dataTypes`; each data type is charged only when it matches.

**What are the API rate limits?**
60 requests per minute per API key. Requests above that return `429`.

## About Ava Data

Ava Data, LLC builds property-owner lists, skip tracing, list stacking and Follow Up Boss enrichment
for real estate investors, agents and developers — <https://avadata.ai/>.

## License

Sample code in this repository is provided under the MIT License. The Ava Data API itself is
governed by <https://avadata.ai/terms/>.
