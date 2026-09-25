// Bulk skip trace a CSV with the Ava Data API: upload, poll, download. Node.js 18+.
// Usage: AVADATA_API_KEY=sk_live_... node bulk-skip-trace.mjs input.csv [results.csv]
// The CSV needs a header row and at minimum an "address" column; firstName, lastName, city,
// state and zip columns narrow each search. 1 credit (2¢) per data type per match.
import { readFile, writeFile } from "node:fs/promises";
import { basename } from "node:path";

const API = "https://app.avadata.ai/api/v1";
const key = process.env.AVADATA_API_KEY;
const [input, output = "results.csv"] = process.argv.slice(2);
if (!key || !input) {
  console.error("Usage: AVADATA_API_KEY=sk_live_... node bulk-skip-trace.mjs input.csv [results.csv]");
  process.exit(1);
}
const auth = { Authorization: `Bearer ${key}` };

async function api(path, init = {}) {
  const res = await fetch(`${API}${path}`, { ...init, headers: { ...auth, ...(init.headers ?? {}) } });
  const json = await res.json();
  if (!res.ok || !json.success) throw new Error(`HTTP ${res.status}: ${json.error ?? "request failed"}`);
  return json.data;
}

const form = new FormData();
form.append("file", new Blob([await readFile(input)], { type: "text/csv" }), basename(input));
form.append("dataTypes", JSON.stringify(["phone", "email"]));
const { jobId, recordCount } = await api("/bulk/upload", { method: "POST", body: form });
console.log(`Job ${jobId} accepted (${recordCount} records)`);

for (;;) {
  const job = await api(`/bulk/${jobId}/status`);
  console.log(`status: ${job.status} (${job.progress ?? 0}%)`);
  if (job.status === "completed") break;
  if (job.status === "failed") throw new Error(job.errorMessage ?? "bulk job failed");
  await new Promise((r) => setTimeout(r, 5000));
}

const res = await fetch(`${API}/bulk/${jobId}/download?format=csv`, { headers: auth });
if (!res.ok) throw new Error(`Download failed: HTTP ${res.status}`);
await writeFile(output, Buffer.from(await res.arrayBuffer()));
console.log(`Saved ${output}`);
