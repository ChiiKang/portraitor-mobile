#!/usr/bin/env bash
#
# Build a shareable Android APK for clients and teammates.
#
# The default build is the one described in docs/client-testing-distribution-plan.md:
# a simulated purchase, but a real backend, real AI generation, and a real email.
#
# Usage:
#   tool/build_tester_apk.sh                     # tester build (simulated pay, real portrait)
#   tool/build_tester_apk.sh --demo              # screens only (no backend, local sample portrait)
#   tool/build_tester_apk.sh --api-base https://portraitor.ai
#   tool/build_tester_apk.sh --skip-checks       # skip analyze/test (only when already green)
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

API_BASE="https://staging.portraitor.ai"
MODE="tester"
RUN_CHECKS=1
OUT_DIR="${PORTRAITOR_APK_OUT:-$HOME/Desktop/Portraitor-Builds}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --demo)        MODE="demo"; shift ;;
    --api-base)    API_BASE="$2"; shift 2 ;;
    --skip-checks) RUN_CHECKS=0; shift ;;
    --out)         OUT_DIR="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

if [[ "$MODE" == "demo" ]]; then
  FLAG_NAME="DEMO_IAP"
  LABEL="demo"
else
  FLAG_NAME="FAKE_BILLING"
  LABEL="tester"
fi

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
fail() { printf '\033[31m%s\033[0m\n' "$1" >&2; exit 1; }
warn() { printf '\033[33m%s\033[0m\n' "$1" >&2; }

bold "Portraitor APK build"
echo "  mode:      $MODE  (--dart-define=$FLAG_NAME=true)"
echo "  backend:   $API_BASE"
echo "  output:    $OUT_DIR"
echo

# ── 1. Correctness gates ────────────────────────────────────────────────
# A tester build that fails analyze or tests is not worth sending to a client.
if [[ $RUN_CHECKS -eq 1 ]]; then
  bold "1/4  Static analysis"
  flutter analyze || fail "flutter analyze failed. Fix it before sending a build to anyone."

  bold "2/4  Test suite"
  flutter test || fail "flutter test failed. Fix it before sending a build to anyone."
else
  warn "Skipping analyze and tests (--skip-checks)."
fi

