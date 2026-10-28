// Build a property list with the Ava Data List Builder API: preview (free) -> create (with an
// Idempotency-Key) -> poll -> read the first records -> download the CSV. Node.js 18+, run as an ES module.
// Usage: AVADATA_API_KEY=sk_live_... node list-builder.mjs STATE KIND VALUE [MAX_RECORDS] [list.csv]
// Example: node list-builder.mjs AZ county Maricopa 25 maricopa.csv
// KIND is city, county or zip (5 digits). MAX_RECORDS (default 25, at most 100,000) caps the pull.
// Credits: 1 credit (2¢) per record pulled. The cap is reserved when the list is created; you are charged
// for the records actually pulled and the rest is released. Edit `filters` below to change the search;
// GET /lists/filters returns every allowed value. List Builder must be enabled for the account.
import { randomUUID } from "node:crypto";
import { writeFile } from "node:fs/promises";

const API = process.env.AVADATA_BASE_URL ?? "https://app.avadata.ai/api/v1";
const key = process.env.AVADATA_API_KEY;
const [state, kind, value, maxArg = "25", output = "list.csv"] = process.argv.slice(2);
if (!key || !value || !/^\d+$/.test(maxArg)) {
  console.error("Usage: AVADATA_API_KEY=sk_live_... node list-builder.mjs STATE KIND VALUE [MAX_RECORDS] [list.csv]");
  process.exit(1);
}

const HINTS = {
  401: "Check the key and send it exactly as 'Authorization: Bearer sk_live_...'.",
  402: "Not enough available credits for the reservation. GET /credits shows availableCredits.",
  403: "LIST_BUILDER_DISABLED: List Builder isn't on for this account. SUBSCRIPTION_REQUIRED or SUBSCRIPTION_PAUSED: start or resume your plan in the app.",
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

class ApiError extends Error {
  constructor(status, json, text) {
    const code = json?.code ? ` ${json.code}` : "";
    const field = json?.field ? ` (field: ${json.field})` : "";
    const hint = HINTS[status] ? `\n${HINTS[status]}` : "";
    super(`HTTP ${status}${code}: ${json?.error ?? text.slice(0, 300)}${field}${hint}`);
    this.status = status;
  }
}

// One request. On 429 (code RATE_LIMITED for the 60-per-minute key limit, or a List Builder code) it
// waits the Retry-After seconds, or 60 s if the header is missing, then retries. Responses also carry
// X-RateLimit-Limit, X-RateLimit-Remaining and X-RateLimit-Reset for the key limit; counts are kept per
// server instance, so treat them as a guide and wait on Retry-After. Returns { data, res } (res alone
// with raw: true); any other error throws an ApiError with the API's message.
async function api(path, { method = "GET", body, headers = {}, raw = false, timeout = 60_000 } = {}) {
  for (let attempt = 1; ; attempt++) {
    const res = await fetch(`${API}${path}`, {
      method,
      headers: { Authorization: `Bearer ${key}`, ...(body ? { "Content-Type": "application/json" } : {}), ...headers },
      body: body ? JSON.stringify(body) : undefined,
      signal: AbortSignal.timeout(timeout),
    });
    const wait = Number(res.headers.get("retry-after") ?? 60);
    if (res.status === 429 && attempt < 5 && wait <= 300) {
      console.error(`Rate limited (HTTP 429), retrying in ${wait}s`);
      await sleep(wait * 1000);
      continue;
    }
    if (raw && res.ok) return res;
    const text = await res.text();
    let json = null;
    try { json = JSON.parse(text); } catch {}
    if (res.ok && json?.success) return { data: json.data, res };
    throw new ApiError(res.status, json, text);
  }
}

const filters = {
  location: { state, kind, values: [value] },
  quicklists: ["absentee-owner", "high-equity"],
  quicklistMatch: "all",
};

try {
  // 1. Preview: counts matches and shows the cost. Free (20 per minute, 250 per UTC day per account).
  let preview;
  for (let attempt = 1; ; attempt++) {
    try {
      ({ data: preview } = await api("/lists/preview", { method: "POST", body: { filters, maxRecords: Number(maxArg) } }));
      break;
    } catch (err) {
      if (!(err instanceof ApiError && err.status === 503 && attempt < 3)) throw err;
      console.error("Match count unavailable right now (503), retrying in 10s");
      await sleep(10_000);
    }
  }
  console.log(`Preview: ${preview.matchCount} match(es); pulling ${preview.recordsToPull} record(s) costs about ${preview.estimatedCredits} credit(s)`);
  if (preview.recordsToPull === 0) {
    console.log("Nothing to pull: no list was created and nothing was charged.");
    process.exit(0);
  }

  // 2. Create. maxRecords = the preview's recordsToPull, so only the credits needed are reserved.
  // One Idempotency-Key per list, sent again on every retry: a retry after a timeout, 409 or 5xx
  // returns the original list (header Idempotent-Replayed: true) instead of creating and charging twice.
  const idempotencyKey = randomUUID();
  const body = { name: `${state} ${kind} ${value} absentee high equity`, maxRecords: preview.recordsToPull, filters };
  let list;
  for (let attempt = 1; ; attempt++) {
    try {
      const { data, res } = await api("/lists", { method: "POST", body, headers: { "Idempotency-Key": idempotencyKey }, timeout: 120_000 });
      list = data;
      if (res.headers.get("idempotent-replayed") === "true") console.log("(replayed: this list already existed, nothing was charged twice)");
      break;
    } catch (err) {
      const retryable = !(err instanceof ApiError) || err.status === 409 || err.status >= 500;
      if (!retryable || attempt >= 5) throw err;
      console.error(`Create not confirmed (${err.status ? `HTTP ${err.status}` : `no response: ${err.cause?.code ?? err.name}`}), retrying with the same Idempotency-Key in 10s`);
      await sleep(10_000);
    }
  }
  console.log(`List ${list.listId} created, ${list.creditsReserved} credit(s) reserved`);

  // 3. Poll every 10 s until completed or failed. Any other value, including new ones, means still pulling.
  while (list.status !== "completed" && list.status !== "failed") {
    await sleep(10_000);
    ({ data: list } = await api(`/lists/${list.listId}`));
    console.log(`status: ${list.status} (${list.progress}%), ${list.recordCount} record(s)`);
  }
  if (list.status === "failed") {
    console.error(list.errorMessage);
    if (list.recordCount === 0) process.exit(1);
  }

  // 4. Read the first records as JSON (free). Default columns; add &columns=key1,key2 for others (up to 35).
  const { data: page } = await api(`/lists/${list.listId}/records?limit=5&offset=0`);
  for (const r of page.records) {
    console.log(`${r.propertyId}  ${r.propStreet ?? ""}, ${r.propCity ?? ""}, ${r.propState ?? ""} ${r.propZip ?? ""}  owner: ${r.ownerName ?? "-"}  [${(r.quickListFlags ?? []).join(", ")}]`);
  }

  // 5. Download every record as CSV (free). Header row = column keys, propertyId first.
  const res = await api(`/lists/${list.listId}/download`, { raw: true, timeout: 600_000 });
  await writeFile(output, Buffer.from(await res.arrayBuffer()));
  console.log(`Saved ${output} (${list.recordCount} record(s), ${list.creditsCharged} credit(s) charged)`);
} catch (err) {
  console.error(err.cause ? `No response (${err.cause.code ?? err.cause.message}). Check the network and the base URL (${API}).` : err.message);
  process.exit(1);
}
