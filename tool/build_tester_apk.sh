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
# The tester build's simulated purchase needs the backend's payment mode set to
# 'mock'. Against live Stripe the confirm step 400s and the tester gets stuck at
# the pay screen with a real portrait they can never reach. Catch that here,
# not in the client's hands.
if [[ "$MODE" == "tester" && "$API_BASE" == *"staging"* ]]; then
  bold "3/4  Backend payment-mode preflight"
  REF="apk-preflight-$(date +%s)"
  INTENT="$(curl -sS -X POST "$API_BASE/api/payment.php" \
    -H 'Content-Type: application/json' \
    -d "{\"customer_email\":\"demo@portraitor.ai\",\"tier\":\"you\",\"client_conversation_ref\":\"$REF\",\"source\":\"manual-test\"}" \
    --max-time 25 | sed -n 's/.*"payment_intent_id":"\([^"]*\)".*/\1/p')"

  if [[ -z "$INTENT" ]]; then
    warn "Could not create a preflight payment intent. Is $API_BASE reachable?"
  else
    CONFIRM="$(curl -sS -X PUT "$API_BASE/api/payment.php" \
      -H 'Content-Type: application/json' \
      -d "{\"payment_intent_id\":\"$INTENT\"}" --max-time 25)"
    if [[ "$CONFIRM" == *'"confirmed":true'* ]]; then
      echo "  Backend is in mock mode. Simulated purchases will produce real portraits."
    else
      warn ""
      warn "  BACKEND IS NOT IN MOCK MODE."
      warn "  Response: $CONFIRM"
      warn ""
      warn "  Testers will reach the pay screen and get:"
      warn "    \"Demo purchases need the backend payment mode set to 'mock'.\""
      warn ""
      warn "  Fix: open $API_BASE/admin.php, set Payment Mode to"
      warn "  'Mock (testing)', and save. Leave Email Mode on a real SMTP"
      warn "  option so testers still receive their portrait by email."
      warn ""
      warn "  Building anyway. The APK is correct; the backend is not ready."
    fi
  fi
else
  bold "3/4  Backend preflight skipped for this mode/target"
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
