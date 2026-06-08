# Multilingual PDF Font Coverage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make backend-generated PDFs preserve Russian and other major-language text when mobile downloads/shares PDFs.

**Architecture:** Keep mobile as a PDF downloader only. Fix language support in the `portraitor` backend PDF generator with repo-controlled fonts, script-aware tests, and a fallback strategy for scripts not covered by current pdfmake/Roboto output.

**Tech Stack:** PHP endpoint, Node.js, pdfmake 0.2.15, repo-bundled Unicode fonts, `pdftotext`, Playwright parity tests, Flutter integration test.

---

## Current Finding

Local reproduction on the newly built backend generator showed:

- Russian/Cyrillic text is preserved locally through `tools/pdf/generate-portrait-pdf.cjs`.
- Chinese text is dropped by extracted PDF text.
- Arabic text is dropped by extracted PDF text.
- The screenshot showing `????` is most likely from the previous local/mobile PDF path, a deployed backend that does not yet include the new endpoint code, or a font path different from local.

This still needs fixing because the product requirement is broader than Russian: PDFs should support multilingual portraits.

## Scope

In scope:

- Backend PDF font coverage.
- Backend PDF tests for Cyrillic, CJK, Arabic, and mixed-language text.
- Mobile integration test proving mobile downloads backend PDF bytes.
- Preserve current web PDF production behavior. Do not switch web to backend PDF.

Out of scope:

- Rebuilding the web renderer.
- Switching email PDF attachment flow.
- Guaranteeing perfect emoji/color emoji rendering in this phase.
- Claiming literal “every script on earth” unless tests and fonts prove it.

## Key Design Decision

Use a two-level approach:

1. **Immediate regression lock:** add tests proving Russian/Cyrillic survives backend PDF generation and mobile endpoint download.
2. **Unicode coverage upgrade:** add repo-controlled Noto fonts and script-aware PDF text runs so CJK/Arabic/other scripts are not replaced by `?` or dropped.

If pdfmake cannot shape a script correctly, especially Arabic/Indic/Thai, escalate to a browser/Chromium HTML-to-PDF renderer in a separate backend service. Do not silently ship broken glyph output.

## Files

Backend repo: `/Users/chiikang/Desktop/Nation/Project54/portraitor`

- Modify: `tools/pdf/generate-portrait-pdf.cjs`
- Modify: `public/assets/modules/pdfDocumentBuilder.js`
- Modify: `tests/unit/pdf-node-generator.test.js`
- Modify: `tests/e2e/pdf-backend-browser-parity.spec.ts`
- Create: `tests/fixtures/portrait-pdf-multilingual.md`
- Create: `tests/unit/pdf-font-coverage.test.js`
- Create: `resources/fonts/README.md`
- Add font files under: `resources/fonts/`

Mobile repo: `/Users/chiikang/Desktop/Nation/Project54/portraitor-mobile`

- Modify: `integration_test/result_pdf_test.dart`

## Task 1: Lock Russian Regression

- [ ] Add Russian text to `tests/fixtures/portrait-pdf-multilingual.md`.

Required fixture content:

```markdown
## Report - Natalia (Test2) - Янв 2021 - Май 2026

1. Привет мир: Наталия говорит по-русски.
2. Эмоциональная поддержка, доверие и устойчивость.
```

- [ ] Update `tests/unit/pdf-node-generator.test.js` to generate a PDF from this fixture.

Required assertions:

```javascript
assert(text.includes('Янв 2021 - Май 2026'), 'preserves Russian date range');
assert(text.includes('Привет мир'), 'preserves Russian ordered text');
assert(text.includes('Эмоциональная поддержка'), 'preserves Russian paragraph text');
assert(!text.includes('????'), 'does not replace Russian with question marks');
```

- [ ] Run the test.

```bash
cd /Users/chiikang/Desktop/Nation/Project54/portraitor
node tests/unit/pdf-node-generator.test.js
```

