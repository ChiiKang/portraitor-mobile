/**
 * privacy_client_fixtures.mjs — goldens for the client-side privacy functions.
 *
 * Separate from privacy_fixtures.mjs because the source is different in kind.
 * The pipeline is TypeScript modules that esbuild can bundle. These three live
 * in shipped browser JavaScript: two inside an IIFE that attaches to `window`,
 * and one inside app.js's closure. So they are EXECUTED here, from the real
 * source text, rather than reimplemented. Nothing expected is hand written.
 *
 *   unmaskText                 public/assets/modules/privacy-filter.js
 *   buildRedactionFromPipeline public/assets/modules/privacy-filter.js
 *   maskTargetName             public/assets/app.js
 *
 * Depends on test/golden/mask_cases.json for realistic inputs, so run
 * privacy_fixtures.mjs first.
 *
 * Usage:
 *   node tool/privacy_client_fixtures.mjs
 */
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const webRoot =
  process.env.PRIVACY_WEB_ROOT ?? resolve(repoRoot, "../portraitor_v3");

const pfPath = resolve(webRoot, "public/assets/modules/privacy-filter.js");
const appPath = resolve(webRoot, "public/assets/app.js");

for (const p of [pfPath, appPath]) {
  if (!existsSync(p)) {
    console.error(`Cannot find ${p}. Set PRIVACY_WEB_ROOT to portraitor_v3.`);
    process.exit(1);
  }
}

// privacy-filter.js is an IIFE ending in
// `(typeof window !== 'undefined' ? window : this)`. Passing `window` as a
// parameter makes that branch pick our object, so the module attaches itself
// to a sandbox instead of a real browser global.
const fakeWindow = {};
new Function("window", readFileSync(pfPath, "utf8"))(fakeWindow);
const { unmaskText, buildRedactionFromPipeline } =
  fakeWindow.Portraitor.PrivacyFilter;

// maskTargetName is trapped inside app.js's closure and reads the module-level
// `pfMaskResult`. Lift the function's source verbatim and rebind that free
// variable as a parameter. Still the shipped code, just given its dependency.
const appSrc = readFileSync(appPath, "utf8");
const fnMatch = appSrc.match(/ {2}function maskTargetName\(name\) \{[\s\S]*?\n {2}\}/);
if (!fnMatch) {
  console.error("Could not locate maskTargetName in app.js. Has it moved?");
  process.exit(1);
}
const maskTargetName = new Function(
  "pfMaskResult",
  "name",
  `${fnMatch[0]}\nreturn maskTargetName(name);`,
);

const maskCasesPath = resolve(repoRoot, "test/golden/mask_cases.json");
if (!existsSync(maskCasesPath)) {
  console.error("Run node tool/privacy_fixtures.mjs first.");
  process.exit(1);
}
const maskCases = JSON.parse(readFileSync(maskCasesPath, "utf8")).cases;

const jsonOf = (v) => JSON.parse(JSON.stringify(v));

// ── unmaskText ──────────────────────────────────────────────────────────────
// A portrait is prose containing the tokens, so build one per case from the
// entities the pipeline actually produced, then add adversarial shapes.
const unmaskCases = [];

for (const c of maskCases) {
  if (!c.entities.length) continue;
  const tokens = c.entities.map((e) => e.token);
  const portrait =
    `${tokens[0]} shows up as grounded and encouraging. ` +
    tokens.map((t) => `Notes on ${t}.`).join(" ") +
    ` Finally, ${tokens[tokens.length - 1]} again.`;
  unmaskCases.push({
    name: c.name,
    text: portrait,
    entities: c.entities,
    expected: unmaskText(portrait, c.entities),
  });
}

const smokeEntities = maskCases.find((c) => c.name === "smoke").entities;
for (const [name, text, entities] of [
  ["unknown_token_left_alone", "[PERSON9] was never issued", smokeEntities],
  ["no_tokens", "plain prose with no tokens at all", smokeEntities],
  ["empty_text", "", smokeEntities],
  ["no_entities", "[PERSON1] and [EMAIL1] stay put", []],
  ["adjacent_tokens", "[PERSON1][PERSON2] together", smokeEntities],
  ["lowercase_is_not_a_token", "[person1] is not a token", smokeEntities],
  ["no_digits_is_not_a_token", "[PERSON] is not a token", smokeEntities],
  [
    "value_containing_dollar",
    "[PERSON1] earned money",
    [{ token: "[PERSON1]", type: "person", value: "$&Ann$1", count: 1, you: false }],
  ],
]) {
  unmaskCases.push({ name, text, entities, expected: unmaskText(text, entities) });
}

writeFileSync(
  resolve(repoRoot, "test/golden/unmask_cases.json"),
  JSON.stringify({ cases: unmaskCases }, null, 2) + "\n",
);

// ── buildRedactionFromPipeline ──────────────────────────────────────────────
const redactionCases = [];
for (const c of maskCases) {
  const firstPerson = c.entities.find((e) => e.type === "person");
  for (const youName of [null, firstPerson ? firstPerson.value : null]) {
    redactionCases.push({
      name: youName ? `${c.name}__you` : c.name,
      maskedText: c.maskedText,
      entities: c.entities,
      youName,
      expected: jsonOf(buildRedactionFromPipeline(c.maskedText, c.entities, youName)),
    });
  }
}
redactionCases.push({
  name: "orphan_token_without_entity",
  maskedText: "[PERSON1] met [PERSON42] yesterday",
  entities: smokeEntities,
  youName: null,
  expected: jsonOf(
    buildRedactionFromPipeline("[PERSON1] met [PERSON42] yesterday", smokeEntities, null),
  ),
});

writeFileSync(
  resolve(repoRoot, "test/golden/redaction_cases.json"),
  JSON.stringify({ cases: redactionCases }, null, 2) + "\n",
);

// ── maskTargetName ──────────────────────────────────────────────────────────
const targetNameCases = [];
for (const c of maskCases) {
  const person = c.entities.find((e) => e.type === "person");
  const inputs = [
    person ? person.value : "Nobody",
    person ? person.value.toUpperCase() : "NOBODY",
    person ? `  ${person.value}  ` : "  Nobody  ",
    "Someone Not Present",
    "",
  ];
  for (const name of inputs) {
    targetNameCases.push({
      name: `${c.name}:${JSON.stringify(name)}`,
      entities: c.entities,
      input: name,
      expected: maskTargetName({ entities: c.entities }, name),
    });
  }
}
// A non-person entity whose value equals the name must NOT be matched.
targetNameCases.push({
  name: "email_entity_is_not_a_person",
  entities: [
    { token: "[EMAIL1]", type: "email", value: "Dana", count: 1, you: false },
  ],
  input: "Dana",
  expected: maskTargetName(
    { entities: [{ token: "[EMAIL1]", type: "email", value: "Dana", count: 1, you: false }] },
    "Dana",
  ),
});

writeFileSync(
  resolve(repoRoot, "test/golden/target_name_cases.json"),
  JSON.stringify({ cases: targetNameCases }, null, 2) + "\n",
);

console.log(`unmask_cases.json       ${unmaskCases.length} cases`);
console.log(`redaction_cases.json    ${redactionCases.length} cases`);
console.log(`target_name_cases.json  ${targetNameCases.length} cases`);
