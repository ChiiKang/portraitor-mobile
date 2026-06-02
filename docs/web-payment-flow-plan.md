# Web Payment Flow — Implementation Plan

## Overview

Replace in-app Stripe payment sheet with a web browser payment flow to avoid Apple/Google's 30% commission. Payment happens on a branded web page we host (`portraitor.ai/pay/`), then deep-links back into the app.

## Architecture

```
[App] POST /api/payment.php → { client_secret, publishable_key, pi_id, amount }
  │
  ▼
[App] FlutterWebAuth2.authenticate()
  → opens: https://staging.portraitor.ai/pay/?client_secret=…&publishable_key=…&amount=500&pi_id=pi_xxx&ref=conv_abc&name=Sarah
  │
  ▼
[Web] Branded Stripe card form (card-only, no wallets)
  → user enters card → consent checkbox → Pay → confirmPayment()
  │
  ├─ success → portraitor://payment-success?pi_id=pi_xxx&ref=conv_abc&status=authorized
  └─ cancel  → portraitor://payment-cancel?pi_id=pi_xxx&ref=conv_abc
  │
  ▼
[App] catches deep link → GET /api/payment.php?payment_intent_id=pi_xxx → verify → start processing
```

## Repos Involved

| Repo | Status | What |
|------|--------|------|
| `/portraitor` (backend) | DONE | `payment.php` hardened, `pay/index.php` deployed, `.htaccess.staging` updated |
| `/portraitor-mobile` (app) | TODO | All steps below |

## Environment

- **Staging**: `https://staging.portraitor.ai` (current default in `api_service.dart:20`)
- **Production**: `https://portraitor.ai` (switch later via `API_BASE`)
- Pay page URL follows the base URL automatically

---

## Implementation Steps

### Step 1: Add dependency (~2 min)

**File:** `pubspec.yaml`

```yaml
dependencies:
  flutter_web_auth_2: ^4.0.0   # ADD
  # flutter_stripe: ^11.3.0    # KEEP (don't remove — fallback if Apple rejects)
```

Run `flutter pub get`.

**Decision:** Keep `flutter_stripe` as dead code. If Apple rejects the web payment approach, we can revert to in-app Stripe quickly.

---

### Step 2: Register `portraitor://` URL scheme — iOS (~2 min)

**File:** `ios/Runner/Info.plist`

Add inside the top-level `<dict>`:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLName</key>
    <string>ai.portraitor.app</string>
    <key>CFBundleURLSchemes</key>
    <array><string>portraitor</string></array>
  </dict>
</array>
```

**Important:** This is separate from the WhatsApp share intent (`receive_sharing_intent`). They use different mechanisms — this is a URL scheme, not a content share.

---

### Step 3: Register `portraitor://` URL scheme — Android (~2 min)

**File:** `android/app/src/main/AndroidManifest.xml`

Add inside the main `<activity>` (NOT replacing the existing share intent-filter):

```xml
<intent-filter>
  <action android:name="android.intent.action.VIEW" />
  <category android:name="android.intent.category.DEFAULT" />
  <category android:name="android.intent.category.BROWSABLE" />
  <data android:scheme="portraitor" />
</intent-filter>
```

**Note:** `flutter_web_auth_2` may ship its own callback activity. Check its README for the manifest placeholder approach.

---

### Step 4: Rewrite `PaymentNotifier.initiatePayment()` (~10 min)

**File:** `lib/providers/payment_provider.dart`

Replace the current flow (ApiService.createPayment → StripeService → ApiService.verifyPayment) with:

