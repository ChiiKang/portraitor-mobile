# Flutter UI port - v2 branch

**Branch:** `v2/ui-prototype-port`  
**Status:** Implementation in progress in this repo (not a handover for another agent).

## Locked product decisions

- Mobile billing follows the authoritative
  [store-billing design](superpowers/specs/2026-08-07-apple-iap-design.md):
  App Store on iOS, Google Play on Android, and Stripe on web only.
- All four product CTAs use the platform-selected native billing path.
- A verified consumable continues to processing; a verified Pass first saves
  its credential, then continues.

## Shipped on this branch

- Routes: `/funnel/add|plan|configure|confirm`, `/profile`
- `FunnelChrome` (progress · n/4 · glass CTA)
- Add conversation (upload / WhatsApp / paste / clipboard banner)
- Plan packs + Pass drawer with localized store prices
- Configure You (detected chips, date presets, privacy note, consent)
- Confirm and pay through App Store or Google Play billing
- Home logo lockup, Start → `/funnel/add`, Profile screen shell
- Persistent tab dock and session preview cards
- Inline unfinished-portrait recovery card with state-specific actions

## Still open

- App Store Connect and Google Play Console setup, deployed secrets, and real
  sandbox end-to-end verification
- Partner / Family multi-person jobs
- Pixel polish vs Open Design HTML