# ── 2. Backend preflight ────────────────────────────────────────────────
# The tester build does not touch Stripe, so the backend's web payment mode is
# irrelevant to it and staging deliberately stays on 'stripe_sandbox'. What it
# needs is GOOGLE_PLAY_DEMO_GRANTS, which lets the real Google verify endpoint
# accept a 'demo.v1.' purchase token. Probe that endpoint, because it is the one
# the APK will actually call.
#
# Two probes, because no single response proves anything on its own. The demo
# token exercises the demo branch; an unprefixed control token can only take the
# real Google Play branch. Read together they separate "demo grants are on" from
# "everything is rejected the same way".
if [[ "$MODE" == "tester" ]]; then
  bold "3/4  Backend demo-grant preflight"

  b64url() { printf '%s' "$1" | base64 | tr -d '\n' | tr '+/' '-_' | tr -d '='; }
  new_uuid() {
    uuidgen 2>/dev/null | tr '[:upper:]' '[:lower:]' \
      || printf 'preflight-%s-%s' "$$" "$(date +%s)"
  }

  PROBE_SKU="com.portraitor.portrait.you"
  # Deliberately mismatched identities: the token claims one uuid and the
  # request body claims another. A backend that accepts demo tokens still stops
  # at the account-token check, so the probe proves the branch was taken without
  # minting a payment row nobody will ever spend.
  PROBE_TOKEN="demo.v1.$(b64url "{\"product_id\":\"$PROBE_SKU\",\"public_uuid\":\"$(new_uuid)\"}")"
  PROBE_UUID="$(new_uuid)"

  probe() {
    curl -sS -o /dev/null -w '%{http_code}' --max-time 25 \
      -X POST "$API_BASE/api/google/purchase/verify.php" \
      -H 'Content-Type: application/json' \
      -d "{\"purchase_token\":\"$1\",\"product_id\":\"$PROBE_SKU\",\"public_uuid\":\"$PROBE_UUID\",\"client_conversation_ref\":\"apk-preflight-$(date +%s)\"}" \
      2>/dev/null || printf 'unreachable'
  }

  DEMO_CODE="$(probe "$PROBE_TOKEN")"
  CONTROL_CODE="$(probe "not-a-demo-token")"
  echo "  demo token: HTTP $DEMO_CODE    control token: HTTP $CONTROL_CODE"

  if [[ "$DEMO_CODE" == "422" && "$CONTROL_CODE" == "500" ]]; then
    echo "  Demo grants are on. A simulated purchase will fund a real portrait."
  elif [[ "$DEMO_CODE" == "500" && "$CONTROL_CODE" == "500" ]]; then
    warn ""
    warn "  DEMO GRANTS ARE OFF ON THIS BACKEND."
    warn "  The demo token fell through to real Google Play verification, which"
    warn "  cannot work until the Play Console account exists."
    warn ""
    warn "  Testers will reach the pay screen and get:"
    warn "    \"Purchase could not be verified\""
    warn ""
    warn "  Fix: set 'SetEnv GOOGLE_PLAY_DEMO_GRANTS true' in the .htaccess"
    warn "  profile that is actually deployed to $API_BASE, redeploy, and"
    warn "  rerun this script. Do NOT change Payment Mode in admin.php - that"
    warn "  governs the web Stripe rail and this build never touches it."
    warn ""
    warn "  Building anyway. The APK is correct; the backend is not ready."
  else
    warn ""
    warn "  DEMO-GRANT READINESS IS UNKNOWN."
    warn "  Expected HTTP 422 for the demo token and 500 for the control token."
    warn ""
    if [[ "$DEMO_CODE" == "unreachable" || "$CONTROL_CODE" == "unreachable" ]]; then
      warn "  The endpoint did not answer. Check that $API_BASE is reachable."
    elif [[ "$DEMO_CODE" == "429" || "$CONTROL_CODE" == "429" ]]; then
      warn "  Rate limited. Wait for the verify window to reset and rerun."
    elif [[ "$DEMO_CODE" == "422" && "$CONTROL_CODE" == "422" ]]; then
      warn "  Real Google Play verification is configured, so both tokens are"
      warn "  rejected identically and the status code cannot tell them apart."
    fi
    warn ""
    warn "  Check by hand before sending this build: confirm the deployed"
    warn "  .htaccess on $API_BASE sets GOOGLE_PLAY_DEMO_GRANTS, then walk one"
    warn "  simulated purchase on a device and confirm the portrait arrives."
    warn ""
    warn "  Building anyway. Nothing above says the APK is wrong."
  fi
else
  bold "3/4  Backend preflight skipped for this mode"
fi

# ── 3. Build ────────────────────────────────────────────────────────────
# Profile, never release: both demo flags are compiled out of release builds by
# design, so a release APK would silently fall through to real store billing
# and fail on a device with no store catalog.
bold "4/4  Building profile APK"
flutter build apk --profile \
  --dart-define="$FLAG_NAME=true" \
  --dart-define="API_BASE=$API_BASE" \
  || fail "The APK build failed."

SRC="build/app/outputs/flutter-apk/app-profile.apk"
[[ -f "$SRC" ]] || fail "Build reported success but $SRC is missing."

# ── 4. Publish to a stable, findable location ───────────────────────────
VERSION="$(sed -n 's/^version: *\([^+]*\)+.*/\1/p' pubspec.yaml | tr -d '[:space:]')"
BUILDNO="$(sed -n 's/^version: *[^+]*+\(.*\)/\1/p' pubspec.yaml | tr -d '[:space:]')"
# BSD sed has no \?, so match the optional 's' with 'https*'.
TARGET="$(printf '%s' "$API_BASE" | sed -e 's#^https*://##' -e 's#\..*##')"
STAMP="$(date +%Y-%m-%d)"
NAME="portraitor-v${VERSION}+${BUILDNO}-${TARGET}-${LABEL}-${STAMP}.apk"

mkdir -p "$OUT_DIR"
cp "$SRC" "$OUT_DIR/$NAME"
SIZE="$(du -h "$OUT_DIR/$NAME" | cut -f1 | tr -d '[:space:]')"

echo
bold "APK ready"
echo "  file:    $NAME"
echo "  folder:  $OUT_DIR"
echo "  size:    $SIZE"
echo "  backend: $API_BASE"
echo
echo "  Open the folder:  open \"$OUT_DIR\""
echo
