/**
 * privacy_gliner_fixtures.mjs — goldens for GLiNER input construction.
 *
 * Word splitting decides everything downstream: span offsets, words_mask and
 * text_lengths all derive from it, and a divergence would be silent because the
 * model would still return plausible logits for the wrong spans. So the splitter
 * is captured from the REAL gliner package the web runs, not from reading its
 * regex.
 *
 * Only the splitter is captured here. The token IDs come from the tokenizer,
 * whose parity is proven separately (11/11 byte-identical on device, see
 * integration_test/tokenizer_parity_test.dart), and capturing them would mean
 * loading a 175 MB model's vocab in node for no extra confidence.
 *
 * Usage:
 *   node tool/privacy_gliner_fixtures.mjs
 */
import { createRequire } from "node:module";
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const webDir =
  process.env.PRIVACY_WEB_DIR ?? resolve(repoRoot, "../portraitor_v3/privacy");

const splitterSrc = resolve(
  webDir,
  "node_modules/gliner/src/lib/processor.ts",
);
if (!existsSync(splitterSrc)) {
  console.error(`Cannot find the gliner package at ${webDir}/node_modules.`);
  process.exit(1);
}

const webRequire = createRequire(resolve(webDir, "package.json"));
let esbuild;
try {
  esbuild = webRequire("esbuild");
} catch {
  console.error(`esbuild not installed. Run: cd ${webDir} && npm install`);
  process.exit(1);
}

// processor.ts imports the tokenizer machinery, which we do not want to load.
// WhitespaceTokenSplitter is self-contained, so lift just that class.
const src = readFileSync(splitterSrc, "utf8");
const m = src.match(/export class WhitespaceTokenSplitter \{[\s\S]*?\n\}/);
if (!m) {
  console.error("Could not locate WhitespaceTokenSplitter. Has gliner changed?");
  process.exit(1);
}
const tmp = resolve(webDir, ".fixtures.splitter.ts");
writeFileSync(tmp, m[0]);
await esbuild.build({
  entryPoints: [tmp],
  bundle: true,
  format: "esm",
  platform: "node",
  outfile: `${tmp}.mjs`,
  logLevel: "error",
});
const { WhitespaceTokenSplitter } = await import(`${tmp}.mjs?t=${Date.now()}`);
const { rmSync } = await import("node:fs");
rmSync(tmp, { force: true });
rmSync(`${tmp}.mjs`, { force: true });

const splitter = new WhitespaceTokenSplitter();

// Every shape the chat corpus can produce, plus the ones that break naive
// splitters: CJK (no spaces), emoji (surrogate pairs), hyphen and underscore
// runs, punctuation, bidi marks, and the bracketed timestamp format.
const texts = [
  "hello world",
  "Mac Chai said hi",
  "e-mail me at a@b.com",
  "snake_case and kebab-case and mixed_a-b_c",
  "[27/11/2025, 9:20:00 AM] Natalia: hi Michael",
  "24/02/2025, 11:41 - Mac Chai: hi @CK",
  "绍陞 said hello",
  "Наталия Иванова",
  "🎉🎉 party with Zoe",
  "Björn and Bjorn",
  "IBAN GB29NWBK60161331926819",
  "  leading and trailing   ",
  "",
  "   ",
  "a",
  "!!!",
  "multi\nline\ntext here",
  "tabs\tand\tspaces",
  "https://x.io/a?b=c&d=e",
  "don't split apostrophes wrongly",
  "1234 5678 9012 3456",
  "‎[24/02/2025] ‎Bidi Speaker: marked",
];

const cases = texts.map((text) => ({
  text,
  words: [...splitter.call(text)].map(([token, start, end]) => ({
    token,
    start,
    end,
  })),
}));

// Guard: every recorded offset must slice back to its own token.
for (const c of cases) {
  for (const w of c.words) {
    if (c.text.slice(w.start, w.end) !== w.token) {
      throw new Error(`offset mismatch in ${JSON.stringify(c.text)}`);
    }
  }
}

writeFileSync(
  resolve(repoRoot, "test/golden/word_split_cases.json"),
  JSON.stringify({ cases }, null, 2) + "\n",
);

console.log(`word_split_cases.json  ${cases.length} cases`);
for (const c of cases) {
  console.log(`  ${JSON.stringify(c.text).slice(0, 46).padEnd(48)} ${c.words.length} words`);
}
