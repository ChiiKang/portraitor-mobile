# 2026-06-17 — Mobile bugs: PDF download 500 + streaming "thoughts"

Found while running the real app (`main`) on a physical iPhone.

---

## 1. PDF download fails — "Unable to share PDF" (BACKEND bug, fix later)

**Symptom (mobile):** Tapping share/download a portrait PDF shows
`Unable to share PDF`. With the catch instrumented, the real error is:

```
ApiException: Unable to create PDF (status: 500, code: null)
```

**Server error log:**
```
Portrait PDF endpoint error: Unable to create PDF for this language without the TCPDF Unicode renderer
```

### Root cause — server side, NOT mobile
- Mobile correctly POSTs a valid portrait to `POST /api/portrait-pdf.php` and the
  **backend returns HTTP 500**.
- That endpoint renders the PDF server-side (`PortraitPdfService::buildStyledPdf`).
  Logic:
  1. If the portrait text contains **non-Latin script** (Cyrillic, CJK,
     Japanese, Korean, Hebrew, Arabic, Devanagari, Thai — see
     `basicRendererCannotEncodeText()`), it needs the **TCPDF Unicode renderer**.
  2. If TCPDF is unavailable *or* throws, and the text is non-Latin, it throws
     `Unable to create PDF for this language without the TCPDF Unicode renderer`.
- **Web is unaffected** because web generates the PDF **client-side** (pdfmake in
  the browser) and never calls this endpoint. This backend endpoint exists only
  for mobile — which is why it's the untested/broken path.
- The portrait that failed was in a **non-Latin language**. A plain-English
  portrait renders fine via the basic fallback.

### Which sub-case? (check the staging error log for a SECOND line)
`Portrait PDF TCPDF renderer failed; retrying with basic PDF renderer: <msg>`
- **Line present** → TCPDF is installed but **threw** → almost certainly a
  **missing font** for that script. Fix: configure a Unicode/CJK font in the
  TCPDF renderer (e.g. `droidsansfallback`, `cid0jp`, or an embedded TTF) for the
  affected language.
- **Line absent** → `class_exists(\TCPDF::class)` was false → **TCPDF not
  deployed on staging**. Fix: run `composer install` on staging so
  `vendor/tecnickcom/tcpdf` is present (it IS in `composer.json` /
  `composer.lock` and in the local checkout — so it's a deployment gap).

### Fix location
Backend repo (`portraitor` / `p54-ai/portraitor`) + the **staging deployment**.
`src/Services/PortraitPdfService.php` (renderer/font selection). **No mobile change
needed** — the Flutter client is behaving correctly.

### Confirmation test (no code)
Generate a portrait in **plain English** and download the PDF → should succeed.
That proves the failure is the non-Latin + TCPDF path on the server.

### Fallback option (only if backend can't be fixed)
Switch mobile back to **client-side PDF generation** (Flutter `pdf` package), like
web. Bigger change — mobile was deliberately moved to backend generation
(client-side was removed). Prefer fixing the backend.

### TEMP mobile diagnostic in place (revert later)
`lib/features/results/presentation/result_screen.dart` `_sharePdf` was changed
from `catch (_)` (which silently swallowed the error) to `catch (e, st)` that
logs `[PDF] _sharePdf failed: …` and shows the raw exception in the snackbar.
Revert to a clean user-facing message once the backend is fixed.

---

## 2. Streaming "thoughts" arrived only at the very end (MOBILE — fix applied)

**Symptom:** During processing, the Gemini chain-of-thoughts didn't stream
progressively — everything appeared ~0.5 s before the complete page.

**Root cause:** The SSE request (`_postSseWithHcdnRetry` in
`lib/core/api/api_service.dart`) didn't pin `Accept-Encoding`. dart:io defaults to
`gzip`; browsers don't offer gzip for `EventSource`. So the CDN gzip-buffered the
event-stream for the mobile client and released it all at the end. The web server
already streams correctly (`X-Accel-Buffering: no`, `Cache-Control: no-transform`,
per-event `flush()`).

**Fix applied (mobile):** send `Accept-Encoding: identity` on the SSE request so
the CDN streams it uncompressed like it does for the browser.
```dart
headers: {'Accept': 'text/event-stream', 'Accept-Encoding': 'identity'},
```
Status: applied on `main` (uncommitted) — pending on-device confirmation that the
thoughts now stream progressively.