Expected:

- Russian passes locally.
- If it fails on any machine, stop and inspect the actual font path/version.

## Task 2: Add Broad Multilingual Failure Test

- [ ] Extend `tests/fixtures/portrait-pdf-multilingual.md` with CJK and Arabic.

Required fixture content:

```markdown
### Chinese

1. 你好，世界。中文内容应该保留。

### Arabic

1. مرحبا بالعالم. يجب أن يبقى النص العربي واضحا.
```

- [ ] Create `tests/unit/pdf-font-coverage.test.js`.

Required behavior:

- Generate PDF through `tools/pdf/generate-portrait-pdf.cjs`.
- Extract text with `pdftotext`.
- Assert Russian, Chinese, and Arabic are present.
- Assert no long `????` runs exist.
- Log unsupported script failures clearly.

- [ ] Run the test and verify RED.

```bash
cd /Users/chiikang/Desktop/Nation/Project54/portraitor
node tests/unit/pdf-font-coverage.test.js
```

Expected before font upgrade:

- Russian likely passes.
- Chinese and Arabic fail or are dropped.

## Task 3: Add Repo-Controlled Fonts

- [ ] Add fonts under `portraitor/resources/fonts/`.

Recommended minimum set:

```text
resources/fonts/Roboto-Regular.ttf
resources/fonts/Roboto-Medium.ttf
resources/fonts/Roboto-Italic.ttf
resources/fonts/Roboto-MediumItalic.ttf
resources/fonts/NotoSans-Regular.ttf
resources/fonts/NotoSans-Bold.ttf
resources/fonts/NotoSansSC-Regular.otf
resources/fonts/NotoNaskhArabic-Regular.ttf
resources/fonts/README.md
```

- [ ] `resources/fonts/README.md` must document:

```markdown
# PDF Fonts

These fonts are bundled for backend PDF generation so Hostinger production does not depend on system fonts.

- Roboto: keeps Latin/browser parity close to current pdfmake output.
- Noto Sans: Cyrillic/Greek/general Unicode fallback.
- Noto Sans SC: CJK fallback.
- Noto Naskh Arabic: Arabic fallback.

Keep license files with downloaded fonts.
```

- [ ] Do not use system fonts only.

Reason:

- Local macOS fonts may work.
- Hostinger may not have the same fonts.
- Production must be deterministic.

## Task 4: Implement Script-Aware Font Runs

- [ ] Modify `public/assets/modules/pdfDocumentBuilder.js`.

Add a pure helper:

```javascript
function fontForCodePoint(codePoint) {
  if (codePoint >= 0x0600 && codePoint <= 0x06ff) return 'NotoNaskhArabic';
  if (
    (codePoint >= 0x4e00 && codePoint <= 0x9fff) ||
    (codePoint >= 0x3040 && codePoint <= 0x30ff) ||
    (codePoint >= 0xac00 && codePoint <= 0xd7af)
  ) return 'NotoSansSC';
  if (codePoint >= 0x0400 && codePoint <= 0x04ff) return 'NotoSans';
  return 'Roboto';
}
```

- [ ] Add `splitTextByFont(text)` that returns pdfmake text runs.

Expected output shape:

```javascript
[
  { text: 'Report - ', font: 'Roboto' },
  { text: 'Наталия', font: 'NotoSans' },
  { text: ' - ', font: 'Roboto' },
  { text: '你好', font: 'NotoSansSC' }
]
```

- [ ] Ensure existing bold/italic parsing preserves font per run.

Important:

- Do not produce nested arrays like `[marker, parseInline(...)]` for ordered list text.
- Flatten inline arrays so styled ordered-list text is not dropped.

## Task 5: Switch Node Generator to Bundled Fonts

- [ ] Modify `tools/pdf/generate-portrait-pdf.cjs`.

Required behavior:

- Register bundled fonts with pdfmake.
- Use `PdfPrinter` if browser-build pdfmake cannot load custom fonts reliably.
- Keep current browser-build path only if it supports bundled fonts and multilingual output.

Font registration target:

```javascript
{
  Roboto: {
    normal: 'resources/fonts/Roboto-Regular.ttf',
    bold: 'resources/fonts/Roboto-Medium.ttf',
    italics: 'resources/fonts/Roboto-Italic.ttf',
    bolditalics: 'resources/fonts/Roboto-MediumItalic.ttf'
  },
  NotoSans: {
    normal: 'resources/fonts/NotoSans-Regular.ttf',
    bold: 'resources/fonts/NotoSans-Bold.ttf'
  },
  NotoSansSC: {
    normal: 'resources/fonts/NotoSansSC-Regular.otf'
  },
  NotoNaskhArabic: {
    normal: 'resources/fonts/NotoNaskhArabic-Regular.ttf'
  }
}
```

- [ ] Keep generation timeout under 30 seconds.

Run:

```bash
cd /Users/chiikang/Desktop/Nation/Project54/portraitor
node tests/unit/pdf-font-coverage.test.js
node tests/unit/pdf-node-generator.test.js
```

Expected:

- Russian, Chinese, and Arabic assertions pass.
- No `????` runs.
- Runtime remains under 30 seconds.

## Task 6: Recheck Browser Parity

- [ ] Run existing parity test.

```bash
cd /Users/chiikang/Desktop/Nation/Project54/portraitor
npm run serve
npx playwright test tests/e2e/pdf-backend-browser-parity.spec.ts
```

Expected:

- Existing Latin/browser fixture remains visually/textually close.
- If font changes cause measurable layout drift, use Roboto for Latin and route only non-Latin runs to Noto fonts.

## Task 7: Mobile Integration Coverage

- [ ] Modify `portraitor-mobile/integration_test/result_pdf_test.dart`.

Add Russian and Chinese content:

```dart
portrait: '''
## Report - Natalia (Test2) - Янв 2021 - Май 2026

1. Привет мир: Наталия говорит по-русски.
2. 你好，世界。中文内容应该保留。
''',
```

- [ ] Run mobile integration against local backend.

```bash
cd /Users/chiikang/Desktop/Nation/Project54/portraitor-mobile
flutter test integration_test/result_pdf_test.dart -d <ios-simulator-id> --dart-define API_BASE=http://127.0.0.1:8080
```

Expected:

- Mobile receives `%PDF`.
- Backend tests already prove the text inside that PDF is multilingual-safe.

## Task 8: Final Verification

Backend:

```bash
cd /Users/chiikang/Desktop/Nation/Project54/portraitor
node tests/unit/pdf-document-builder.test.js
node tests/unit/pdf-generator.test.js
node tests/unit/pdf-node-generator.test.js
node tests/unit/pdf-font-coverage.test.js
php tests/unit/portrait-pdf-service.test.php
npx playwright test tests/e2e/pdf-backend-browser-parity.spec.ts
```

Mobile:

```bash
cd /Users/chiikang/Desktop/Nation/Project54/portraitor-mobile
flutter test test/services/api_service_test.dart test/services/portrait_pdf_service_test.dart
flutter test integration_test/result_pdf_test.dart -d <ios-simulator-id> --dart-define API_BASE=http://127.0.0.1:8080
flutter analyze
```

Expected:

- All tests pass.
- Russian is preserved.
- CJK is preserved.
- Arabic is either preserved or explicitly marked unsupported with a follow-up Chromium renderer plan.
- No PDF output contains `????` for supported scripts.

## Risk

pdfmake may not fully shape some complex scripts. If Arabic/Indic/Thai still render incorrectly after fonts are added, the correct fix is not more font files. The correct fix is a backend renderer with a real browser text shaping engine, likely Chromium/Puppeteer, deployed where Hostinger process limits and binary availability are acceptable.

