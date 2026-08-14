# Portraitor Mobile — Screens 01–04 · Flutter Handover

**Package:** onboarding (01 Welcome · 02 How it works · 03 Privacy) + 04 Home
**Target:** refactor the existing `portraitor-mobile` Flutter app to match this design
**Design source of truth:** `Portraitor_Screens_01-04.html` (open in a browser — it is pixel-accurate and self-contained)

---

## 1. What's in this package

| File | What it is |
|---|---|
| `Portraitor_Screens_01-04.html` | The design itself. Open in Chrome. Inspect any element to read exact values. |
| `screenshots/all-screens.png` | Visual reference of all 4 screens side by side |
| `assets/01-welcome-bg.png` | Screen 01 full-bleed background (sunset over water) |
| `assets/02-howitworks-bg.png` | Screen 02 background (person meditating by lake) |
| `assets/03-privacy-bg.png` | Screen 03 full-bleed background (lavender lake at dusk) |
| `assets/04-home-card-bg.png` | Screen 04 hero card background (purple lotus) |
| `design_tokens.css` | Existing web token file, for cross-reference |
| `INSTRUCTIONS.md` | This file |

**Icons are inline SVG inside the HTML — no icon files.** Copy each `<svg>` path directly into `flutter_svg` (`SvgPicture.string`) or redraw with `CustomPainter`. Every icon is a 24×24 viewBox.

---

## 2. Design frame

