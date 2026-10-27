// Bulk skip trace a CSV with the Ava Data API: upload, poll, download the results in the standard layout.
// Node.js 18+, run as an ES module.
// Usage: AVADATA_API_KEY=sk_live_... node bulk-skip-trace.mjs input.csv [results.csv]
// Start from sample-bulk.csv in this folder and replace its rows with your own records.
// CSV rules: a header row, UTF-8, no line breaks inside cells, at most 100 MB and 250,000 rows. Each row
// needs First Name + Last Name + ZIP, First Name + Last Name + City + State, or Street Address + City +
// State + ZIP; an address column alone is not enough. Headers are matched by exact name, not mapped (the
// accepted names are in the README). Rows without a combination are skipped and never charged; your other
// columns, such as an ID, come back unchanged in the results.
// Credits: rows x data types are reserved at upload; each row is charged 1 credit (2¢) per requested data
// type it actually returned, and the rest is released.
import { readFile, writeFile } from "node:fs/promises";
import { basename } from "node:path";

const API = process.env.AVADATA_BASE_URL ?? "https://app.avadata.ai/api/v1";
const key = process.env.AVADATA_API_KEY;
const [input, output = "results.csv"] = process.argv.slice(2);
if (!key || !input) {
  console.error("Usage: AVADATA_API_KEY=sk_live_... node bulk-skip-trace.mjs input.csv [results.csv]");
  process.exit(1);
}

const HINTS = {
  401: "Check the key and send it exactly as 'Authorization: Bearer sk_live_...'.",
  402: "Not enough available credits (the upload reserves rows x data types). GET /credits shows availableCredits.",
  403: "SUBSCRIPTION_REQUIRED or SUBSCRIPTION_PAUSED: start or resume your plan in the app.",
  413: "The file is over 100 MB. Split it and upload the parts.",
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// One request. On 429 it waits and retries: Retry-After when the response has one, otherwise 60 s
// (the 60-per-minute 429 sends none). Returns `data` (or the raw response with raw: true); any other
// error throws with the API's message.
async function api(path, { method = "GET", body, raw = false, timeout = 60_000 } = {}) {
  for (let attempt = 1; ; attempt++) {
    const res = await fetch(`${API}${path}`, {
      method,
      headers: { Authorization: `Bearer ${key}` },
      body,
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
    if (res.ok && json?.success) return json.data;
    const code = json?.code ? ` ${json.code}` : "";
    const hint = HINTS[res.status] ? `\n${HINTS[res.status]}` : "";
    throw new Error(`HTTP ${res.status}${code}: ${json?.error ?? text.slice(0, 300)}${hint}`);
  }
}

try {
  // Upload. Uploads accept no idempotency key, so this script never retries one except after a 429.
  const form = new FormData();
  form.append("file", new Blob([await readFile(input)], { type: "text/csv" }), basename(input));
  form.append("dataTypes", JSON.stringify(["phone", "email"])); // list each type once
  const job = await api("/bulk/upload", { method: "POST", body: form, timeout: 300_000 });
  console.log(`Job ${job.jobId} accepted: ${job.recordCount} row(s), ${job.creditsPerMatch} data type(s) per row`);
  if (job.skippedCount) console.log(`Skipped ${job.skippedCount} row(s), not charged: ${job.skippedReason}`);

  // Poll every 10 s. Each poll counts toward the key's 60 requests per minute.
  for (;;) {
    const s = await api(`/bulk/${job.jobId}/status`);
    console.log(`status: ${s.status} (${s.progress ?? 0}%)`);
    if (s.status === "completed") {
      console.log(`Matched rows: ${s.numMatches ?? 0}`);
      break;
    }
    if (s.status === "failed") {
      throw new Error(`Job failed: ${s.errorMessage ?? "no reason given"}\n` +
        "A failed job can still finish later. Check its status again before uploading the same file again.");
    }
    await sleep(10_000); // uploading, queued, processing, or any new value: keep polling
  }

  // layout=standard: your columns, then Match Found, Phone 1-6 with Line Type 1-6, Mobile 1-3,
  // Landline 1-3, Email 1... Without it you get the older layout, kept unchanged for existing integrations.
  const res = await api(`/bulk/${job.jobId}/download?layout=standard&format=csv`, { raw: true, timeout: 600_000 });
  await writeFile(output, Buffer.from(await res.arrayBuffer()));
  console.log(`Saved ${output}`);
} catch (err) {
  console.error(err.cause ? `No response (${err.cause.code ?? err.cause.message}). Check the network and the base URL (${API}).` : err.message);
  process.exit(1);
}
