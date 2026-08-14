/**
 * privacy_fake_spans.mjs — author test/golden/fake_spans.json.
 *
 * fake_spans.json is the fake detector, held as DATA so node and Dart replay
 * identical spans. Its offsets are UTF-16 code units, which is why they are
 * COMPUTED here in node rather than typed by hand: an astral emoji or a bidi
 * mark shifts every following offset, and a hand-counted offset would silently
 * produce a wrong golden.
 *
 * Each case lists the names the fake "detects". Like the real model it finds
 * each name ONCE, at its first occurrence, so the pipeline has to propagate the
 * rest. Everything else in a case (emails, cards, speaker lines, mentions) is
 * left for the rules and structural detectors to find on their own.
 *
 * Usage:
 *   node tool/privacy_fake_spans.mjs && node tool/privacy_fixtures.mjs
 */
import { writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");

// Bidi and formatting marks WhatsApp sprinkles into exports.
const LRM = "‎";
const FSI = "⁦";
const PDI = "⁩";

const cases = [
  // ── core behaviours ──────────────────────────────────────────────────────
  {
    name: "smoke",
    text:
      "[27/11/2025, 9:20:00 AM] Natalia: hi Michael, my link is https://x.io/a\n" +
      "[27/11/2025, 9:21:00 AM] Michael: thanks Natalia! email me at a@b.com",
    detect: ["Natalia", "Michael"],
  },
  {
    name: "propagation_repeat",
    text:
      "[01/02/2025, 10:00:00 AM] Emma: morning\n" +
      "[01/02/2025, 10:01:00 AM] James: hi Emma\n" +
      "[01/02/2025, 10:02:00 AM] Emma: Emma again, and Emma once more",
    detect: ["Emma", "James"],
  },
  {
    name: "literal_token_in_source",
    text:
      "[01/02/2025, 10:00:00 AM] Ana: the placeholder [PERSON1] is literally in this chat\n" +
      "[01/02/2025, 10:01:00 AM] Ana: ok",
    detect: ["Ana"],
  },
  {
    name: "leak_adjacent_to_token",
    text:
      "[01/02/2025, 10:00:00 AM] Bob: mail me bob@example.com now\n" +
      "[01/02/2025, 10:01:00 AM] Bob: IBAN GB29NWBK60161331926819 ok",
    detect: ["Bob"],
  },
  {
    name: "cjk_and_cyrillic",
    text:
      "[01/02/2025, 10:00:00 AM] 绍陞: hello\n" +
      "[01/02/2025, 10:01:00 AM] Наталия: hi 绍陞",
    detect: ["绍陞", "Наталия"],
  },
  {
    name: "emoji_offsets",
    text:
      "[01/02/2025, 10:00:00 AM] Zoe: 🎉🎉 party with Zoe\n" +
      "[01/02/2025, 10:01:00 AM] Zoe: 👍 ok",
    detect: ["Zoe"],
  },
  {
    name: "accented_name",
    text:
      "[01/02/2025, 10:00:00 AM] Björn: hi\n" +
      "[01/02/2025, 10:01:00 AM] Bjorn: different person",
    detect: ["Björn"],
  },

  // ── export shapes ────────────────────────────────────────────────────────
  {
    // The dash speaker format, plus @mentions with and without isolates.
    name: "dash_format_and_mentions",
    text:
      `24/02/2025, 11:41 - Mac Chai: hi @CK and @${FSI}Zoe${PDI} here\n` +
      "24/02/2025, 11:42 - CK: thanks Mac Chai",
    detect: ["Mac Chai"],
  },
  {
    // Bidi marks around the timestamp and speaker, and the "~ " push-name
    // prefix. Nothing is model-detected: the structural detector must carry it.
    name: "bidi_and_push_name",
    text:
      `${LRM}[24/02/2025, 11:41:30 PM] ${LRM}Bidi Speaker: marked line\n` +
      "[24/02/2025, 11:42:00 PM] ~ Push Name: with a push-name prefix",
    detect: [],
  },

  // ── structured detail through the whole pipeline ─────────────────────────
  {
    name: "contacts_email_url_phone",
    text:
      "[01/02/2025, 10:00:00 AM] Dana: mail dave@oakwoodlettings.co.uk or call 020 7946 0321\n" +
      "[01/02/2025, 10:01:00 AM] Dana: repairs at https://oakwoodlettings.co.uk/repairs",
    detect: ["Dana"],
  },
  {
    name: "credentials_otp_password_card",
    text:
      "[01/02/2025, 10:00:00 AM] Sam: your OTP is 483920 and password: hunter2x\n" +
      "[01/02/2025, 10:01:00 AM] Sam: card 4242 4242 4242 4242 on file",
    detect: ["Sam"],
  },
  {
    name: "account_and_national_ids",
    text:
      "[01/02/2025, 10:00:00 AM] Ravi: IBAN GB29NWBK60161331926819 sort code 40-47-84\n" +
      "[01/02/2025, 10:01:00 AM] Ravi: ssn 123-45-6789 and passport no A1234567",
    detect: ["Ravi"],
  },
];

const out = {
  cases: cases.map(({ name, text, detect }) => {
    const spans = [];
    for (const n of detect) {
      const i = text.indexOf(n);
      if (i < 0) throw new Error(`case ${name}: "${n}" not present in text`);
      spans.push({
        spanText: n,
        start: i,
        end: i + n.length,
        label: "person name",
        score: 0.9,
      });
    }
    spans.sort((a, b) => a.start - b.start);
    for (const s of spans) {
      if (text.slice(s.start, s.end) !== s.spanText) {
        throw new Error(`case ${name}: computed offset does not round-trip`);
      }
    }
    return { name, text, spans };
  }),
};

writeFileSync(
  resolve(repoRoot, "test/golden/fake_spans.json"),
  JSON.stringify(out, null, 2) + "\n",
);

console.log(`wrote ${out.cases.length} cases`);
for (const c of out.cases) {
  const d = c.spans.map((s) => `${s.spanText}@${s.start}`).join(", ") || "none";
  console.log(`  ${c.name}: ${d}`);
}