```dart
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

Future<bool> initiatePayment({
  required String email,
  String? existingConversationRef,
}) async {
  final conversationRef = existingConversationRef ?? const Uuid().v4();
  state = state.copyWith(
    status: PaymentStatus.loading,
    clientConversationRef: conversationRef,
    error: null,
  );

  try {
    // Step 1: Create PaymentIntent on backend
    final result = await ApiService.instance.createPayment(
      clientConversationRef: conversationRef,
      customerEmail: email,
    );

    final data = result['data'] as Map<String, dynamic>? ?? result;
    final clientSecret = data['client_secret'] as String?;
    final paymentIntentId = data['payment_intent_id'] as String?;
    final publishableKey = data['publishable_key'] as String?;
    final amountCents = data['amount_cents'] as int? ?? 500;
    final currency = data['currency'] as String? ?? 'usd';

    if (clientSecret == null || paymentIntentId == null || publishableKey == null) {
      state = state.copyWith(status: PaymentStatus.error, error: 'Missing payment credentials');
      return false;
    }

    state = state.copyWith(paymentIntentId: paymentIntentId, clientSecret: clientSecret);

    // Step 2: Open web payment page in browser
    final baseUrl = ApiService.instance.baseUrl.replaceAll('/api', '');
    final payUrl = Uri.parse('$baseUrl/pay/').replace(queryParameters: {
      'client_secret': clientSecret,
      'publishable_key': publishableKey,
      'amount': amountCents.toString(),
      'currency': currency,
      'pi_id': paymentIntentId,
      'ref': conversationRef,
      'name': state.targetName ?? '',
    });

    final callbackUrl = await FlutterWebAuth2.authenticate(
      url: payUrl.toString(),
      callbackUrlScheme: 'portraitor',
    );

    // Step 3: Parse the callback
    final uri = Uri.parse(callbackUrl);

    if (uri.host == 'payment-cancel') {
      state = state.copyWith(status: PaymentStatus.idle, error: null);
      return false;
    }

    if (uri.host == 'payment-success') {
      // Step 4: Verify server-side (never trust redirect alone)
      final verification = await ApiService.instance.verifyPayment(
        paymentIntentId: paymentIntentId,
      );
      final verifyData = verification['data'] as Map<String, dynamic>? ?? verification;
      final paid = verifyData['paid'] == true;

      if (paid) {
        state = state.copyWith(status: PaymentStatus.authorized);
        return true;
      }

      state = state.copyWith(status: PaymentStatus.error, error: 'Payment not confirmed');
      return false;
    }

    state = state.copyWith(status: PaymentStatus.error, error: 'Unexpected payment response');
    return false;
  } on ApiException catch (e) {
    state = state.copyWith(status: PaymentStatus.error, error: e.message);
    return false;
  } catch (e) {
    state = state.copyWith(status: PaymentStatus.error, error: e.toString());
    return false;
  }
}
```

**Keep `initiateDemo()` unchanged** — still works for testing without payment.

---

### Step 5: Update payment screen UI (~5 min)

**File:** `lib/screens/payment_screen.dart`

Changes:
- Remove `_AcceptedCards` widget (VISA/MC/AMEX badges) — cards shown on web page now
- Remove "SECURED BY stripe" trust badge — shown on web page now
- Keep: email field (REQUIRED), receipt card, price breakdown, Pay button
- Update trust copy to: "You'll be redirected to a secure payment page"
- Pay button label: "Pay $X.XX" (unchanged)
- Add: handle cancel state (user closed browser without paying)

---

### Step 6: Keep `stripe_service.dart` (~0 min)

**No action.** Keep as dead code for fallback. Don't import it in the new payment flow.

---

## Testing Checklist

### Simulator testing (staging)
- [ ] Pay button → opens web browser with payment page
- [ ] Payment page shows correct amount and target name
- [ ] Test card `4242 4242 4242 4242` → success → deep link returns → processing starts
- [ ] Test card `4000 0027 6000 3184` → 3D Secure challenge → success
- [ ] Test card `4000 0000 0000 0002` → decline → error shown, retry works
- [ ] Cancel on web page → `portraitor://payment-cancel` → user can retry
- [ ] Close browser without paying → user can retry
- [ ] Empty email → blocked before opening browser
- [ ] Invalid email → blocked before opening browser
- [ ] Server-side verification happens before processing starts

### Edge cases
- [ ] Slow network: payment page still loads
- [ ] User switches apps during payment: can resume
- [ ] Multiple rapid taps on Pay: only one browser opens

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Apple rejects web payment | `flutter_stripe` kept as fallback — can revert in 1 hour |
| Deep link not caught | Pay page has "Open Portraitor" fallback button |
| User pays but deep link fails | Server-side verification + webhook ensures payment is tracked |
| Network error during verify | Retry verification, show error with retry button |

---

## Files Changed Summary

| File | Change |
|------|--------|
| `pubspec.yaml` | Add `flutter_web_auth_2` |
| `ios/Runner/Info.plist` | Add `portraitor://` scheme |
| `android/app/src/main/AndroidManifest.xml` | Add `portraitor://` intent-filter |
| `lib/providers/payment_provider.dart` | Rewrite `initiatePayment()` to use web flow |
| `lib/screens/payment_screen.dart` | Remove Stripe UI, update trust copy |

**Total estimated effort: ~20 minutes**
