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

// ── per-module goldens ──────────────────────────────────────────────────────
// One file per ported module so each can be tested in isolation. Generated
// centrally rather than by each porter, so the modules cannot disagree about
// what the inputs were.
const { highRiskSpans, detectHighRisk } = await load(
  "pipeline/highRisk.ts",
  ".fixtures.highrisk.mjs",
);
const { detectChatStructure } = await load(
  "pipeline/chatStructure.ts",
  ".fixtures.chatstructure.mjs",
);
const { propagateDetectedNames } = await load(
  "pipeline/names.ts",
  ".fixtures.names.mjs",
);
const { mergeOverlappingSpans } = await load(
  "pipeline/spans.ts",
  ".fixtures.spans.mjs",
);
const { buildPseudonymMap, applyPseudonymization } = await load(
  "pipeline/pseudonymize.ts",
  ".fixtures.pseudonymize.mjs",
);

// Texts that exercise the structured detectors. The fake_spans texts alone do
// not reach OTP, password, SSN, card or street-address paths.
const regexCorpus = [
  "mail me bob@example.com or visit https://x.io/a and www.y.co/b",
  "call +44 20 7946 0321 or 020 7946 0321 today",
  "IBAN GB29NWBK60161331926819 and account no: 12345678901",
  "sort code 40-47-84, routing number 021000021",
  "my ssn is 123-45-6789 and IC 900101-14-5678",
  "card 4242 4242 4242 4242 and 4242-4242-4242-4241",
  "your OTP is 483920, verification code 12345",
  "password: hunter2! and pwd = s3cr3tval",
  "api key sk-abcdefghijklmnopqrstuvwxyz012345 and ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123",
  "hash 5f4dcc3b5aa765d61d8327deb882cf995f4dcc3b5aa765d61d8327deb882cf99",
  "token abcDEF123456789012345678901234567890abcdEF12 here",
  "passport no A1234567 and national id 900101145678",
  "we live at Jalan Bukit Bintang 12 and 221B Baker Street now",
  "[24/02/2025, 11:41:30 PM] pick a ball: hello there",
  "24/02/2025, 11:41 - Mac Chai: hi @CK and @⁦Zoe⁩",
  "[24/02/2025, 11:41:30 PM] ~ Push Name: with a push-name prefix",
  "‎[24/02/2025, 11:41:30 PM] ‎Bidi Speaker: marked line",
  "[24/02/2025, 11:41:30 PM] Messages and calls are end-to-end encrypted",
  "no pii at all in this line",
  "",
];

const structuralTexts = [...fake.cases.map((c) => c.text), ...regexCorpus];

const jsonOf = (v) => JSON.parse(JSON.stringify(v));

writeFileSync(
  resolve(repoRoot, "test/golden/highrisk_cases.json"),
  JSON.stringify(
    {
      cases: structuralTexts.map((text) => ({
        text,
        raw: jsonOf(detectHighRisk(text)),
        spans: jsonOf(highRiskSpans(text)),
      })),
    },
    null,
    2,
  ) + "\n",
);

writeFileSync(
  resolve(repoRoot, "test/golden/chatstructure_cases.json"),
  JSON.stringify(
    {
      cases: structuralTexts.map((text) => ({
        text,
        spans: jsonOf(detectChatStructure(text)),
      })),
    },
    null,
    2,
  ) + "\n",
);

// names, spans and pseudonymize take spans as input. Feed them the real
// intermediate state from the fake_spans cases, exactly as index.ts composes it.
const namesCases = [];
const spansCases = [];
const pseudoCases = [];

for (const { name, text, spans } of fake.cases) {
  const modelSpans = spans.map((e) => ({
    label: normalizePrivacyLabel(e.label),
    text: e.spanText,
    start: e.start,
    end: e.end,
    score: e.score ?? 0,
    source: "openai_privacy_filter",
  }));
  const structural = detectChatStructure(text);
  const personSpans = [...structural, ...modelSpans];

  const propagated = propagateDetectedNames(personSpans, text);
  namesCases.push({
    name,
    text,
    input: jsonOf(personSpans),
    output: jsonOf(propagated),
  });

  const all = [...highRiskSpans(text), ...propagated];
  const merged = mergeOverlappingSpans(all);
  spansCases.push({ name, input: jsonOf(all), output: jsonOf(merged) });

  const map = buildPseudonymMap(merged);
  pseudoCases.push({
    name,
    text,
    spans: jsonOf(merged),
    map: jsonOf(map),
    applied: applyPseudonymization(text, merged, map),
  });
}

// The leakage backstop runs on ALREADY-MASKED text, so it is fed the real
// first-pass output rather than raw chat, plus texts that deliberately place a
// leak next to a token to exercise the token guard.
const { applyLeakageBackstop } = await load(
  "pipeline/leakage.ts",
  ".fixtures.leakage.mjs",
);

const leakageCases = pseudoCases.map((c) => {
  const result = applyLeakageBackstop(c.applied, c.map);
  return {
    name: c.name,
    maskedText: c.applied,
    existingMap: c.map,
    text: result.text,
    leaks: jsonOf(result.leaks),
    map: jsonOf(result.map),
    spans: jsonOf(result.spans),
  };
});

for (const [name, maskedText, existingMap] of [
  ["guard_leak_inside_token", "[EMAIL1] and [ACCOUNT12] stay put", {}],
  ["guard_leak_beside_token", "[PERSON1] mail a@b.com now", {}],
  ["guard_no_leak", "[PERSON1] said hello to [PERSON2]", {}],
  ["numbering_continues", "reach me at x@y.co", { "private_email:old@z.co": "[EMAIL7]" }],
  ["token_adjacent_no_space", "[PERSON1]a@b.com", {}],
]) {
  const result = applyLeakageBackstop(maskedText, existingMap);
  leakageCases.push({
    name,
    maskedText,
    existingMap,
    text: result.text,
    leaks: jsonOf(result.leaks),
    map: jsonOf(result.map),
    spans: jsonOf(result.spans),
  });
}

writeFileSync(
  resolve(repoRoot, "test/golden/leakage_cases.json"),
  JSON.stringify({ cases: leakageCases }, null, 2) + "\n",
);

writeFileSync(
  resolve(repoRoot, "test/golden/names_cases.json"),
  JSON.stringify({ cases: namesCases }, null, 2) + "\n",
);
writeFileSync(
  resolve(repoRoot, "test/golden/spans_cases.json"),
  JSON.stringify({ cases: spansCases }, null, 2) + "\n",
);
writeFileSync(
  resolve(repoRoot, "test/golden/pseudonymize_cases.json"),
  JSON.stringify({ cases: pseudoCases }, null, 2) + "\n",
);

console.log(`label_cases.json          ${labelCases.length} cases`);
console.log(`mask_cases.json           ${maskCases.length} cases`);
console.log(`highrisk_cases.json       ${structuralTexts.length} cases`);
console.log(`chatstructure_cases.json  ${structuralTexts.length} cases`);
console.log(`names_cases.json          ${namesCases.length} cases`);
console.log(`leakage_cases.json        ${leakageCases.length} cases`);
console.log(`spans_cases.json          ${spansCases.length} cases`);
console.log(`pseudonymize_cases.json   ${pseudoCases.length} cases`);
for (const c of maskCases) {
  const leaked = c.leaks.length ? ` leaks=${c.leaks.length}` : "";
  console.log(`  ${c.name}: ${c.entities.length} entities${leaked}`);
}