- Screens are drawn at **278 × 614 logical px** (the inner screen area; the 296×632 outer box in the HTML includes the phone bezel — ignore the bezel, it's presentation chrome only).
- Design assumes a standard iPhone (notch/Dynamic Island at top, home indicator at bottom). Use `SafeArea`.
- **The status bar, notch pill, and home indicator in the HTML are mockup decoration — do NOT build them.** Use the real system status bar.

---

## 3. Colors — ADD THESE TO YOUR THEME

The redesign introduces colors not in the current Flutter theme. Add all of these.

### Brand gradient (primary CTA — used on every screen)
```
LinearGradient(
  begin: Alignment.topLeft, end: Alignment.bottomRight,
  colors: [Color(0xFF5B8CFF), Color(0xFFA855F7), Color(0xFFEC4899)],
)
```

### Core palette
| Token | Hex | Use |
|---|---|---|
| `ink` | `#211A37` | Primary text |
| `inkSoft` | `#4C4666` | Secondary body text |
| `muted` | `#8C86A0` | Tertiary / captions |
| `mutedLight` | `#B4AEC4` | Inactive tab icons |
| `surface` | `#FBFAFF` | Page/card background |
| `primary` | `#7C5CFF` | Active state, links, accents |
| `primaryDeep` | `#6B4AF0` | Pressed / badge text |

### Icon gradient ramp (NEW — this is the design's signature)
Icons step through violet → peach across a list, rather than all being one color:
| Position | Gradient |
|---|---|
| 1st (violet) | `#8B5CF6` → `#6D28D9` |
| 2nd (violet→peach) | `#C084FC` → `#F0A48A` |
| 3rd (peach→coral) | `#F0A48A` → `#E8837A` |

Applies to: screen 01 feature cards, screen 02 step badges + step icons, screen 03 privacy cards. **Preserve this ramp — it is intentional, not a bug.**

### Pass gold (screen 04 Pass chip)
| Token | Hex |
|---|---|
| `passGoldBorder` | `#B8912F` (32% alpha for border) |
| `passGoldText` | `#8A6A1E` |
| `passGoldLink` | `#A17E26` |
| `passGoldBgTop` | `#FBF5E9` |
| `passGoldBgBottom` | `#F6ECD6` |

### Sage (success checks, screen 03)
| Token | Hex |
|---|---|
| `sageCheck` | `#5E7A6C` |
| `sageCheckBg` | `rgba(127,184,158,0.22)` |

---

## 4. Typography

Two families, both already in the app:
- **Space Grotesk** — all headings, buttons, labels, names, numbers
- **Inter** — all body copy, descriptions, captions

| Role | Family | Size | Weight | Extra |
|---|---|---|---|---|
| Screen title (01) | Space Grotesk | 24 | 700 | `letterSpacing: -0.03em`, `height: 1.05` |
| Screen title (02/03) | Space Grotesk | 20 | 700 | `letterSpacing: -0.02em` |
| Section heading | Space Grotesk | 14.5 | 700 | |
| Card title | Space Grotesk | 13–14 | 600 | |
| Button label | Space Grotesk | 14.5 | 600 | |
| Body | Inter | 12.5–13 | 400 | `height: 1.4–1.5` |
| Caption / meta | Inter | 11–11.5 | 400 | |
| Tab label | Space Grotesk | 9.5 | 600 | |
| Eyebrow (NEW PORTRAIT) | Inter | 10 | 700 | `letterSpacing: 0.12em` |

---

## 5. Screen-by-screen

### 01 · Welcome
- Full-bleed background image (`01-welcome-bg.png`), `BoxFit.cover`.
- Scrim over it so text stays legible — a vertical gradient: transparent in the middle, `#FBFAFF` at 55% opacity at top, solid `#FBFAFF` at bottom. Use `Stack` + `DecoratedBox`.
- Headline "Read between the lines." top-left, then flexible spacer.
- 3 frosted feature cards above the CTA: white at 72% opacity, `BackdropFilter(blur: 12)`, radius 14, 1px white border at 85%. Icon tile 26×26, radius 8, gradient ramp (see §3).
- Page dots: active = 22×6 pill `#7C5CFF`; inactive = 6×6 at 30% opacity.
- CTA: full-width, height 54, fully rounded, brand gradient, with a circular arrow chip on the right (26×26, white at 24%).

### 02 · How it works
- Background image (`02-howitworks-bg.png`) covers the **whole content area**, positioned `center 78%` (anchored low so the figure and lake are visible). It sits BEHIND the steps — use `Stack` with the image first.
- No white gap at the bottom: the image bleeds to the very bottom edge. The home indicator sits on top of it.
- 3 steps in a vertical timeline: 40×40 white circle with the icon, a small 18×18 numbered badge pinned top-right of each circle, and a 2px connector line between circles (`rgba(124,92,255,0.2)`), omitted after the last step.
- Step icons + badges follow the gradient ramp (§3).
- CTA floats over the image near the bottom.

### 03 · Privacy
- Full-bleed background image (`03-privacy-bg.png`), `BoxFit.cover`, with a strong vertical white scrim over it so cards and text stay legible: `#FBFAFF` at 72% (top) → 50% (26%) → 78% (52%) → 92% (bottom).
- 3D-ish shield hero: 60×66 rounded shape with gradient `#8B5CF6 → #6D28D9`, asymmetric border radius (`16 16 22 22 / 16 16 30 30`) to get the shield silhouette, plus inner highlight/shadow. Behind it, a soft blurred purple radial glow that gently breathes (scale 1.0 ↔ 1.06, 5s).
- 3 cards, each: 34×34 gradient icon tile (ramp per §3) + title + description + a sage circular check on the right.
- Legal line with tappable **Privacy Policy** and **Terms of Service**.
- CTA "I agree & continue".

### 04 · Home
- Pass chip (gold): shows `Pass · 7 of 10 left` + `Manage →`. Tapping opens Manage Pass. **Bind to real Pass quota.**
- Hero card: `04-home-card-bg.png` as background, overlaid with a diagonal gradient scrim (`rgba(91,60,180,.92)` → `rgba(236,72,153,.28)`, 105°) so white text stays readable. Contains eyebrow, title, subtitle, and a white pill "Start" button.
- Recent portraits list: 36×36 circular avatar with the person's initial on a gradient, name, a relationship tag chip (PARTNER / FAMILY), and relative time.
- **Bottom tab bar: Home · Portraits · Profile** (3 tabs). Active tab is `#7C5CFF`, inactive `#B4AEC4`. Bar is white at 85% with a blur and a 1px top hairline.

---

## 6. Animations

| Effect | Where | Spec |
|---|---|---|
| `pulseGlow` | All primary CTAs | Shadow pulses 3.4s ease-in-out, infinite. Flutter: `AnimationController` + animated `BoxShadow` blur/opacity. |
| `auraBreathe` | Screen 03 shield glow | Scale 1.0 ↔ 1.06, opacity .9 ↔ 1, 5s ease-in-out, infinite. |

Both are decorative — if they cost too much on low-end devices, drop them, don't fake them.

---

## 7. Navigation

```
01 Welcome  → [Let's begin]        → 02
02 How it works → [Continue]       → 03
03 Privacy  → [I agree & continue] → 04 Home   (onboarding complete, don't show again)
04 Home     → tab bar: Home | Portraits | Profile
            → Pass chip  → Manage Pass
            → Start / hero card → import flow
```

Onboarding is a one-time flow — persist a completion flag.

---

## 8. Rules

1. **Do not redesign.** Match the HTML. Inspect it for any value not written down here.
2. **Do not substitute colors.** Especially the icon gradient ramp — all-purple is wrong.
3. **Ignore mockup chrome.** The phone bezel, the fake status bar, the fake home indicator, and the "01 · Welcome" captions are presentation only.
4. **Images ship as-is.** Don't recompress or crop; the framing (particularly 02's low anchor) is deliberate.
5. **The Pass is a shared, code-based pass** — 10 portraits per cycle pooled across everyone holding the code, not per-user credits. Copy on the Home chip should reflect real remaining quota.
6. If something can't be built exactly, flag it — don't silently approximate.
