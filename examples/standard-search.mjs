// Single-record skip trace with the Ava Data API (POST /standard-search). Node.js 18+, run as an ES module.
// Usage: AVADATA_API_KEY=sk_live_... node standard-search.mjs LAST_NAME [FIRST_NAME] [ADDRESS] [CITY] [STATE] [ZIP]
// Example: node standard-search.mjs Doe Jane "123 Main St" Austin TX 78701
// The API validates only lastName up front, but a search needs a name plus street + ZIP, or city + state
// (otherwise 400 INSUFFICIENT_INPUT). A match charges 1 credit (2¢) per requested data type, even a type
// that comes back empty; a search with no match costs nothing. Run it on a server: the API sends no CORS
// headers, and the key must stay out of browsers and apps.
const API = process.env.AVADATA_BASE_URL ?? "https://app.avadata.ai/api/v1";
const key = process.env.AVADATA_API_KEY;
const [lastName, firstName, address, city, state, zip] = process.argv.slice(2);
if (!key || !lastName) {
  console.error("Usage: AVADATA_API_KEY=sk_live_... node standard-search.mjs LAST_NAME [FIRST_NAME] [ADDRESS] [CITY] [STATE] [ZIP]");
  process.exit(1);
}

const HINTS = {
  401: "Check the key and send it exactly as 'Authorization: Bearer sk_live_...'.",
  402: "Not enough available credits. GET /credits shows availableCredits.",
  403: "SUBSCRIPTION_REQUIRED or SUBSCRIPTION_PAUSED: start or resume your plan in the app.",
  500: "Search service error. Any credits taken were refunded; it is safe to retry shortly.",
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// POST JSON and return `data`. On 429 (code RATE_LIMITED, 60 requests per minute per key) it waits the
// Retry-After seconds, or 60 s if the header is missing, then retries. Responses also carry
// X-RateLimit-Limit, X-RateLimit-Remaining and X-RateLimit-Reset; counts are kept per server instance, so
// treat them as a guide and wait on Retry-After. Any other error throws with the API's message.
async function api(path, body) {
  for (let attempt = 1; ; attempt++) {
    const res = await fetch(`${API}${path}`, {
      method: "POST",
      headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(60_000),
    });
    const wait = Number(res.headers.get("retry-after") ?? 60);
    if (res.status === 429 && attempt < 5 && wait <= 300) {
      console.error(`Rate limited (HTTP 429), retrying in ${wait}s`);
      await sleep(wait * 1000);
      continue;
    }
    const text = await res.text();
    let json = null;
    try { json = JSON.parse(text); } catch {}
    if (res.ok && json?.success) return json.data;
    const code = json?.code ? ` ${json.code}` : "";
    const hint = HINTS[res.status] ? `\n${HINTS[res.status]}` : "";
    throw new Error(`HTTP ${res.status}${code}: ${json?.error ?? text.slice(0, 300)}${hint}`);
  }
}

const body = Object.fromEntries(
  Object.entries({ firstName, lastName, address, city, state, zip }).filter(([, v]) => v),
);
body.dataTypes = ["phone", "email"]; // list each type once: a repeated type is charged again

try {
  const data = await api("/standard-search", body);
  if (!data.matchFound) {
    console.log("No match: nothing charged");
  } else {
    // phones: [{ number, lineType? }], emails: strings, name: { first, last }, addresses: [{ address, city, state, zip, zip4? }]
    const { creditsCharged, matchType, name = {}, phones = [], emails = [], addresses = [] } = data;
    console.log(`Match: ${creditsCharged} credit(s) charged`);
    console.log(`name: ${[name.first, name.last].filter(Boolean).join(" ")} (${matchType ?? "unknown"} match)`);
    for (const p of phones) console.log("phone:", p.number, p.lineType ?? "");
    for (const e of emails) console.log("email:", e);
    for (const a of addresses) console.log(`address: ${a.address}, ${a.city}, ${a.state} ${a.zip}${a.zip4 ? `-${a.zip4}` : ""}`);
    if (matchType === "Household") console.log("Household match: a phone or email may belong to someone else at the address.");
  }
} catch (err) {
  if (err.name === "TimeoutError") {
    console.error("Timed out. Searches accept no idempotency key: this one may still have run and been charged. Check your balance (GET /credits) before retrying.");
  } else if (err.cause) {
    console.error(`No response (${err.cause.code ?? err.cause.message}). Check the network and the base URL (${API}).`);
  } else {
    console.error(err.message);
  }
  process.exit(1);
}
