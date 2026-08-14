/**
 * privacy_fixtures.mjs — generate parity goldens for the Dart masking pipeline
 * by running the SHIPPED JavaScript pipeline under node.
 *
 * The Dart port must reproduce these byte for byte. Nothing here is hand
 * written: every expected value comes from executing portraitor_v3's real
 * pipeline, so the goldens cannot drift from the shipped behaviour.
 *
 * The fake detector is read from test/golden/fake_spans.json, the SAME file the
 * Dart tests read. It is never reimplemented here. If it were written twice,
 * node and Dart could detect different spans and every golden would be measured
 * against a different baseline than the code under test.
 *
 * Usage:
 *   node tool/privacy_fixtures.mjs
 *   PRIVACY_WEB_DIR=/path/to/portraitor_v3/privacy node tool/privacy_fixtures.mjs
 *
 * Writes:
 *   test/golden/label_cases.json   normalizePrivacyLabel inputs -> outputs
 *   test/golden/mask_cases.json    maskText end-to-end results
 */
import { createRequire } from "node:module";
import { readFileSync, writeFileSync, rmSync, existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const webDir =
  process.env.PRIVACY_WEB_DIR ??
  resolve(repoRoot, "../portraitor_v3/privacy");

if (!existsSync(resolve(webDir, "pipeline/index.ts"))) {
  console.error(
    `Cannot find the web pipeline at ${webDir}.\n` +
      `Set PRIVACY_WEB_DIR to portraitor_v3/privacy.`,
  );
  process.exit(1);
}

// esbuild lives in the web project's node_modules, not this repo's. Resolve it
// from there rather than adding a node dependency to a Flutter app.
const webRequire = createRequire(resolve(webDir, "package.json"));
let esbuild;
try {
  esbuild = webRequire("esbuild");
} catch {
  console.error(`esbuild not installed. Run: cd ${webDir} && npm install`);
  process.exit(1);
}

/** Bundle a TypeScript entry point into loadable ESM. */
async function load(entry, tmpName) {
  const tmp = resolve(webDir, tmpName);
  await esbuild.build({
    entryPoints: [resolve(webDir, entry)],
    bundle: true,
    format: "esm",
    platform: "node",
    outfile: tmp,
    logLevel: "error",
  });
  const mod = await import(`${tmp}?t=${Date.now()}`);
  rmSync(tmp, { force: true });
  return mod;
}

const { maskText } = await load("pipeline/index.ts", ".fixtures.index.mjs");
const { normalizePrivacyLabel } = await load(
  "pipeline/labels.ts",
  ".fixtures.labels.mjs",
);

// ── labels ──────────────────────────────────────────────────────────────────
// Every alias, plus the whitespace/case handling of trim().toLowerCase(), plus
// inputs that must fall through to "unknown".
const labelInputs = [
  "person name", "person", "name", "private_person",
  "email address", "email", "private_email",
  "phone number", "phone", "private_phone",
  "url", "private_url",
  "date of birth", "date", "timestamp", "private_date",
  "street address", "address", "private_address",
  "account number", "account_number",
  "api key", "secret",
  "username", "unknown",
  "PERSON NAME", "Person Name", "  person name  ", "\tEMAIL\n",
  "", "   ", "not a label", "person_name", "e-mail", "URL",
  "Account Number", "API KEY", "ACCOUNT_NUMBER",
];

const labelCases = labelInputs.map((input) => ({
  input,
  expected: normalizePrivacyLabel(input),
}));

writeFileSync(
  resolve(repoRoot, "test/golden/label_cases.json"),
  JSON.stringify({ cases: labelCases }, null, 2) + "\n",
);

// ── maskText end to end ─────────────────────────────────────────────────────
const fake = JSON.parse(
  readFileSync(resolve(repoRoot, "test/golden/fake_spans.json"), "utf8"),
);

const maskCases = [];
for (const { name, text, spans } of fake.cases) {
  // Validate the recorded offsets before trusting them, so a hand-edited
  // fixture fails here rather than silently producing a wrong golden.
  for (const s of spans) {
    if (text.slice(s.start, s.end) !== s.spanText) {
      throw new Error(
        `fake_spans.json case "${name}": span ${s.start}..${s.end} is ` +
          `"${text.slice(s.start, s.end)}" but spanText says "${s.spanText}"`,
      );
    }
  }

  const detect = async () => spans;
  const { maskedText, entities, csv, leaks } = await maskText(text, detect);
  maskCases.push({ name, text, maskedText, entities, csv, leaks });
}

writeFileSync(
  resolve(repoRoot, "test/golden/mask_cases.json"),
  JSON.stringify({ cases: maskCases }, null, 2) + "\n",
);

console.log(`label_cases.json  ${labelCases.length} cases`);
console.log(`mask_cases.json   ${maskCases.length} cases`);
for (const c of maskCases) {
  const leaked = c.leaks.length ? ` leaks=${c.leaks.length}` : "";
  console.log(`  ${c.name}: ${c.entities.length} entities${leaked}`);
}
