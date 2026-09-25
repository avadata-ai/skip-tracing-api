// Single-record skip trace with the Ava Data API (POST /standard-search). Node.js 18+.
// Usage: AVADATA_API_KEY=sk_live_... node standard-search.mjs LAST_NAME [FIRST_NAME] [ADDRESS] [CITY] [STATE] [ZIP]
// Charges 1 credit (2¢) per data type per match; a search with no match costs nothing.
const API = "https://app.avadata.ai/api/v1";
const key = process.env.AVADATA_API_KEY;
const [lastName, firstName, address, city, state, zip] = process.argv.slice(2);
if (!key || !lastName) {
  console.error("Usage: AVADATA_API_KEY=sk_live_... node standard-search.mjs LAST_NAME [FIRST_NAME] [ADDRESS] [CITY] [STATE] [ZIP]");
  process.exit(1);
}

const body = Object.fromEntries(
  Object.entries({ firstName, lastName, address, city, state, zip }).filter(([, v]) => v),
);
body.dataTypes = ["phone", "email"];

const res = await fetch(`${API}/standard-search`, {
  method: "POST",
  headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
  body: JSON.stringify(body),
});
const json = await res.json();
if (!res.ok || !json.success) {
  console.error(`HTTP ${res.status}: ${json.error ?? "request failed"}`);
  process.exit(1);
}

const { matchFound, creditsCharged, phones = [], emails = [] } = json.data;
console.log(matchFound ? `Match: ${creditsCharged} credit(s) charged` : "No match: nothing charged");
for (const p of phones) console.log("phone:", p.number, p.type ?? "");
for (const e of emails) console.log("email:", e.address);
