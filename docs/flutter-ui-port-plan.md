# Flutter UI port — v2 branch

**Branch:** `v2/ui-prototype-port`  
**Status:** Implementation in progress in this repo (not a handover for another agent).

## Locked product decisions
- Money: Apple IAP / StoreKit (UI sheet live; StoreKit verify next)
- First ship: full UI; Partner / Family / Pass CTAs gated
- You path: funnel → IAP sheet → legacy `/payment` bridge until StoreKit

## Shipped on this branch
- Routes: `/funnel/add|plan|configure|confirm`, `/profile`
- `FunnelChrome` (progress · n/4 · glass CTA)
- Add conversation (upload / WhatsApp / paste / clipboard banner)
- Plan packs + Pass drawer (Subscribe gated)
- Configure You (detected chips, date presets, privacy note, consent)
- Confirm & pay + Apple IAP sheet → `/payment` for You
- Home logo lockup, Start → `/funnel/add`, Profile screen shell

## Still open
- StoreKit product IDs + receipt verify backend
- Partner / Family multi-person jobs
- Pass quota API
- Persistent tab dock on Library / Profile (Home dock only for now)
- Session preview cards parity with HTML prototype
- Pixel polish vs Open Design HTML
